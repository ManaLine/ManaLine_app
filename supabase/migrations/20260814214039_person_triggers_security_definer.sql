-- Both persons triggers were SECURITY INVOKER, so they ran as whoever wrote
-- the row. service_role has no USAGE on the `app` schema, so every insert from
-- auth-register died with "42501: permission denied for schema app" — and
-- because the failure was inside a BEFORE trigger it surfaced as a generic
-- "Could not create account", not as anything naming a permission.
--
-- This had been true since the name-split migration. It went unnoticed because
-- the probes that proved those triggers ran as a superuser over the MCP
-- connection, which has USAGE on everything. The lesson is in the CLAUDE.md
-- rule already: invoke it before believing it — and invoke it AS THE ROLE THAT
-- WILL CALL IT.
--
-- SECURITY DEFINER is the right answer rather than granting service_role USAGE:
-- these two triggers must fire identically for every writer — the edge
-- function, an Owner over RLS, a migration RPC — and composing a name or
-- hashing an Aadhaar is not a privilege the caller should need to hold.

CREATE OR REPLACE FUNCTION app.sync_person_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_trimmed TEXT;
  v_first   TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.surname, '') <> '' OR COALESCE(NEW.given_name, '') <> '' THEN
      NEW.full_name := btrim(COALESCE(NEW.surname, '') || ' ' || COALESCE(NEW.given_name, ''));
      RETURN NEW;
    END IF;
  ELSE
    IF NEW.surname    IS DISTINCT FROM OLD.surname
    OR NEW.given_name IS DISTINCT FROM OLD.given_name THEN
      NEW.full_name := btrim(COALESCE(NEW.surname, '') || ' ' || COALESCE(NEW.given_name, ''));
      RETURN NEW;
    END IF;
    IF NEW.full_name IS NOT DISTINCT FROM OLD.full_name THEN
      RETURN NEW;
    END IF;
  END IF;

  v_trimmed := btrim(COALESCE(NEW.full_name, ''));
  v_first   := split_part(v_trimmed, ' ', 1);
  NEW.surname    := v_first;
  NEW.given_name := btrim(substr(v_trimmed, length(v_first) + 1));
  NEW.full_name  := v_trimmed;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.hash_person_aadhaar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_hash TEXT;
BEGIN
  IF NEW.aadhaar_number IS NULL THEN
    RETURN NEW;
  END IF;

  v_hash := app.aadhaar_hash(NEW.aadhaar_number);
  IF v_hash IS NULL THEN
    RAISE EXCEPTION 'Aadhaar must be 12 digits' USING ERRCODE = '22023';
  END IF;

  NEW.aadhaar_hash  := v_hash;
  NEW.aadhaar_last4 := right(regexp_replace(NEW.aadhaar_number, '[^0-9]', '', 'g'), 4);
  NEW.aadhaar_number := NULL;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.clear_aadhaar_on_erasure()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.aadhaar_hash  := NULL;
  NEW.aadhaar_last4 := NULL;
  RETURN NEW;
END;
$$;

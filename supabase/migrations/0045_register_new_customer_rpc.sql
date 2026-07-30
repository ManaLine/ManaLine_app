-- MANA LINE — 0045_register_new_customer_rpc.sql
--
-- Closes the confirmed gap in OW-004's "create new identity" path: the
-- previous client code did a raw INSERT into persons (blocked — no
-- client insert policy exists there, same as every other identity
-- creation this session) AND left mlid as a literal empty string
-- (would violate the UNIQUE/NOT NULL constraint on every attempt).
--
-- Aadhaar is now OPTIONAL, per explicit request: if given, MLID is MLPI
-- (permanent individual, matches the pattern used everywhere else this
-- session); if not given, MLID is MLTI (temporary individual) — the
-- other half of mlid_type_enum, which existed in the schema from day one
-- but was never actually used by any registration path until now.
--
-- MLTI has no natural "last 8 digits of Aadhaar" to derive from, so it's
-- built from a random component instead — collision-checked with a
-- bounded retry loop (unlike register_new_agent's MLPI derivation, which
-- is fully deterministic and can't meaningfully retry — MLTI has no such
-- constraint, so a real retry loop IS the right pattern here).

CREATE OR REPLACE FUNCTION app.register_new_customer(
  p_business_id UUID,
  p_full_name VARCHAR,
  p_father_husband_name VARCHAR,
  p_gender_digit CHAR(1),
  p_mobile_number VARCHAR,
  p_aadhaar_number VARCHAR DEFAULT NULL,
  p_door_no VARCHAR DEFAULT NULL,
  p_pin_code VARCHAR DEFAULT NULL,
  p_village_id UUID DEFAULT NULL
)
RETURNS UUID -- returns the new customer_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_mlid VARCHAR(13);
  v_mlid_type mlid_type_enum;
  v_person_id BIGINT;
  v_membership_id UUID;
  v_customer_id UUID;
  v_attempt INT := 0;
  v_last8 VARCHAR(8);
  v_mandal VARCHAR(100);
  v_district VARCHAR(100);
  v_state VARCHAR(100);
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  -- Hard duplicate check on Aadhaar, same as auth-register — never allow
  -- two persons rows for the same real Aadhaar.
  IF p_aadhaar_number IS NOT NULL AND EXISTS (
    SELECT 1 FROM persons WHERE aadhaar_number = p_aadhaar_number
  ) THEN
    RAISE EXCEPTION 'This Aadhaar Number is already associated with an existing account.' USING ERRCODE = '23505';
  END IF;

  IF p_aadhaar_number IS NOT NULL THEN
    -- MLPI — same deterministic derivation as register_new_agent.
    v_last8 := RIGHT(p_aadhaar_number, 8);
    v_mlid := 'MLPI' || p_gender_digit || v_last8;
    v_mlid_type := 'MLPI';
  ELSE
    -- MLTI — no natural deterministic source, so genuinely random with a
    -- real collision-retry loop (unlike MLPI, retrying here actually
    -- produces a different candidate each time).
    v_mlid_type := 'MLTI';
    LOOP
      v_mlid := 'MLTI' || p_gender_digit || LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0');
      EXIT WHEN NOT EXISTS (SELECT 1 FROM persons WHERE mlid = v_mlid);
      v_attempt := v_attempt + 1;
      IF v_attempt > 10 THEN
        RAISE EXCEPTION 'Could not generate a unique MLTI after 10 attempts — extremely unlikely, contact support.';
      END IF;
    END LOOP;
  END IF;

  INSERT INTO persons (
    mlid, mlid_type, gender_digit, full_name, father_husband_name,
    mobile_number, aadhaar_number, registration_source, customer_type
  ) VALUES (
    v_mlid, v_mlid_type, p_gender_digit, p_full_name, p_father_husband_name,
    p_mobile_number, p_aadhaar_number, 'Owner', 'New'
  ) RETURNING person_id INTO v_person_id;

  -- Address — optional (Owner may add it later), but if a village was
  -- selected, derive mandal/district/state from locations, never free
  -- text (standing convention, same as everywhere else in this app).
  IF p_village_id IS NOT NULL AND p_door_no IS NOT NULL AND p_pin_code IS NOT NULL THEN
    SELECT mandal, district, state INTO v_mandal, v_district, v_state
    FROM locations WHERE location_id = p_village_id;

    IF v_mandal IS NULL THEN
      RAISE EXCEPTION 'Selected village could not be found.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, is_current, from_date)
    VALUES (v_person_id, p_door_no, p_pin_code, p_village_id, v_mandal, v_district, v_state, true, CURRENT_DATE);
  END IF;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Customer', 'Active', 'Not Required',
    'Direct Registration', app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  -- occupation is NOT NULL with no sensible default derivable from the
  -- minimal fields requested — 'Other-Custom' + an explicit placeholder
  -- note, editable later from the customer's profile, rather than
  -- silently guessing a real occupation category.
  INSERT INTO customers (membership_id, person_id, occupation, occupation_other_text, customer_since)
  VALUES (v_membership_id, v_person_id, 'Other-Custom', 'Not specified at creation', CURRENT_DATE)
  RETURNING customer_id INTO v_customer_id;

  RETURN v_customer_id;
END;
$$;

COMMENT ON FUNCTION app.register_new_customer(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, UUID) IS
  'Atomic new-customer creation (persons + person_addresses + business_members + customers), replacing the previous raw client insert that always failed (persons has no client INSERT policy) and left mlid as an empty string. Aadhaar optional: MLPI if given, MLTI (randomly generated, collision-retried) if not.';

GRANT EXECUTE ON FUNCTION app.register_new_customer(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, UUID) TO authenticated;

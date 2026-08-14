-- Stop storing Aadhaar numbers in the clear.
--
-- persons.aadhaar_number held all twelve digits as text on 30 of 37 rows, with
-- a UNIQUE index on the full number. It now holds nothing: writes are hashed
-- on the way in and the plaintext is discarded inside the same statement.
--
-- WHAT THIS DOES AND DOES NOT BUY, stated plainly so nobody reads more into it
-- than is there. It removes readable Aadhaar numbers from the table, from
-- backups, and from anyone who can run a SELECT. It is NOT a defence against
-- an attacker holding the database: an Aadhaar is twelve digits, so the whole
-- space can be hashed and compared offline in minutes. An unsalted digest of a
-- short numeric secret is obfuscation at rest, not protection, and the privacy
-- policy is being worded to match that rather than to overclaim. A keyed HMAC
-- with the key outside Postgres would be the real fix; it would also mean the
-- six functions that write this column could no longer do so.
--
-- BR-181 is untouched and still puts the last eight digits inside every MLPI.
-- That is a deliberate, separately-decided trade-off, not an oversight here.

CREATE OR REPLACE FUNCTION app.aadhaar_hash(p_aadhaar TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
SET search_path = ''
AS $$
  -- Normalised first: an Aadhaar copied off a card arrives as "1234 5678 9012"
  -- about as often as "123456789012", and those two must not hash differently
  -- or the same person registers twice.
  SELECT CASE
    WHEN regexp_replace(COALESCE(p_aadhaar, ''), '[^0-9]', '', 'g') ~ '^[0-9]{12}$'
    THEN encode(
           pg_catalog.sha256(
             pg_catalog.convert_to(
               regexp_replace(p_aadhaar, '[^0-9]', '', 'g'), 'UTF8')),
           'hex')
  END;
$$;

ALTER TABLE persons
  ADD COLUMN aadhaar_hash  TEXT,
  ADD COLUMN aadhaar_last4 VARCHAR(4);

COMMENT ON COLUMN persons.aadhaar_hash IS
  'SHA-256 of the normalised 12 digits. Identity matching only. See migration note on what hashing does and does not protect against.';
COMMENT ON COLUMN persons.aadhaar_last4 IS
  'Last four digits, for display (•••• •••• 1234). The only part kept readable.';
COMMENT ON COLUMN persons.aadhaar_number IS
  'WRITE-ONLY. Pass the full number here; the trigger hashes it and blanks this in the same statement. Always NULL at rest — never read it.';

UPDATE persons
   SET aadhaar_hash  = app.aadhaar_hash(aadhaar_number),
       aadhaar_last4 = right(regexp_replace(aadhaar_number, '[^0-9]', '', 'g'), 4)
 WHERE aadhaar_number IS NOT NULL;

-- ADDS ONLY, never clears. owner_update_member_identity writes
-- `aadhaar_number = COALESCE(p_aadhaar_number, aadhaar_number)`, and with the
-- plaintext always NULL that collapses to the parameter — so an Owner editing
-- only a phone number passes NULL here. Treating NULL as "clear it" would wipe
-- a person's Aadhaar on an unrelated edit.
CREATE OR REPLACE FUNCTION app.hash_person_aadhaar()
RETURNS TRIGGER
LANGUAGE plpgsql
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
  NEW.aadhaar_number := NULL;   -- the plaintext never reaches storage
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_hash_person_aadhaar
  BEFORE INSERT OR UPDATE OF aadhaar_number ON persons
  FOR EACH ROW EXECUTE FUNCTION app.hash_person_aadhaar();

-- Erasure has to take the hash with it. app.anonymise_person sets
-- aadhaar_number = NULL, which the trigger above deliberately ignores, so
-- without this the hash would outlive the right-to-erasure request — and a
-- hash still answers "was this Aadhaar ever registered here".
CREATE OR REPLACE FUNCTION app.clear_aadhaar_on_erasure()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.aadhaar_hash  := NULL;
  NEW.aadhaar_last4 := NULL;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_clear_aadhaar_on_erasure
  BEFORE UPDATE OF account_status ON persons
  FOR EACH ROW
  WHEN (NEW.account_status = 'Deleted' AND OLD.account_status <> 'Deleted')
  EXECUTE FUNCTION app.clear_aadhaar_on_erasure();

UPDATE persons SET aadhaar_number = NULL WHERE aadhaar_number IS NOT NULL;

-- Uniqueness moves to the hash. Same guarantee — one person per Aadhaar —
-- without the number.
ALTER TABLE persons DROP CONSTRAINT IF EXISTS persons_aadhaar_number_key;
DROP INDEX IF EXISTS persons_aadhaar_number_key;
CREATE UNIQUE INDEX persons_aadhaar_hash_key ON persons (aadhaar_hash);

-- The MLTI hard-key rule was written against the plaintext, which is now
-- always NULL — every MLTI person would have failed it on the next write.
ALTER TABLE persons DROP CONSTRAINT persons_mlti_needs_hard_key;
ALTER TABLE persons
  ADD CONSTRAINT persons_mlti_needs_hard_key CHECK (
    mlid_type <> 'MLTI'
    OR account_status = 'Deleted'
    OR aadhaar_hash IS NOT NULL
    OR mobile_number IS NOT NULL
  );

GRANT EXECUTE ON FUNCTION app.aadhaar_hash(TEXT) TO service_role;

-- Search by Aadhaar now compares hashes.
CREATE OR REPLACE FUNCTION app.owner_search_person(
  p_mlid text DEFAULT NULL::text,
  p_mobile_number text DEFAULT NULL::text,
  p_aadhaar_number text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text)
 RETURNS TABLE(person_id bigint, full_name character varying, father_husband_name character varying, mobile_number character varying, mlid character varying)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'app'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  IF p_mlid IS NOT NULL AND p_mlid <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
  ELSIF p_aadhaar_number IS NOT NULL AND p_aadhaar_number <> '' THEN
    -- Hash the search term and compare digests. The caller still passes the
    -- number the Owner typed; it is hashed here and never stored.
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.aadhaar_hash = app.aadhaar_hash(p_aadhaar_number) LIMIT 1;
  ELSIF p_mobile_number IS NOT NULL AND p_mobile_number <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mobile_number = p_mobile_number LIMIT 1;
  ELSIF p_full_name IS NOT NULL AND p_full_name <> '' THEN
    -- Many rows, shortest first so an exact-ish match leads. Capped at 25:
    -- this feeds a bottom sheet, not a report.
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p
      WHERE p.full_name ILIKE '%' || p_full_name || '%'
      ORDER BY length(p.full_name), p.full_name
      LIMIT 25;
  END IF;
END;
$function$;

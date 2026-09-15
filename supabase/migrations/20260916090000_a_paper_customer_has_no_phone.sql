-- A customer from a paper book may have neither phone nor Aadhaar.
--
-- THE BUG. Adding a customer with both contact fields blank threw:
--
--   new row for relation "persons" violates check constraint
--   "persons_mlti_needs_hard_key"
--
-- straight from Postgres, onto a doorstep screen, in English, quoting a
-- constraint name. app.mint_person_mlid() issues an MLTI -- a TEMPORARY
-- identity -- when there is no Aadhaar, and persons_mlti_needs_hard_key
-- requires an MLTI row to carry an Aadhaar hash, a mobile number, is_migrated,
-- or Deleted status. A paper-book customer has none of those.
--
-- WHY IT SURVIVED A FIX. register_new_agent and register_new_investor BOTH
-- already handle this, with the same one-line test:
--
--   IF NULLIF(p_aadhaar_number,'') IS NULL AND NOT app.migration_import_active()
--     THEN RAISE ... 'Aadhaar Number is required to register an Agent'
--
-- register_new_customer never mentioned the migration context at all. Three
-- sibling RPCs, two taught and one left behind -- the exact shape CLAUDE.md
-- describes: a change correct in itself, verified in isolation, reported as
-- done, while a third consumer went on as before. It was reported fixed once
-- and came back because "fixed" had meant "fixed for agents and investors".
--
-- THE RULE, decided 2026-09-16: allowed ONLY inside a migration import,
-- refused otherwise. A customer registered normally at a doorstep still needs
-- a way to be reached; a customer copied out of a ten-year-old ledger may
-- genuinely have neither, and refusing that would make the book unenterable.
--
-- p_migration_entry is what the one-by-one screens pass, and it is not a
-- loophole: app.is_owner() is checked above it and app.migration_assert_open()
-- below it, so it can only be used by the Owner of a business whose migration
-- is genuinely still open -- the same bar app.import_migrated_identities sets
-- for the bulk path. A client that passes true outside those conditions gets
-- the same refusal it would have got anyway.
--
-- The condition is written `NOT app.migration_import_active()` rather than
-- `NOT p_migration_entry` ON PURPOSE: the two existing SQL callers
-- (20260807074903 and 20260817151200, both inside the bulk import) already run
-- with the GUC on and pass no such argument. Reading the GUC means they keep
-- working untouched instead of needing the flag threaded through them.
--
-- DROP then CREATE because the parameter list changes -- CREATE OR REPLACE
-- would leave a second overload and PostgREST would answer PGRST203.
DROP FUNCTION IF EXISTS app.register_new_customer(
  UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, UUID,
  NUMERIC, NUMERIC, NUMERIC);

CREATE FUNCTION app.register_new_customer(
  p_business_id       UUID,
  p_full_name         VARCHAR,
  p_father_husband_name VARCHAR,
  p_gender_digit      CHAR,
  p_mobile_number     VARCHAR,
  p_aadhaar_number    VARCHAR DEFAULT NULL,
  p_door_no           VARCHAR DEFAULT NULL,
  p_pin_code          VARCHAR DEFAULT NULL,
  p_village_id        UUID    DEFAULT NULL,
  p_gps_latitude      NUMERIC DEFAULT NULL,
  p_gps_longitude     NUMERIC DEFAULT NULL,
  p_gps_accuracy_m    NUMERIC DEFAULT NULL,
  p_migration_entry   BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_mlid VARCHAR(13);
  v_mlid_type mlid_type_enum;
  v_person_id BIGINT;
  v_membership_id UUID;
  v_customer_id UUID;
  v_mandal VARCHAR(100);
  v_district VARCHAR(100);
  v_state VARCHAR(100);
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized - Owner only' USING ERRCODE = '42501';
  END IF;

  -- Transaction-local, and only after the two checks above it: it dies with
  -- this statement, so nothing outside a migration entry is ever stamped.
  -- Stamped whether or not a hard key was supplied, matching the bulk import,
  -- which marks every person it creates -- a migrated customer who happens to
  -- have a phone is still a migrated customer.
  IF p_migration_entry THEN
    PERFORM app.migration_assert_open(p_business_id);
    PERFORM set_config('app.migration_import', 'on', true);
  END IF;

  IF NULLIF(p_mobile_number, '') IS NULL
     AND NULLIF(p_aadhaar_number, '') IS NULL
     AND NOT app.migration_import_active() THEN
    RAISE EXCEPTION 'A customer needs a mobile number or an Aadhaar number. Only a customer being brought across from an existing book can have neither.'
      USING ERRCODE = '23514';
  END IF;

  SELECT o_mlid, o_mlid_type INTO v_mlid, v_mlid_type
    FROM app.mint_person_mlid(p_gender_digit, NULLIF(p_aadhaar_number, ''));

  INSERT INTO persons (
    mlid, mlid_type, gender_digit, full_name, father_husband_name,
    mobile_number, aadhaar_number, registration_source, customer_type
  ) VALUES (
    v_mlid, v_mlid_type, p_gender_digit, p_full_name, p_father_husband_name,
    NULLIF(p_mobile_number, ''), NULLIF(p_aadhaar_number, ''), 'Owner', 'New'
  ) RETURNING person_id INTO v_person_id;

  -- Address - optional. Mandal/district/state are derived from locations,
  -- never free text (standing convention). Door number is optional now: a
  -- migrated customer's paper record rarely has one.
  IF p_village_id IS NOT NULL AND NULLIF(p_pin_code, '') IS NOT NULL THEN
    SELECT mandal, district, state INTO v_mandal, v_district, v_state
    FROM locations WHERE location_id = p_village_id;

    IF v_mandal IS NULL THEN
      RAISE EXCEPTION 'Selected village could not be found.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO person_addresses (
      person_id, door_no, pin_code, village_id, mandal, district, state,
      is_current, from_date,
      gps_latitude, gps_longitude, gps_accuracy_m, gps_captured_at
    ) VALUES (
      v_person_id, NULLIF(p_door_no, ''), p_pin_code, p_village_id, v_mandal, v_district, v_state,
      true, CURRENT_DATE,
      p_gps_latitude, p_gps_longitude, p_gps_accuracy_m,
      CASE WHEN p_gps_latitude IS NOT NULL THEN now() END
    );
  END IF;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Customer', 'Active', 'Not Required',
    app.onboarding_method_now(), app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO customers (membership_id, person_id, occupation, occupation_other_text, customer_since)
  VALUES (v_membership_id, v_person_id, 'Other-Custom', 'Not specified at creation', CURRENT_DATE)
  RETURNING customer_id INTO v_customer_id;

  RETURN v_customer_id;
END;
$function$;

COMMENT ON FUNCTION app.register_new_customer(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, UUID, NUMERIC, NUMERIC, NUMERIC, BOOLEAN) IS
  'Creates a Customer identity, membership and customer row. A customer with neither mobile nor Aadhaar is refused UNLESS p_migration_entry is true (Owner + migration open) or the caller is already inside a bulk migration import -- an MLTI person needs a hard key per persons_mlti_needs_hard_key.';

GRANT EXECUTE ON FUNCTION app.register_new_customer(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, UUID, NUMERIC, NUMERIC, NUMERIC, BOOLEAN) TO authenticated;

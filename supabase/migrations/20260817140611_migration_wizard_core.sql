-- Pre-existing-business migration, part A: the schema relaxations the wizard
-- needs, plus two identity bugs the Aadhaar-hashing change left behind.
--
-- WHY is_migrated is a column and not a lookup: persons_mlti_needs_hard_key is
-- a table CHECK, and a CHECK cannot see business_members. A migrated person may
-- legitimately have neither phone nor Aadhaar (an owner's paper ledger records
-- neither), so the row has to carry its own exemption. It is stamped by a
-- trigger from a transaction-local GUC rather than passed in, so no caller can
-- set it by accident and self-registration is untouched.

-- ---------------------------------------------------------------------------
-- Gender: Others
-- ---------------------------------------------------------------------------
ALTER TABLE public.persons DROP CONSTRAINT IF EXISTS persons_gender_digit_check;
ALTER TABLE public.persons ADD CONSTRAINT persons_gender_digit_check
  CHECK (gender_digit IN ('0', '1', '2'));

COMMENT ON COLUMN public.persons.gender_digit IS
  'MLID gender digit: 1 Male, 0 Female, 2 Others.';

-- ---------------------------------------------------------------------------
-- Migrated rows
-- ---------------------------------------------------------------------------
ALTER TABLE public.persons
  ADD COLUMN IF NOT EXISTS is_migrated boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION app.migration_import_active() RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $$
  SELECT COALESCE(current_setting('app.migration_import', true), '') = 'on';
$$;

CREATE OR REPLACE FUNCTION app.stamp_migrated_person() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
  IF app.migration_import_active() THEN
    NEW.is_migrated := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_migrated_person ON public.persons;
CREATE TRIGGER trg_stamp_migrated_person
  BEFORE INSERT ON public.persons
  FOR EACH ROW EXECUTE FUNCTION app.stamp_migrated_person();

ALTER TABLE public.persons DROP CONSTRAINT IF EXISTS persons_mlti_needs_hard_key;
ALTER TABLE public.persons ADD CONSTRAINT persons_mlti_needs_hard_key CHECK (
  mlid_type <> 'MLTI'::mlid_type_enum
  OR account_status = 'Deleted'::account_status_enum
  OR aadhaar_hash IS NOT NULL
  OR mobile_number IS NOT NULL
  OR is_migrated
);

-- A migrated customer's address comes off a paper ledger: village and PIN are
-- known, a door number usually is not.
ALTER TABLE public.person_addresses ALTER COLUMN door_no DROP NOT NULL;

-- No guarantors in the migration path at all, so every guarantor detail has to
-- be optional for a loan to exist without one.
ALTER TABLE public.guarantors ALTER COLUMN guarantor_name DROP NOT NULL;
ALTER TABLE public.guarantors ALTER COLUMN relationship  DROP NOT NULL;
ALTER TABLE public.guarantors ALTER COLUMN phone         DROP NOT NULL;
ALTER TABLE public.guarantors ALTER COLUMN address       DROP NOT NULL;

-- ---------------------------------------------------------------------------
-- MLID minting, in one place
--
-- Was copied three times, and two of the copies carried the same dead check:
-- `WHERE aadhaar_number = p_aadhaar_number` can never match now that
-- trg_hash_person_aadhaar nulls aadhaar_number out on write, so a duplicate
-- Aadhaar produced a raw unique-index error at best. It compares hashes here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.mint_person_mlid(
  p_gender_digit character,
  p_aadhaar_number character varying,
  OUT o_mlid character varying,
  OUT o_mlid_type mlid_type_enum
) LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
DECLARE
  v_attempt INT := 0;
  v_digits  TEXT;
BEGIN
  IF p_aadhaar_number IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM persons WHERE aadhaar_hash = app.aadhaar_hash(p_aadhaar_number)
    ) THEN
      RAISE EXCEPTION 'This Aadhaar Number is already associated with an existing account.'
        USING ERRCODE = '23505';
    END IF;

    v_digits := regexp_replace(p_aadhaar_number, '[^0-9]', '', 'g');
    IF length(v_digits) <> 12 THEN
      RAISE EXCEPTION 'Aadhaar must be 12 digits' USING ERRCODE = '22023';
    END IF;

    o_mlid := 'MLPI' || p_gender_digit || RIGHT(v_digits, 8);
    o_mlid_type := 'MLPI';

    IF EXISTS (SELECT 1 FROM persons WHERE mlid = o_mlid) THEN
      RAISE EXCEPTION 'MLID collision: the last 8 digits of this Aadhaar number, combined with gender, already match a different existing person. This is a rare coincidence, not a duplicate - please contact support to resolve manually.'
        USING ERRCODE = '23505';
    END IF;
  ELSE
    o_mlid_type := 'MLTI';
    LOOP
      o_mlid := 'MLTI' || p_gender_digit || LPAD(FLOOR(RANDOM() * 100000000)::TEXT, 8, '0');
      EXIT WHEN NOT EXISTS (SELECT 1 FROM persons WHERE mlid = o_mlid);
      v_attempt := v_attempt + 1;
      IF v_attempt > 10 THEN
        RAISE EXCEPTION 'Could not generate a unique MLTI after 10 attempts - extremely unlikely, contact support.';
      END IF;
    END LOOP;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION app.onboarding_method_now() RETURNS onboarding_method_enum
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN app.migration_import_active()
              THEN 'Migration/Pre-Existing'::onboarding_method_enum
              ELSE 'Direct Registration'::onboarding_method_enum END;
$$;

-- ---------------------------------------------------------------------------
-- The three registrars, now sharing the minting rules
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.register_new_customer(
  p_business_id uuid,
  p_full_name character varying,
  p_father_husband_name character varying,
  p_gender_digit character,
  p_mobile_number character varying,
  p_aadhaar_number character varying DEFAULT NULL::character varying,
  p_door_no character varying DEFAULT NULL::character varying,
  p_pin_code character varying DEFAULT NULL::character varying,
  p_village_id uuid DEFAULT NULL::uuid,
  p_gps_latitude numeric DEFAULT NULL::numeric,
  p_gps_longitude numeric DEFAULT NULL::numeric,
  p_gps_accuracy_m numeric DEFAULT NULL::numeric
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
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
$$;

CREATE OR REPLACE FUNCTION app.register_new_agent(
  p_business_id uuid,
  p_full_name character varying,
  p_father_husband_name character varying,
  p_gender_digit character,
  p_mobile_number character varying,
  p_aadhaar_number character varying
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_mlid VARCHAR(13);
  v_mlid_type mlid_type_enum;
  v_person_id BIGINT;
  v_membership_id UUID;
  v_agent_id UUID;
  v_permission_profile_id UUID;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized - Owner only' USING ERRCODE = '42501';
  END IF;

  -- Aadhaar stays mandatory for a normally-registered Agent; only a migrated
  -- book is allowed to have neither Aadhaar nor phone.
  IF NULLIF(p_aadhaar_number, '') IS NULL AND NOT app.migration_import_active() THEN
    RAISE EXCEPTION 'Aadhaar Number is required to register an Agent' USING ERRCODE = '23514';
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

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Agent', 'Pending Invitation',
    'Pending Verification', app.onboarding_method_now(), app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO agents (membership_id, person_id, joined_date)
  VALUES (v_membership_id, v_person_id, CURRENT_DATE)
  RETURNING agent_id INTO v_agent_id;

  INSERT INTO agent_permissions (agent_id)
  VALUES (v_agent_id)
  RETURNING permission_profile_id INTO v_permission_profile_id;

  UPDATE business_members SET permission_profile_id = v_permission_profile_id
  WHERE membership_id = v_membership_id;

  RETURN v_agent_id;
END;
$$;

CREATE OR REPLACE FUNCTION app.register_new_investor(
  p_business_id uuid,
  p_full_name character varying,
  p_father_husband_name character varying,
  p_gender_digit character,
  p_mobile_number character varying,
  p_aadhaar_number character varying
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_mlid VARCHAR(13);
  v_mlid_type mlid_type_enum;
  v_person_id BIGINT;
  v_membership_id UUID;
  v_investor_id UUID;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized - Owner only' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(p_aadhaar_number, '') IS NULL AND NOT app.migration_import_active() THEN
    RAISE EXCEPTION 'Aadhaar Number is required to register an Investor' USING ERRCODE = '23514';
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

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Investor', 'Active', 'Not Required',
    app.onboarding_method_now(), app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO investors (membership_id, person_id)
  VALUES (v_membership_id, v_person_id)
  RETURNING investor_id INTO v_investor_id;

  RETURN v_investor_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.mint_person_mlid(character, character varying) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION app.migration_import_active() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION app.onboarding_method_now() TO authenticated, anon, service_role;

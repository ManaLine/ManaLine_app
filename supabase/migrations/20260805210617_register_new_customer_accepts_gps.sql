-- P2 GPS: register_new_customer takes the pin at creation.
--
-- The signature is EXTENDED rather than paired with a second "now attach the
-- GPS" call. A second call can fail on its own, which would leave a customer
-- whose address exists but whose pin silently does not -- and nothing would
-- report it, because the registration itself succeeded. One call, one
-- transaction, one outcome.
--
-- All three new parameters default to NULL, so every existing caller keeps
-- working untouched. GPS is never required: a denied permission, a phone with
-- location switched off, or a village with no sky view must not stop a
-- customer being registered. The address is written exactly as before and the
-- pin columns simply stay empty.
--
-- The pin is stored on person_addresses, NOT used to choose the village. Per
-- the pin-only decision (20260805141851), `locations` has no coordinates, so
-- there is nothing to resolve a village against -- the Owner still picks it.
--
-- SEE ALSO 20260805210700, which drops the old 9-argument signature. Adding
-- defaulted parameters via CREATE OR REPLACE creates a NEW overload rather
-- than replacing the old one, and the two then collide.
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
  p_gps_latitude numeric DEFAULT NULL,
  p_gps_longitude numeric DEFAULT NULL,
  p_gps_accuracy_m numeric DEFAULT NULL
)
RETURNS uuid
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
    -- real collision-retry loop.
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

    INSERT INTO person_addresses (
      person_id, door_no, pin_code, village_id, mandal, district, state,
      is_current, from_date,
      gps_latitude, gps_longitude, gps_accuracy_m, gps_captured_at
    )
    VALUES (
      v_person_id, p_door_no, p_pin_code, p_village_id, v_mandal, v_district, v_state,
      true, CURRENT_DATE,
      p_gps_latitude, p_gps_longitude, p_gps_accuracy_m,
      -- Only stamped when there is actually a fix, so a NULL captured_at
      -- means "never captured" rather than "captured nothing".
      CASE WHEN p_gps_latitude IS NOT NULL THEN now() END
    );
  END IF;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Customer', 'Active', 'Not Required',
    'Direct Registration', app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO customers (membership_id, person_id, occupation, occupation_other_text, customer_since)
  VALUES (v_membership_id, v_person_id, 'Other-Custom', 'Not specified at creation', CURRENT_DATE)
  RETURNING customer_id INTO v_customer_id;

  RETURN v_customer_id;
END;
$function$;

-- MANA LINE — Create Platform Admin: Karri Siri Manikanta Reddy
-- Run manually via SQL Editor. Idempotent — safe to re-run.
--
-- ASSUMPTION FLAGGED: gender_digit assumed '1' (Male) from the given name
-- pattern ("Manikanta Reddy") — not explicitly provided. Confirm before
-- running if this matters to you; harmless either way for platform_admins
-- purposes (gender_digit only affects the derived MLID format).
--
-- "Full permissions" = present in `platform_admins`, which is the only
-- gate that exists (SP-001's app.is_platform_admin() checks membership in
-- this table — it's boolean, not tiered). This does NOT create any
-- Owner/Agent/Investor/Customer business_members role for this identity —
-- those are separate, added the normal way (an Owner adds them by MLID,
-- or they self-register into a business) if you want this identity to
-- ALSO hold a business role somewhere.

DO $$
DECLARE
  v_person_id BIGINT;
  v_mlid VARCHAR(13);
BEGIN
  -- Check for an existing person by mobile OR Aadhaar first — this exact
  -- identity may already exist from earlier testing this session.
  SELECT person_id INTO v_person_id
  FROM persons
  WHERE mobile_number = '9493509919' OR aadhaar_number = '288942496232'
  LIMIT 1;

  IF v_person_id IS NULL THEN
    v_mlid := 'MLPI1' || '42496232'; -- 'MLPI' + gender_digit('1') + last-8-of-Aadhaar
    INSERT INTO persons (
      mlid, mlid_type, gender_digit, full_name, father_husband_name,
      mobile_number, aadhaar_number, registration_source, customer_type,
      profile_status
    ) VALUES (
      v_mlid, 'MLPI', '1', 'Karri Siri Manikanta Reddy', 'Not Provided',
      '9493509919', '288942496232', 'System', 'New',
      'Incomplete' -- father_husband_name wasn't provided — flagged, edit later if needed
    )
    RETURNING person_id INTO v_person_id;

    -- Address, since one was provided (door_no/pin_code/village).
    -- Resolves village_id via the real locations table — never free text.
    INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, is_current, from_date)
    SELECT v_person_id, '3-1/2', '533261', l.location_id, l.mandal, l.district, l.state, true, CURRENT_DATE
    FROM locations l
    WHERE l.pin_code = '533261' AND l.village_town_name = 'Someswaram'
    LIMIT 1;

    RAISE NOTICE 'Created new person_id % with mlid %', v_person_id, v_mlid;
  ELSE
    RAISE NOTICE 'Person already exists — person_id %, reusing.', v_person_id;
  END IF;

  -- Grant Platform Admin — idempotent (ON CONFLICT DO NOTHING avoids a
  -- duplicate-row error if this script is re-run for the same person).
  INSERT INTO platform_admins (person_id)
  VALUES (v_person_id)
  ON CONFLICT (person_id) DO NOTHING;

  RAISE NOTICE 'person_id % is now a Platform Admin (or already was).', v_person_id;
END $$;

-- Verify:
-- SELECT p.person_id, p.mlid, p.full_name, p.mobile_number
-- FROM persons p JOIN platform_admins pa ON pa.person_id = p.person_id
-- WHERE p.mobile_number = '9493509919';

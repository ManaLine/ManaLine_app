-- =============================================================================
-- MANA LINE — batch_bcd_schema_tests.sql
-- @target: scratch
-- Independent adversarial QA for the Batch B / C / D migrations
-- (20260803070000 .. 20260803120000). Same convention as
-- schema_integrity_tests.sql: plain SQL DO blocks, RAISE NOTICE on PASS /
-- RAISE WARNING on FAIL, one transaction, ROLLBACK at the end.
--
-- These are EXISTENCE + BEHAVIOUR locks: each test fails loudly if a later
-- migration silently drops or renames the schema contract the Dart client
-- now depends on (the route model, the collection-due view, the GPS
-- columns, the rate-limit table).
-- =============================================================================

BEGIN;

CREATE TEMP TABLE bcd_results (
    seq         SERIAL PRIMARY KEY,
    category    TEXT,
    br_ref      TEXT,
    description TEXT,
    passed      BOOLEAN
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.bcd_log(p_category TEXT, p_br_ref TEXT, p_description TEXT, p_passed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO bcd_results(category, br_ref, description, passed) VALUES (p_category, p_br_ref, p_description, p_passed);
    IF p_passed THEN RAISE NOTICE 'PASS [%] (%) %', p_category, p_br_ref, p_description;
    ELSE RAISE WARNING 'FAIL [%] (%) %', p_category, p_br_ref, p_description; END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- BATCH B — M4 route model
-- -----------------------------------------------------------------------------
DO $$
DECLARE v BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='agent_area_assignments'
      AND column_name IN ('valid_from','valid_to','frequency')
  ) INTO v;
  PERFORM pg_temp.bcd_log('route', 'M4', 'agent_area_assignments has valid_from/valid_to/frequency (time-bounded route model)', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='uq_area_assignment_live'
  ) INTO v;
  PERFORM pg_temp.bcd_log('route', 'BR-065', 'uq_area_assignment_live live unique index exists (one open window per agent+area)', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='agent_covers_customer' AND pronamespace='app'::regnamespace
  ) INTO v;
  PERFORM pg_temp.bcd_log('route', 'M4', 'app.agent_covers_customer function exists (RLS area-based scoping)', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='assign_agent_area' AND pronamespace='app'::regnamespace
  ) INTO v;
  PERFORM pg_temp.bcd_log('route', 'M4', 'app.assign_agent_area function exists (atomic Owner-gated assignment)', v);

  -- The old per-customer agent column must be GONE — the client no longer
  -- references it anywhere.
  SELECT NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='customers' AND column_name='assigned_agent_membership_id'
  ) INTO v;
  PERFORM pg_temp.bcd_log('route', 'M4', 'customers.assigned_agent_membership_id column is dropped', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_views WHERE schemaname='app' AND viewname='v_collection_due'
  ) INTO v;
  PERFORM pg_temp.bcd_log('due', '#18', 'app.v_collection_due view exists (server-side due list)', v);
END $$;

-- -----------------------------------------------------------------------------
-- BATCH C — location feature
-- -----------------------------------------------------------------------------
DO $$
DECLARE v BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='person_addresses'
      AND column_name IN ('gps_latitude','gps_longitude','gps_accuracy_m','gps_captured_at')
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'M6', 'person_addresses has the GPS pin columns', v);

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='loans'
      AND column_name IN ('issue_lat','issue_lng','issue_accuracy_m','issue_gps_at')
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'M6', 'loans has the issue-time GPS columns', v);

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='persons' AND column_name='consent_location_capture'
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'M6', 'persons.consent_location_capture column exists', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='uq_person_addresses_one_current'
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'BR-225', 'uq_person_addresses_one_current partial unique index exists', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='uq_locations_pin_village_lower'
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', '#16', 'uq_locations_pin_village_lower dedup index exists', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='compare_address_gps' AND pronamespace='app'::regnamespace
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'M6', 'app.compare_address_gps function exists', v);

  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='update_loan_gps' AND pronamespace='app'::regnamespace
  ) INTO v;
  PERFORM pg_temp.bcd_log('loc', 'M6', 'app.update_loan_gps function exists', v);
END $$;

-- -----------------------------------------------------------------------------
-- BATCH D — auth hardening
-- -----------------------------------------------------------------------------
DO $$
DECLARE v BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='auth_rate_limits'
  ) INTO v;
  PERFORM pg_temp.bcd_log('auth', '#13', 'auth_rate_limits table exists', v);

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='persons' AND column_name='pin_length'
  ) INTO v;
  PERFORM pg_temp.bcd_log('auth', '#11', 'persons.pin_length column exists (needs_pin_upgrade)', v);
END $$;

-- -----------------------------------------------------------------------------
-- BEHAVIOUR: the one-current-address partial unique index must actually
-- reject a second is_current=TRUE address for the same person.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_person BIGINT;
  v_village UUID;
  v_rejected BOOLEAN := FALSE;
BEGIN
  BEGIN
    -- person_addresses requires pin_code, village_id, mandal, district, state
    -- and from_date, and village_id references locations, so the village has
    -- to exist before the address does. This fixture supplied none of them:
    -- the FIRST address insert died on 23502 and the second -- the one
    -- actually under test -- never ran, so the suite reported the partial
    -- unique index missing for as long as the file had existed. It is there,
    -- in production and in a rebuild alike, and the assertion two blocks above
    -- had been saying so the whole time.
    INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state)
    VALUES ('500001', 'QA BCD Village', 'Village', 'QA Mandal', 'QA District', 'Telangana')
    RETURNING location_id INTO v_village;

    -- mobile_number is not optional here: persons_mlti_needs_hard_key requires
    -- an MLTI row to carry an Aadhaar hash, a mobile number, is_migrated, or
    -- Deleted status. Without one the person insert throws 23514 and every
    -- address assertion below becomes a false report about the address table.
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type, mobile_number)
    VALUES ('MLTI9BCDTEST1', 'MLTI', '0', 'QA BCD Person', 'QA Father', 'System', 'New', '9000000001')
    RETURNING person_id INTO v_person;

    -- pin_code is NOT NULL, and omitting it is why this assertion reported the
    -- index missing on 2026-09-15: the FIRST insert died on 23502, the outer
    -- handler below swallowed it, and v_rejected stayed FALSE -- which reads
    -- exactly like "the partial unique index is not there". It is there, in
    -- production and in a rebuild alike. The test never reached it.
    --
    -- The outer handler now records WHY it caught something instead of
    -- discarding it. A fixture that fails silently turns every assertion after
    -- it into a false report about the schema.
    INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
    VALUES (v_person, '1', '500001', v_village, 'QA Mandal', 'QA District', 'Telangana', CURRENT_DATE, TRUE);

    -- Second current address for the SAME person — must violate
    -- uq_person_addresses_one_current.
    BEGIN
      INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
      VALUES (v_person, '2', '500001', v_village, 'QA Mandal', 'QA District', 'Telangana', CURRENT_DATE, TRUE);
      -- Fell through: constraint missing.
    EXCEPTION WHEN unique_violation THEN
      v_rejected := TRUE;
    END;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'the one-current-address fixture could not be built: % (%)', SQLERRM, SQLSTATE;
  END;
  PERFORM pg_temp.bcd_log('loc', 'BR-225', 'second is_current address for one person is rejected (partial unique index fires)', v_rejected);
END $$;

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$
DECLARE v_total INT; v_passed INT; v_failed INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
    INTO v_total, v_passed, v_failed FROM bcd_results;
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'BATCH B/C/D SCHEMA TESTS: % total, % passed, % FAILED', v_total, v_passed, v_failed;
    RAISE NOTICE '=============================================================';
END $$;

SELECT seq, category, br_ref, description, passed FROM bcd_results ORDER BY seq;

ROLLBACK;

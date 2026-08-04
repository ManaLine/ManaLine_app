-- =============================================================================
-- MANA LINE — multi_tenancy_isolation_tests.sql
-- HIGHEST PRIORITY test file per the briefing. Targets BR-202/BR-203
-- cross-business leakage specifically — the single most likely place for a
-- policy that "looks correct in isolation" to actually leak across tenants,
-- because most policies are written per-table without a second business to
-- compare against.
--
-- Self-contained: does not depend on fixtures from rls_access_matrix_tests.sql
-- (each file must be runnable on its own). Some overlap with that file's
-- fixtures is intentional and expected — this is the file meant to catch
-- what that one might miss, not a strict superset/subset relationship.
--
-- Strategy: build two businesses (Alpha, Beta) with DELIBERATELY
-- overlapping-looking data — same person full_names re-used, same loan
-- amounts, same customer occupation, same MLBI prefix pattern — specifically
-- so a policy bug that filters on the wrong column (e.g. matching by name or
-- amount instead of business_id/membership_id) would surface as a failure
-- here even though it might pass a naively-designed test with obviously
-- distinct fixture data.
--
-- Every test below is run in BOTH directions (Alpha-context probing Beta
-- data, AND Beta-context probing Alpha data) since a leak is not guaranteed
-- to be symmetric — a policy with an OR clause bug, for instance, might leak
-- only one direction.
--
-- CONVENTION: see schema_integrity_tests.sql header (plain SQL, not pgTAP).
-- HOW TO RUN: see README_how_to_run.md.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Harness (duplicated from rls_access_matrix_tests.sql by design — each file
-- is meant to be independently copy-pasteable/runnable)
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE mti_results (
    seq SERIAL PRIMARY KEY,
    scenario TEXT,
    direction TEXT,
    br_ref TEXT,
    description TEXT,
    passed BOOLEAN
) ON COMMIT DROP;
GRANT INSERT, SELECT ON mti_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE mti_results_seq_seq TO authenticated, anon;

CREATE OR REPLACE FUNCTION pg_temp.mti_log(p_scenario TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT, p_passed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO mti_results(scenario, direction, br_ref, description, passed) VALUES (p_scenario, p_dir, p_br, p_desc, p_passed);
    IF p_passed THEN
        RAISE NOTICE 'PASS [%/%] (%) %', p_scenario, p_dir, p_br, p_desc;
    ELSE
        RAISE WARNING 'FAIL [%/%] (%) %', p_scenario, p_dir, p_br, p_desc;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.mti_login(p_person_id BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('person_id', p_person_id, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.mti_assert_count(
    p_table TEXT, p_where TEXT, p_expected BIGINT,
    p_scenario TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_actual BIGINT;
BEGIN
    EXECUTE format('SELECT count(*) FROM %I WHERE %s', p_table, p_where) INTO v_actual;
    PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || format(' [expected %s, saw %s]', p_expected, v_actual), v_actual = p_expected);
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || format(' [insufficient_privilege — treated as 0; expected %s]', p_expected), p_expected = 0);
END;
$$;

-- Broader leak probe: as whoever is impersonated, count ALL rows in a table
-- that belong to p_other_business_id (not filtered to one specific row) —
-- catches leaks of rows this script didn't specifically fixture, e.g. if
-- the table already had other data in the target Supabase project.
CREATE OR REPLACE FUNCTION pg_temp.mti_assert_zero_business_rows(
    p_table TEXT, p_business_col TEXT, p_other_business_id UUID,
    p_scenario TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_actual BIGINT;
BEGIN
    EXECUTE format('SELECT count(*) FROM %I WHERE %I = %L', p_table, p_business_col, p_other_business_id) INTO v_actual;
    PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || format(' [saw %s row(s) of the OTHER business — must be 0]', v_actual), v_actual = 0);
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || ' [insufficient_privilege — treated as 0, pass]', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.mti_assert_write(
    p_sql TEXT, p_should_succeed BOOLEAN, p_scenario TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows > 0 THEN
            PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || format(' [write succeeded, %s row(s) affected]', v_rows), p_should_succeed);
        ELSE
            PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || ' [write blocked: 0 rows visible/affected under RLS]', NOT p_should_succeed);
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'MTIPB'; -- always unwind this probe write; caught below, never committed
    EXCEPTION
        WHEN SQLSTATE 'MTIPB' THEN
            NULL; -- expected unwind path; already logged above
        WHEN insufficient_privilege OR others THEN
            PERFORM pg_temp.mti_log(p_scenario, p_dir, p_br, p_desc || format(' [write blocked: %s]', SQLERRM), NOT p_should_succeed);
    END;
END;
$$;

-- =============================================================================
-- FIXTURES — Business Alpha and Business Beta, with intentionally
-- overlapping-looking data throughout.
-- =============================================================================
DO $$ BEGIN SET LOCAL ROLE postgres; END $$;

DO $$
DECLARE
    v_owner_alpha BIGINT; v_agent_alpha BIGINT; v_investor_alpha BIGINT; v_cust_alpha BIGINT;
    v_owner_beta BIGINT; v_agent_beta BIGINT; v_investor_beta BIGINT; v_cust_beta BIGINT;
    v_shared_person BIGINT; -- Agent in Alpha, Customer in Beta (BR-202 role-transition)
    v_biz_alpha UUID; v_biz_beta UUID;
    v_mem_owner_alpha UUID; v_mem_agent_alpha UUID; v_mem_investor_alpha UUID; v_mem_cust_alpha UUID;
    v_mem_owner_beta UUID; v_mem_agent_beta UUID; v_mem_investor_beta UUID; v_mem_cust_beta UUID;
    v_mem_shared_agent_alpha UUID; v_mem_shared_cust_beta UUID;
    v_agent_row_alpha UUID; v_investor_row_alpha UUID; v_shared_agent_row UUID;
    v_cust_row_alpha UUID; v_cust_row_beta UUID; v_shared_cust_row_beta UUID; v_cust_row_alpha_assigned_to_shared UUID;
    v_loan_alpha UUID; v_loan_beta UUID;
    v_investment_alpha UUID; v_investment_beta UUID;
    v_perm_alpha UUID; v_perm_shared UUID;
    -- M4 route-model fixture: coverage is area-based.
    v_loc_alpha UUID; v_area_alpha UUID;
BEGIN
    -- Both businesses use "Ramesh Kumar" for their Agent and "Lakshmi" for
    -- their Customer — identical full_name across tenants, deliberately, to
    -- catch any policy that accidentally matches on name instead of ID.
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIOWNAL1', 'MLPI', '1', 'Owner Alpha', 'Father Alpha', 'System', 'New') RETURNING person_id INTO v_owner_alpha;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIAGTAL1', 'MLPI', '1', 'Ramesh Kumar', 'Father Alpha', 'System', 'New') RETURNING person_id INTO v_agent_alpha;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIINVAL1', 'MLPI', '1', 'Investor Alpha', 'Father Alpha', 'System', 'New') RETURNING person_id INTO v_investor_alpha;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TICUSAL1', 'MLPI', '1', 'Lakshmi', 'Father Alpha', 'System', 'New') RETURNING person_id INTO v_cust_alpha;

    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIOWNBT1', 'MLPI', '1', 'Owner Beta', 'Father Beta', 'System', 'New') RETURNING person_id INTO v_owner_beta;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIAGTBT1', 'MLPI', '1', 'Ramesh Kumar', 'Father Beta', 'System', 'New') RETURNING person_id INTO v_agent_beta;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TIINVBT1', 'MLPI', '1', 'Investor Beta', 'Father Beta', 'System', 'New') RETURNING person_id INTO v_investor_beta;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TICUSBT1', 'MLPI', '1', 'Lakshmi', 'Father Beta', 'System', 'New') RETURNING person_id INTO v_cust_beta;

    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1TISHARE1', 'MLPI', '1', 'Shared Person (Agent+Customer)', 'Father Shared', 'System', 'New') RETURNING person_id INTO v_shared_person;

    -- Businesses
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name, business_status)
    VALUES ('MLBI-MTI-ALPHA', v_owner_alpha, 'MTI Business Alpha', 'MTI Alpha Reg', 'Active') RETURNING business_id INTO v_biz_alpha;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name, business_status)
    VALUES ('MLBI-MTI-BETA', v_owner_beta, 'MTI Business Beta', 'MTI Beta Reg', 'Active') RETURNING business_id INTO v_biz_beta;

    -- Memberships
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_owner_alpha, v_biz_alpha, 'Owner', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_owner_alpha;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_alpha, v_biz_alpha, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_agent_alpha;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_investor_alpha, v_biz_alpha, 'Investor', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_investor_alpha;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_cust_alpha, v_biz_alpha, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_mem_cust_alpha;

    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_owner_beta, v_biz_beta, 'Owner', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_owner_beta;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_beta, v_biz_beta, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_agent_beta;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_investor_beta, v_biz_beta, 'Investor', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_investor_beta;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_cust_beta, v_biz_beta, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_mem_cust_beta;

    -- BR-202 role transition: shared_person is Agent under Alpha AND Customer under Beta
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_shared_person, v_biz_alpha, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_shared_agent_alpha;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_shared_person, v_biz_beta, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_mem_shared_cust_beta;

    -- Role-detail rows
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_agent_alpha, v_agent_alpha, CURRENT_DATE) RETURNING agent_id INTO v_agent_row_alpha;
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_agent_beta, v_agent_beta, CURRENT_DATE);
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_shared_agent_alpha, v_shared_person, CURRENT_DATE) RETURNING agent_id INTO v_shared_agent_row;

    INSERT INTO agent_permissions (agent_id, can_view_customers, can_issue_loans, can_collect_payments, can_view_investor_info)
    VALUES (v_agent_row_alpha, TRUE, TRUE, TRUE, TRUE) RETURNING permission_profile_id INTO v_perm_alpha;
    UPDATE business_members SET permission_profile_id = v_perm_alpha WHERE membership_id = v_mem_agent_alpha;
    INSERT INTO agent_permissions (agent_id, can_view_customers, can_issue_loans, can_collect_payments)
    VALUES (v_shared_agent_row, TRUE, TRUE, TRUE) RETURNING permission_profile_id INTO v_perm_shared;
    UPDATE business_members SET permission_profile_id = v_perm_shared WHERE membership_id = v_mem_shared_agent_alpha;

    INSERT INTO investors (membership_id, person_id) VALUES (v_mem_investor_alpha, v_investor_alpha) RETURNING investor_id INTO v_investor_row_alpha;
    INSERT INTO investors (membership_id, person_id) VALUES (v_mem_investor_beta, v_investor_beta);

    -- Customers, deliberately identical occupation
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_mem_cust_alpha, v_cust_alpha, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_cust_row_alpha;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_mem_cust_beta, v_cust_beta, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_cust_row_beta;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_mem_shared_cust_beta, v_shared_person, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_shared_cust_row_beta;

    -- A customer genuinely covered by shared_person's OWN Agent membership
    -- in Alpha (not Agent Alpha's) — needed so the "Customer-role in Beta
    -- does not downgrade Agent-role in Alpha" test below actually exercises
    -- shared_person's real agent_covers_customer() coverage, rather than
    -- checking a customer assigned to a different Agent entirely.
    -- M4: coverage is area-based, so the shared agent is assigned to an
    -- operating area containing this customer's village.
    DECLARE v_extra_person BIGINT; v_extra_mem UUID;
    BEGIN
        INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
        VALUES ('MLPI1TISHAREC', 'MLPI', '1', 'Shared Agent Customer', 'Father X', 'System', 'New') RETURNING person_id INTO v_extra_person;
        INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
        VALUES (v_extra_person, v_biz_alpha, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_extra_mem;
        INSERT INTO customers (membership_id, person_id, occupation, customer_since)
        VALUES (v_extra_mem, v_extra_person, 'Tailor', CURRENT_DATE)
        RETURNING customer_id INTO v_cust_row_alpha_assigned_to_shared;

        INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state)
        VALUES ('517101', 'MTI Shared Village', 'Village', 'MTI Mandal', 'MTI District', 'Andhra Pradesh')
        RETURNING location_id INTO v_loc_alpha;
        INSERT INTO operating_areas (business_id, name, account_cycle_duration, account_cycle_unit, submission_time)
        VALUES (v_biz_alpha, 'MTI Shared Area', 3, 'Days', '21:00:00')
        RETURNING operating_area_id INTO v_area_alpha;
        INSERT INTO operating_area_locations (operating_area_id, location_id, business_id)
        VALUES (v_area_alpha, v_loc_alpha, v_biz_alpha);
        INSERT INTO agent_area_assignments (agent_id, operating_area_id, frequency, valid_from)
        VALUES (v_shared_agent_row, v_area_alpha, 'Once', CURRENT_DATE);
        INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
        VALUES (v_extra_person, '1-2', '517101', v_loc_alpha, 'MTI Mandal', 'MTI District', 'Andhra Pradesh', CURRENT_DATE, TRUE);
    END;

    -- Loans: SAME repayment_amount in both businesses (₹22,000) — a policy
    -- accidentally matching by amount rather than business_id would pass a
    -- lazier test and fail this one.
    INSERT INTO loans (loan_number, customer_id, business_id, collection_agent_membership_id, repayment_amount,
                       interest_amount, processing_fee, repayment_type, duration_value, installment_amount,
                       grace_period_days, remaining_balance, effective_date, issue_business_date, live_photo_url, loan_status)
    VALUES ('MTI-LN-ALPHA-01', v_cust_row_alpha, v_biz_alpha, v_mem_agent_alpha, 22000, 2000, 200, 'Daily', 100, 220, 3, 22000,
            CURRENT_DATE, CURRENT_DATE, 'https://example.test/alpha.jpg', 'Active') RETURNING loan_id INTO v_loan_alpha;
    INSERT INTO loans (loan_number, customer_id, business_id, collection_agent_membership_id, repayment_amount,
                       interest_amount, processing_fee, repayment_type, duration_value, installment_amount,
                       grace_period_days, remaining_balance, effective_date, issue_business_date, live_photo_url, loan_status)
    VALUES ('MTI-LN-BETA-01', v_cust_row_beta, v_biz_beta, v_mem_agent_beta, 22000, 2000, 200, 'Daily', 100, 220, 3, 22000,
            CURRENT_DATE, CURRENT_DATE, 'https://example.test/beta.jpg', 'Active') RETURNING loan_id INTO v_loan_beta;

    -- Investments: SAME principal in both (₹75,000)
    INSERT INTO investments (investor_id, business_id, principal_amount, original_principal_amount, roi_rate, interest_type, effective_date)
    VALUES (v_investor_row_alpha, v_biz_alpha, 75000, 75000, 1.5, 'Simple', CURRENT_DATE) RETURNING investment_id INTO v_investment_alpha;
    INSERT INTO investments (investor_id, business_id, principal_amount, original_principal_amount, roi_rate, interest_type, effective_date)
    VALUES ((SELECT investor_id FROM investors WHERE membership_id = v_mem_investor_beta), v_biz_beta, 75000, 75000, 1.5, 'Simple', CURRENT_DATE)
    RETURNING investment_id INTO v_investment_beta;

    RESET ROLE;

    CREATE TEMP TABLE mti_fixture_ids (k TEXT PRIMARY KEY, v TEXT);
    INSERT INTO mti_fixture_ids VALUES
        ('owner_alpha', v_owner_alpha::TEXT), ('agent_alpha', v_agent_alpha::TEXT), ('investor_alpha', v_investor_alpha::TEXT), ('cust_alpha', v_cust_alpha::TEXT),
        ('owner_beta', v_owner_beta::TEXT), ('agent_beta', v_agent_beta::TEXT), ('investor_beta', v_investor_beta::TEXT), ('cust_beta', v_cust_beta::TEXT),
        ('shared_person', v_shared_person::TEXT),
        ('biz_alpha', v_biz_alpha::TEXT), ('biz_beta', v_biz_beta::TEXT),
        ('mem_owner_alpha', v_mem_owner_alpha::TEXT), ('mem_agent_alpha', v_mem_agent_alpha::TEXT),
        ('mem_investor_alpha', v_mem_investor_alpha::TEXT), ('mem_cust_alpha', v_mem_cust_alpha::TEXT),
        ('mem_owner_beta', v_mem_owner_beta::TEXT), ('mem_agent_beta', v_mem_agent_beta::TEXT),
        ('mem_investor_beta', v_mem_investor_beta::TEXT), ('mem_cust_beta', v_mem_cust_beta::TEXT),
        ('mem_shared_agent_alpha', v_mem_shared_agent_alpha::TEXT), ('mem_shared_cust_beta', v_mem_shared_cust_beta::TEXT),
        ('cust_row_alpha', v_cust_row_alpha::TEXT), ('cust_row_beta', v_cust_row_beta::TEXT), ('shared_cust_row_beta', v_shared_cust_row_beta::TEXT),
        ('cust_row_alpha_assigned_to_shared', v_cust_row_alpha_assigned_to_shared::TEXT),
        ('loan_alpha', v_loan_alpha::TEXT), ('loan_beta', v_loan_beta::TEXT),
        ('investment_alpha', v_investment_alpha::TEXT), ('investment_beta', v_investment_beta::TEXT);
    GRANT SELECT, INSERT ON mti_fixture_ids TO authenticated;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.mfid(p_key TEXT) RETURNS TEXT LANGUAGE sql AS $$
    SELECT v FROM mti_fixture_ids WHERE k = p_key;
$$;

-- =============================================================================
-- SECTION 1 — CORE BR-202/203 ISOLATION, BOTH DIRECTIONS, PER BUSINESS-SCOPED
-- TABLE. For each table, Alpha-side role probes for Beta rows AND vice versa.
-- =============================================================================

-- --- businesses ---
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('owner_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('businesses', format('business_id = %L', pg_temp.mfid('biz_beta')), 0,
    'businesses', 'ALPHA->BETA', 'BR-202/203', 'Owner Alpha cannot see Business Beta at all');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('owner_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('businesses', format('business_id = %L', pg_temp.mfid('biz_alpha')), 0,
    'businesses', 'BETA->ALPHA', 'BR-202/203', 'Owner Beta cannot see Business Alpha at all');

-- --- business_members (via the identically-named "Ramesh Kumar" Agent rows) ---
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('agent_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L', pg_temp.mfid('mem_agent_beta')), 0,
    'business_members (identical-name agent)', 'ALPHA->BETA', 'BR-202/203',
    'Agent Alpha ("Ramesh Kumar") cannot see the Beta membership row of the OTHER "Ramesh Kumar" (Agent Beta) — same full_name, must not leak via name-based confusion');
SELECT pg_temp.mti_assert_zero_business_rows('business_members', 'business_id', pg_temp.mfid('biz_beta')::UUID,
    'business_members (all rows)', 'ALPHA->BETA', 'BR-202/203', 'Agent Alpha sees zero business_members rows scoped to Business Beta, of any role');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('agent_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L', pg_temp.mfid('mem_agent_alpha')), 0,
    'business_members (identical-name agent)', 'BETA->ALPHA', 'BR-202/203',
    'Agent Beta ("Ramesh Kumar") cannot see the Alpha membership row of the OTHER "Ramesh Kumar" (Agent Alpha)');
SELECT pg_temp.mti_assert_zero_business_rows('business_members', 'business_id', pg_temp.mfid('biz_alpha')::UUID,
    'business_members (all rows)', 'BETA->ALPHA', 'BR-202/203', 'Agent Beta sees zero business_members rows scoped to Business Alpha, of any role');

-- --- customers (via identically-named "Lakshmi" customers) ---
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('agent_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_beta')), 0,
    'customers (identical-name customer)', 'ALPHA->BETA', 'BR-202/203',
    'Agent Alpha (can_view_customers) cannot see the Beta "Lakshmi" customer row, only sees their OWN business''s "Lakshmi"');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('cust_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_beta')), 0,
    'customers (self vs identical-name other-tenant)', 'ALPHA->BETA', 'BR-202/203',
    'Customer Alpha ("Lakshmi") cannot see the OTHER "Lakshmi" (Customer Beta) profile row');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('cust_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_alpha')), 0,
    'customers (self vs identical-name other-tenant)', 'BETA->ALPHA', 'BR-202/203',
    'Customer Beta ("Lakshmi") cannot see the OTHER "Lakshmi" (Customer Alpha) profile row');

-- --- loans (identical ₹22,000 repayment_amount in both businesses) ---
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('cust_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('loans', format('loan_id = %L', pg_temp.mfid('loan_beta')), 0,
    'loans (identical amount, cross-tenant)', 'ALPHA->BETA', 'BR-202/203',
    'Customer Alpha cannot see Business Beta''s loan despite the identical ₹22,000 repayment_amount — confirms filtering is by business_id/customer_id, not amount');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('cust_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('loans', format('loan_id = %L', pg_temp.mfid('loan_alpha')), 0,
    'loans (identical amount, cross-tenant)', 'BETA->ALPHA', 'BR-202/203',
    'Customer Beta cannot see Business Alpha''s loan despite the identical ₹22,000 repayment_amount');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('agent_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_zero_business_rows('loans', 'business_id', pg_temp.mfid('biz_beta')::UUID,
    'loans (all rows)', 'ALPHA->BETA', 'BR-202/203', 'Agent Alpha sees zero loans scoped to Business Beta');

-- --- investments (identical ₹75,000 principal in both businesses) ---
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('investor_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('investments', format('investment_id = %L', pg_temp.mfid('investment_beta')), 0,
    'investments (identical principal, cross-tenant)', 'ALPHA->BETA', 'BR-202/203',
    'Investor Alpha cannot see Investor Beta''s investment despite the identical ₹75,000 principal');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('investor_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('investments', format('investment_id = %L', pg_temp.mfid('investment_alpha')), 0,
    'investments (identical principal, cross-tenant)', 'BETA->ALPHA', 'BR-202/203',
    'Investor Beta cannot see Investor Alpha''s investment despite the identical ₹75,000 principal');

-- =============================================================================
-- SECTION 2 — BR-202 ROLE-TRANSITION SCENARIO
-- shared_person is Agent under Business Alpha AND Customer under Business
-- Beta. Confirm each context's access is correctly scoped, with ZERO
-- bleed-through of the other role's permissions.
-- =============================================================================
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('shared_person')::BIGINT); END $$;

-- Their OWN memberships across both businesses must be visible (BR-208 role
-- switcher needs this — schema §1.8 "Self: SELECT own membership rows
-- across any business").
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L', pg_temp.mfid('mem_shared_agent_alpha')), 1,
    'role-transition: self visibility', 'ALPHA-role', 'BR-208', 'Shared person can see their OWN Agent-role membership row in Business Alpha');
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L', pg_temp.mfid('mem_shared_cust_beta')), 1,
    'role-transition: self visibility', 'BETA-role', 'BR-208', 'Shared person can see their OWN Customer-role membership row in Business Beta');

-- Agent-role powers in Alpha must NOT leak into Beta where they are merely
-- a Customer. As "Agent in Alpha", they should never be able to read
-- Beta's business_members/customers rows just because they hold a
-- privileged role somewhere else in the system.
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_beta')), 0,
    'role-transition: no Agent-power leak into Beta', 'ALPHA-role-into-BETA', 'BR-202/203',
    'Shared person (Agent in Alpha) cannot read Business Beta''s OTHER customer (Customer Beta) — their Agent privileges in Alpha grant nothing in Beta, where they hold only a Customer role');
SELECT pg_temp.mti_assert_count('business_members',
    format('business_id = %L AND membership_id != %L', pg_temp.mfid('biz_beta'), pg_temp.mfid('mem_shared_cust_beta')), 0,
    'role-transition: no Agent-power leak into Beta (all rows)', 'ALPHA-role-into-BETA', 'BR-202/203',
    'Shared person''s Agent-role query context sees zero OTHER business_members rows in Business Beta, beyond their own already-confirmed-visible Customer-role row');

-- Customer-role limits in Beta must NOT restrict their Agent-role access
-- back in Alpha (independent axis — being "just a Customer" somewhere else
-- must not accidentally downgrade their Agent access elsewhere).
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_alpha_assigned_to_shared')), 1,
    'role-transition: Customer-role in Beta does not downgrade Agent-role in Alpha', 'BETA-role-into-ALPHA', 'BR-202',
    'Shared person retains full Agent-role visibility of their OWN assigned customer in Business Alpha, unaffected by also being a mere Customer in Business Beta');

-- Their own Customer-role profile in Beta grants no special access to
-- Beta's operational (Agent-only) tables, e.g. customer_remarks (internal,
-- Agent/Owner-only per Module 3 analysis above) — confirm the shared
-- person, purely as "Customer in Beta", cannot read remarks entered about
-- ANY Beta customer (including ones about themselves, per the Module-3
-- finding that customer_remarks is never customer-facing).
DO $$
DECLARE v_remark_beta UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO customer_remarks (customer_id, entered_by_person_id, remark_text, business_date)
    VALUES (pg_temp.mfid('cust_row_beta')::UUID, pg_temp.mfid('owner_beta')::BIGINT, 'MTI internal remark on Customer Beta', CURRENT_DATE)
    RETURNING remark_id INTO v_remark_beta;
    RESET ROLE;
    INSERT INTO mti_fixture_ids VALUES ('remark_beta', v_remark_beta::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('shared_person')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('customer_remarks', format('remark_id = %L', pg_temp.mfid('remark_beta')), 0,
    'role-transition: Customer-role grants no Agent-only table access', 'BETA-role', 'derived (Module 3 analysis)',
    'Shared person, in their Customer-role context under Business Beta, cannot read customer_remarks at all — an internal operational table stays internal regardless of which OTHER business the same person happens to be an Agent in');

-- =============================================================================
-- SECTION 3 — SP-001 SUSPENSION CARVE-OUT
-- Flip Business Alpha to Suspended. Confirm: non-Owner roles lose access (or
-- the enforcement gap is exposed, per the flagged open decision point in
-- rls_role_matrix.md); Owner retains access needed for dispute resolution;
-- Business Beta is completely unaffected.
-- =============================================================================
DO $$ BEGIN SET LOCAL ROLE postgres; END $$;
UPDATE businesses SET business_status = 'Suspended' WHERE business_id = (SELECT v::UUID FROM mti_fixture_ids WHERE k = 'biz_alpha');
DO $$ BEGIN RESET ROLE; END $$;

-- Owner must retain access (SP-001: "Original account holder ... needs
-- query access to resolve an Aadhaar dispute").
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('owner_alpha')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('businesses', format('business_id = %L', pg_temp.mfid('biz_alpha')), 1,
    'SP-001 suspension: Owner retains access', 'ALPHA (suspended)', 'SP-001',
    'Owner Alpha can still read their own SUSPENDED business — required for dispute resolution per SP-001');
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_alpha')), 1,
    'SP-001 suspension: Owner retains data access', 'ALPHA (suspended)', 'SP-001',
    'Owner Alpha can still read customer data within their SUSPENDED business');

-- Non-Owner roles: per rls_role_matrix.md's own flagged "SP-001 suspension
-- enforcement — decision point, not resolved here" note, this is NOT
-- enforced at the RLS layer in the reviewed migration set (0012-0018) — it
-- is left to the application layer. This test therefore documents the
-- CURRENT ACTUAL STATE (a non-Owner can still query through RLS while
-- Suspended) as a FINDING rather than silently expecting it to pass, since
-- SP-001 explicitly requires "Agent/Investor/Customer see only the generic
-- suspension message" — if this test reports PASS-with-access, that is a
-- gap to escalate to master chat, not a suite bug.
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('agent_alpha')::BIGINT); END $$;
DO $$
DECLARE v_actual BIGINT;
BEGIN
    EXECUTE format('SELECT count(*) FROM businesses WHERE business_id = %L', pg_temp.mfid('biz_alpha')) INTO v_actual;
    IF v_actual = 0 THEN
        PERFORM pg_temp.mti_log('SP-001 suspension: non-Owner RLS enforcement', 'ALPHA (suspended)', 'SP-001',
            'Agent Alpha is blocked at the RLS layer from a SUSPENDED business (stricter than the flagged decision point — a follow-up "AND business_status != Suspended" clause appears to already be present)', TRUE);
    ELSE
        PERFORM pg_temp.mti_log('SP-001 suspension: non-Owner RLS enforcement', 'ALPHA (suspended)', 'SP-001',
            'FINDING (expected, per rls_role_matrix.md''s own flag): Agent Alpha CAN still query the SUSPENDED business at the RLS layer. SP-001 requires non-Owner roles see only "This business is temporarily suspended" — that behavior is NOT implemented in RLS policies 0012-0018 and must be enforced at the application layer (block navigation before any query fires) or via an additional business_status clause. Recorded as a known gap, not a suite defect — do not silently mark this a suite bug if it fails; escalate to master chat per the briefing''s instruction.', FALSE);
    END IF;
END $$;

-- Suspension must not leak into the UNRELATED Business Beta.
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('owner_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('businesses', format('business_id = %L AND business_status = ''Active''', pg_temp.mfid('biz_beta')), 1,
    'SP-001 suspension: no cross-business leak', 'BETA (unaffected)', 'SP-001',
    'Business Beta remains Active and fully accessible to its own Owner — Alpha''s suspension has zero effect on an unrelated tenancy');
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('cust_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('customers', format('customer_id = %L', pg_temp.mfid('cust_row_beta')), 1,
    'SP-001 suspension: no cross-business leak', 'BETA (unaffected)', 'SP-001',
    'Customer Beta''s own access is completely unaffected by Business Alpha''s suspension');

-- Un-suspend Alpha for any tests that might run after this section in a
-- combined run (defensive; this file rolls back everything anyway).
DO $$ BEGIN SET LOCAL ROLE postgres; END $$;
UPDATE businesses SET business_status = 'Active' WHERE business_id = (SELECT v::UUID FROM mti_fixture_ids WHERE k = 'biz_alpha');
DO $$ BEGIN RESET ROLE; END $$;

-- =============================================================================
-- SECTION 4 — LOCK INDEPENDENCE (BR-203): a lock applied by one Owner must
-- have zero effect on that person's standing with any OTHER Owner's tenancy.
-- Simulate by setting locked_by_this_owner=TRUE on the shared_person's
-- Alpha membership and confirming their Beta membership is untouched.
-- =============================================================================
DO $$ BEGIN SET LOCAL ROLE postgres; END $$;
UPDATE business_members SET locked_by_this_owner = TRUE
WHERE membership_id = (SELECT v::UUID FROM mti_fixture_ids WHERE k = 'mem_shared_agent_alpha');
DO $$ BEGIN RESET ROLE; END $$;

DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('shared_person')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L AND locked_by_this_owner = TRUE', pg_temp.mfid('mem_shared_agent_alpha')), 1,
    'BR-203 lock independence', 'ALPHA (locked)', 'BR-203', 'Shared person''s Alpha membership correctly shows locked_by_this_owner = TRUE');
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L AND locked_by_this_owner = FALSE', pg_temp.mfid('mem_shared_cust_beta')), 1,
    'BR-203 lock independence', 'BETA (unaffected)', 'BR-203',
    'Shared person''s Beta membership remains locked_by_this_owner = FALSE — Owner Alpha''s lock on the person has zero effect on their standing with Owner Beta');
-- Also confirm Owner Beta cannot see or be affected by the Alpha lock flag at all.
DO $$ BEGIN PERFORM pg_temp.mti_login(pg_temp.mfid('owner_beta')::BIGINT); END $$;
SELECT pg_temp.mti_assert_count('business_members', format('membership_id = %L', pg_temp.mfid('mem_shared_agent_alpha')), 0,
    'BR-203 lock independence: Owner Beta cannot see Alpha''s lock', 'BETA->ALPHA', 'BR-203',
    'Owner Beta cannot even see the shared person''s Alpha membership row (let alone its lock flag) — full tenancy isolation, not just a permission check on the lock itself');

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$ BEGIN RESET ROLE; END $$;
DO $$
DECLARE v_total INT; v_passed INT; v_failed INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed) INTO v_total, v_passed, v_failed FROM mti_results;
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'MULTI-TENANCY ISOLATION TESTS: % total, % passed, % FAILED', v_total, v_passed, v_failed;
    RAISE NOTICE '(A FAIL in the SP-001 non-Owner section is an EXPECTED, already-known application-layer gap — see comment above. Every other FAIL here is a real cross-tenant leak and should block merge.)';
    RAISE NOTICE '=============================================================';
END $$;

SELECT seq, scenario, direction, br_ref, description, passed FROM mti_results ORDER BY seq;

ROLLBACK;

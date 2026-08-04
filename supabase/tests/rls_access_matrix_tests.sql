-- =============================================================================
-- MANA LINE — rls_access_matrix_tests.sql
-- CORE DELIVERABLE of this QA chat. For every table in 03_Database_Schema.md,
-- one positive test per role that SHOULD have access, and one negative test
-- per role that SHOULD NOT — independently derived from the ground-truth
-- specs (03_Database_Schema.md, 01_Global_Rules_Guide.md, the OW/AG/IW/CW
-- PERMISSION sections), NOT copied from the RLS chat's own
-- rls_role_matrix.md. Every disagreement between this file's expectations
-- and rls_role_matrix.md is called out explicitly in comments marked
-- "DISAGREEMENT" and summarized again in README_how_to_run.md /
-- master-chat notes — none are silently resolved here.
--
-- CONVENTION: plain SQL (see schema_integrity_tests.sql header for why —
-- pgTAP availability unconfirmed in target project). Identity/role
-- impersonation works by setting the `request.jwt.claims` GUC the same way
-- Supabase's PostgREST does at runtime, then `SET LOCAL ROLE authenticated`
-- so the session actually runs under RLS instead of as its underlying
-- superuser/service role. This exactly matches the assumption
-- app.current_person_id() makes in 0012_rls_module0_identity.sql (JWT claim
-- named "person_id") — if the real auth integration turns out to use a
-- different mechanism (see rls_role_matrix.md's own flagged "Auth
-- integration" open item), every test in this file will uniformly and
-- visibly FAIL (deny-all), which is itself a useful, unambiguous signal.
--
-- HOW TO RUN: see README_how_to_run.md.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Harness
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE ram_results (
    seq SERIAL PRIMARY KEY,
    table_name TEXT,
    role_under_test TEXT,
    direction TEXT,        -- 'POSITIVE' or 'NEGATIVE'
    br_ref TEXT,
    description TEXT,
    passed BOOLEAN
) ON COMMIT DROP;
-- Owned by the setup role; every assertion runs as an impersonated
-- authenticated/anon role via SET LOCAL ROLE, so both need explicit access
-- or every single ram_log() call (i.e. every test result) fails silently
-- into the same "permission denied" abort as the ram_fixture_ids gap above.
GRANT INSERT, SELECT ON ram_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE ram_results_seq_seq TO authenticated, anon;

CREATE OR REPLACE FUNCTION pg_temp.ram_log(p_table TEXT, p_role TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT, p_passed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO ram_results(table_name, role_under_test, direction, br_ref, description, passed)
    VALUES (p_table, p_role, p_dir, p_br, p_desc, p_passed);
    IF p_passed THEN
        RAISE NOTICE 'PASS [%/%/%] (%) %', p_table, p_role, p_dir, p_br, p_desc;
    ELSE
        RAISE WARNING 'FAIL [%/%/%] (%) %', p_table, p_role, p_dir, p_br, p_desc;
    END IF;
END;
$$;

-- Impersonate a person as an authenticated PostgREST-style request.
CREATE OR REPLACE FUNCTION pg_temp.ram_login(p_person_id BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('person_id', p_person_id, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

-- Log out entirely (anon request) — used for negative tests that assert
-- zero-visibility to unauthenticated callers where relevant.
CREATE OR REPLACE FUNCTION pg_temp.ram_logout()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', '', true);
    EXECUTE 'SET LOCAL ROLE anon';
END;
$$;

-- Generic visibility assertion: as whoever is currently impersonated, count
-- rows in p_table matching p_where and compare to p_expected.
CREATE OR REPLACE FUNCTION pg_temp.ram_assert_count(
    p_table TEXT, p_where TEXT, p_expected BIGINT,
    p_role TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_actual BIGINT;
BEGIN
    EXECUTE format('SELECT count(*) FROM %I WHERE %s', p_table, p_where) INTO v_actual;
    PERFORM pg_temp.ram_log(p_table, p_role, p_dir, p_br,
        p_desc || format(' [expected %s row(s), saw %s]', p_expected, v_actual),
        v_actual = p_expected);
EXCEPTION WHEN insufficient_privilege THEN
    -- A table with RLS enabled and literally zero matching policies for this
    -- role can sometimes surface as insufficient_privilege rather than an
    -- empty result set depending on grants; treat that the same as "saw 0".
    PERFORM pg_temp.ram_log(p_table, p_role, p_dir, p_br,
        p_desc || format(' [insufficient_privilege raised — treated as 0 rows visible; expected %s]', p_expected),
        p_expected = 0);
END;
$$;

-- Generic INSERT assertion: attempt p_sql as whoever is impersonated; log
-- whether it succeeded/failed against p_should_succeed. Runs in a SAVEPOINT
-- so a failure doesn't poison the rest of the run, and rolls the attempt
-- back either way (this file never wants its own probes to leave rows).
CREATE OR REPLACE FUNCTION pg_temp.ram_assert_write(
    p_sql TEXT, p_should_succeed BOOLEAN,
    p_table TEXT, p_role TEXT, p_dir TEXT, p_br TEXT, p_desc TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows > 0 THEN
            PERFORM pg_temp.ram_log(p_table, p_role, p_dir, p_br, p_desc || format(' [write succeeded, %s row(s) affected]', v_rows), p_should_succeed);
        ELSE
            -- No exception, but zero rows affected: RLS's USING clause made
            -- the target invisible to this role, which is functionally
            -- identical to being blocked from a security standpoint — this
            -- is the expected outcome for a NEGATIVE case, not a failure.
            PERFORM pg_temp.ram_log(p_table, p_role, p_dir, p_br, p_desc || ' [write blocked: 0 rows visible/affected under RLS]', NOT p_should_succeed);
        END IF;
        RAISE EXCEPTION USING ERRCODE = 'RAMPB'; -- always unwind this probe write; caught below, never committed
    EXCEPTION
        WHEN SQLSTATE 'RAMPB' THEN
            NULL; -- expected unwind path; already logged above
        WHEN insufficient_privilege OR others THEN
            PERFORM pg_temp.ram_log(p_table, p_role, p_dir, p_br, p_desc || format(' [write blocked: %s]', SQLERRM), NOT p_should_succeed);
    END;
END;
$$;

-- =============================================================================
-- FIXTURES — two businesses (A, B) each with a full role set, plus a
-- role-transition person (Agent in A / Customer in B) and a
-- deliberately-identical-looking pair of customers/loans across A and B, so
-- the SAME queries used below double as a lightweight cross-tenancy check.
-- (The dedicated, exhaustive cross-tenancy suite lives in
-- multi_tenancy_isolation_tests.sql — this fixture set is intentionally
-- reused there via near-identical setup so both files can be read/run
-- independently.)
-- =============================================================================
DO $$ BEGIN
SET LOCAL ROLE postgres; -- fixture setup runs as the table owner/superuser, bypassing RLS
END $$;

DO $$
DECLARE
    v_owner_a BIGINT; v_agent_a BIGINT; v_investor_a BIGINT; v_customer_a BIGINT;
    v_owner_b BIGINT; v_agent_b BIGINT; v_investor_b BIGINT; v_customer_b BIGINT;
    v_biz_a UUID; v_biz_b UUID;
    v_mem_owner_a UUID; v_mem_agent_a UUID; v_mem_investor_a UUID; v_mem_customer_a UUID;
    v_mem_owner_b UUID; v_mem_agent_b UUID; v_mem_investor_b UUID; v_mem_customer_b UUID;
    v_cust_row_a UUID; v_cust_row_b UUID;
    v_agent_row_a UUID; v_investor_row_a UUID;
    v_loan_a UUID; v_loan_b UUID;
    v_perm_a UUID;
    -- M4 route-model fixture: coverage is area-based now.
    v_loc_a UUID; v_area_a UUID;
BEGIN
    -- Persons
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMOWNA01', 'MLPI', '1', 'RAM Owner A', 'Father A', 'System', 'New') RETURNING person_id INTO v_owner_a;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMAGTA01', 'MLPI', '1', 'RAM Agent Identical Name', 'Father A', 'System', 'New') RETURNING person_id INTO v_agent_a;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMINVA01', 'MLPI', '1', 'RAM Investor A', 'Father A', 'System', 'New') RETURNING person_id INTO v_investor_a;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMCUSA01', 'MLPI', '1', 'RAM Customer A', 'Father A', 'System', 'New') RETURNING person_id INTO v_customer_a;

    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMOWNB01', 'MLPI', '1', 'RAM Owner B', 'Father B', 'System', 'New') RETURNING person_id INTO v_owner_b;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMAGTB01', 'MLPI', '1', 'RAM Agent Identical Name', 'Father B', 'System', 'New') RETURNING person_id INTO v_agent_b;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMINVB01', 'MLPI', '1', 'RAM Investor B', 'Father B', 'System', 'New') RETURNING person_id INTO v_investor_b;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMCUSB01', 'MLPI', '1', 'RAM Customer B', 'Father B', 'System', 'New') RETURNING person_id INTO v_customer_b;

    -- Businesses
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name, business_status)
    VALUES ('MLBI-RAM-A', v_owner_a, 'RAM Business A', 'RAM Business A Reg', 'Active') RETURNING business_id INTO v_biz_a;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name, business_status)
    VALUES ('MLBI-RAM-B', v_owner_b, 'RAM Business B', 'RAM Business B Reg', 'Active') RETURNING business_id INTO v_biz_b;

    -- Memberships, all Active
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_owner_a, v_biz_a, 'Owner', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_owner_a;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_a, v_biz_a, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_agent_a;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_investor_a, v_biz_a, 'Investor', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_investor_a;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_customer_a, v_biz_a, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_mem_customer_a;

    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_owner_b, v_biz_b, 'Owner', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_owner_b;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_b, v_biz_b, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_agent_b;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_investor_b, v_biz_b, 'Investor', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_investor_b;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_customer_b, v_biz_b, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_mem_customer_b;

    -- BR-202 role-transition fixture: v_agent_a is ALSO a Customer under Business B
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_a, v_biz_b, 'Customer', 'Active', 'Direct Registration', 'Not Required');

    -- Role-detail rows
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_agent_a, v_agent_a, CURRENT_DATE) RETURNING agent_id INTO v_agent_row_a;
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_agent_b, v_agent_b, CURRENT_DATE);
    INSERT INTO agent_permissions (agent_id, can_view_customers, can_issue_loans, can_collect_payments, can_view_investor_info, can_view_reports)
    VALUES (v_agent_row_a, TRUE, TRUE, TRUE, TRUE, TRUE) RETURNING permission_profile_id INTO v_perm_a;
    UPDATE business_members SET permission_profile_id = v_perm_a WHERE membership_id = v_mem_agent_a;

    INSERT INTO investors (membership_id, person_id) VALUES (v_mem_investor_a, v_investor_a) RETURNING investor_id INTO v_investor_row_a;
    INSERT INTO investors (membership_id, person_id) VALUES (v_mem_investor_b, v_investor_b);

    -- Identical-looking customers in both businesses (same occupation profile)
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_mem_customer_a, v_customer_a, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_cust_row_a;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_mem_customer_b, v_customer_b, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_cust_row_b;

    -- M4: agent coverage is area-based. Customer A's village belongs to an
    -- operating area that Agent A currently holds (open window), so the
    -- "Agent (assigned)" positive assertions below still mean something.
    INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state)
    VALUES ('517102', 'RAM Village A', 'Village', 'RAM Mandal', 'RAM District', 'Andhra Pradesh')
    RETURNING location_id INTO v_loc_a;
    INSERT INTO operating_areas (business_id, name, account_cycle_duration, account_cycle_unit, submission_time)
    VALUES (v_biz_a, 'RAM Area A', 3, 'Days', '21:00:00')
    RETURNING operating_area_id INTO v_area_a;
    INSERT INTO operating_area_locations (operating_area_id, location_id, business_id)
    VALUES (v_area_a, v_loc_a, v_biz_a);
    INSERT INTO agent_area_assignments (agent_id, operating_area_id, frequency, valid_from)
    VALUES (v_agent_row_a, v_area_a, 'Once', CURRENT_DATE);
    INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
    VALUES (v_customer_a, '1-2', '517102', v_loc_a, 'RAM Mandal', 'RAM District', 'Andhra Pradesh', CURRENT_DATE, TRUE);

    -- Loans with the same amount in both businesses
    INSERT INTO loans (loan_number, customer_id, business_id, collection_agent_membership_id, repayment_amount,
                       interest_amount, processing_fee, repayment_type, duration_value, installment_amount,
                       grace_period_days, remaining_balance, effective_date, issue_business_date, live_photo_url, loan_status)
    VALUES ('RAM-LN-A-001', v_cust_row_a, v_biz_a, v_mem_agent_a, 11000, 1000, 100, 'Daily', 100, 110, 3, 11000,
            CURRENT_DATE, CURRENT_DATE, 'https://example.test/a.jpg', 'Active') RETURNING loan_id INTO v_loan_a;
    INSERT INTO loans (loan_number, customer_id, business_id, collection_agent_membership_id, repayment_amount,
                       interest_amount, processing_fee, repayment_type, duration_value, installment_amount,
                       grace_period_days, remaining_balance, effective_date, issue_business_date, live_photo_url, loan_status)
    VALUES ('RAM-LN-B-001', v_cust_row_b, v_biz_b, v_mem_agent_b, 11000, 1000, 100, 'Daily', 100, 110, 3, 11000,
            CURRENT_DATE, CURRENT_DATE, 'https://example.test/b.jpg', 'Active') RETURNING loan_id INTO v_loan_b;

    -- Investments, identical amounts
    INSERT INTO investments (investor_id, business_id, principal_amount, original_principal_amount, roi_rate, interest_type, effective_date)
    VALUES (v_investor_row_a, v_biz_a, 50000, 50000, 1.5, 'Simple', CURRENT_DATE);

    -- Stash the generated ids for later sections via a temp lookup table
    -- (session-scoped, dropped with the outer transaction).
    CREATE TEMP TABLE ram_fixture_ids (k TEXT PRIMARY KEY, v TEXT);
    INSERT INTO ram_fixture_ids VALUES
        ('owner_a', v_owner_a::TEXT), ('agent_a', v_agent_a::TEXT), ('investor_a', v_investor_a::TEXT), ('customer_a', v_customer_a::TEXT),
        ('owner_b', v_owner_b::TEXT), ('agent_b', v_agent_b::TEXT), ('investor_b', v_investor_b::TEXT), ('customer_b', v_customer_b::TEXT),
        ('biz_a', v_biz_a::TEXT), ('biz_b', v_biz_b::TEXT),
        ('cust_row_a', v_cust_row_a::TEXT), ('cust_row_b', v_cust_row_b::TEXT),
        ('loan_a', v_loan_a::TEXT), ('loan_b', v_loan_b::TEXT),
        ('mem_agent_a', v_mem_agent_a::TEXT), ('mem_owner_a', v_mem_owner_a::TEXT);
    -- The setup role (postgres/service_role) owns this temp table by
    -- default; every test below runs as `authenticated` via SET LOCAL ROLE,
    -- which has no implicit access to another role's objects even within
    -- the same session/temp schema. Without this grant, every fixture
    -- lookup after the first role switch fails with "permission denied for
    -- table ram_fixture_ids", masking every RLS assertion that follows.
    GRANT SELECT, INSERT ON ram_fixture_ids TO authenticated;
END $$;

DO $$ BEGIN RESET ROLE; END $$;

-- Convenience getters
CREATE OR REPLACE FUNCTION pg_temp.fid(p_key TEXT) RETURNS TEXT LANGUAGE sql AS $$
    SELECT v FROM ram_fixture_ids WHERE k = p_key;
$$;

-- =============================================================================
-- MODULE 0 — IDENTITY NETWORK
-- =============================================================================

-- persons: Owner/Agent(can_view_customers) SHOULD see a business partner's
-- row; Investor/Customer should NOT see anyone else's identity row at all
-- (derived independently from BR-207 "Guarantor data strictly private" /
-- general privacy posture — persons carries PIN/password hashes, the most
-- sensitive table in the schema, so default-deny for I/C is the only
-- defensible independent reading even before consulting rls_role_matrix.md).
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('persons', format('person_id = %L', pg_temp.fid('customer_a')), 1,
    'Owner', 'POSITIVE', 'schema §0.1 + BR-199', 'Owner A can read a Customer A person row (shared active business)');

DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('persons', format('person_id = %L', pg_temp.fid('customer_a')), 0,
    'Investor', 'NEGATIVE', 'derived: identity data is not investor-visible', 'Investor A cannot read Customer A''s person row (persons carries auth secrets; independently expected default-deny for Investor)');

DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('persons', format('person_id = %L', pg_temp.fid('agent_a')), 0,
    'Customer', 'NEGATIVE', 'derived: identity data is not customer-visible', 'Customer A cannot read their assigned Agent''s person row');
SELECT pg_temp.ram_assert_count('persons', format('person_id = %L', pg_temp.fid('customer_a')), 1,
    'Customer', 'POSITIVE', 'schema §0.1', 'Customer A can read their OWN person row (self-access)');

-- devices: self-only, EVEN for Owner (independently derived: schema note
-- calls devices a "security control surface", so this is one of the few
-- tables where Owner's BR-199 "unrestricted access" should NOT apply —
-- confirm this reading against rls_role_matrix.md, which reaches the same
-- conclusion; flagged as agreement, not taken on faith).
DO $$
DECLARE v_device UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO devices (person_id, device_fingerprint) VALUES (pg_temp.fid('agent_a')::BIGINT, 'ram-fingerprint-1') RETURNING device_id INTO v_device;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('device_agent_a', v_device::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('devices', format('device_id = %L', pg_temp.fid('device_agent_a')), 0,
    'Owner', 'NEGATIVE', 'derived: BR-199 unrestricted access should NOT extend to device fingerprints (security control surface, not business data)',
    'Owner A cannot read Agent A''s device row, even though Owner otherwise has unrestricted business access');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('devices', format('device_id = %L', pg_temp.fid('device_agent_a')), 1,
    'Agent (self)', 'POSITIVE', 'schema §0.4', 'Agent A can read their own device row');

-- =============================================================================
-- MODULE 1 — TENANCY / BUSINESS
-- =============================================================================

-- businesses: Owner full on own; A/I/C SELECT-only while Active; nobody
-- sees the other business.
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('businesses', format('business_id = %L', pg_temp.fid('biz_a')), 1,
    'Agent', 'POSITIVE', 'schema §1.1', 'Agent A can read Business A (their own active membership)');
SELECT pg_temp.ram_assert_count('businesses', format('business_id = %L', pg_temp.fid('biz_b')), 1,
    'Agent', 'POSITIVE', 'BR-202/203', 'Agent A CAN read Business B — but only via their separate Customer-role membership there (see the BR-202 role-transition fixture above), not via Agent-role bleed-through; the Agent-role-isolation negative case is covered separately below using Agent B, who genuinely holds no membership in Business A');

DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('businesses', format('business_id = %L', pg_temp.fid('biz_a')), 0,
    'Agent', 'NEGATIVE', 'BR-202/203', 'Agent B (genuinely zero membership anywhere in Business A) cannot read Business A');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;

DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_write(
    format('UPDATE businesses SET business_name = ''Hacked'' WHERE business_id = %L', pg_temp.fid('biz_a')),
    FALSE, 'businesses', 'Owner (cross-tenant)', 'NEGATIVE', 'BR-185/BR-202/203',
    'Owner B cannot UPDATE Business A (not their business)'
);
SELECT pg_temp.ram_assert_write(
    format('UPDATE businesses SET business_name = ''Renamed B'' WHERE business_id = %L', pg_temp.fid('biz_b')),
    TRUE, 'businesses', 'Owner', 'POSITIVE', 'schema §1.1', 'Owner B CAN update their own Business B'
);

-- business_members: the single most important negative case per
-- rls_role_matrix.md's own assessment (and independently, per BR-202/203 +
-- AG-004 scoping) — Agent must see ONLY the Customer rows assigned to them,
-- never Owner/other-Agent/Investor rows, even within their own business.
DO $$
DECLARE v_other_cust_mem UUID; v_other_cust_person BIGINT;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMCUSA02', 'MLPI', '1', 'RAM Customer A2 Unassigned', 'Father A', 'System', 'New') RETURNING person_id INTO v_other_cust_person;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_other_cust_person, pg_temp.fid('biz_a')::UUID, 'Customer', 'Active', 'Direct Registration', 'Not Required') RETURNING membership_id INTO v_other_cust_mem;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since) -- NOT assigned to Agent A
    VALUES (v_other_cust_mem, v_other_cust_person, 'Tailor', CURRENT_DATE);
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('mem_unassigned_customer_a', v_other_cust_mem::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('business_members', format('membership_id = %L', pg_temp.fid('mem_agent_a')), 1,
    'Agent', 'POSITIVE', 'schema §1.8', 'Agent A CAN see their own business_members row (self-select)');
SELECT pg_temp.ram_assert_count('business_members', format('membership_id = %L', pg_temp.fid('mem_owner_a')), 0,
    'Agent', 'NEGATIVE', 'BR-202/203 + rls_role_matrix.md ''single most important negative case''',
    'Agent A cannot see their own Owner''s business_members row via the business-partner policy path — Agent visibility must be Customer-only-and-assigned');
SELECT pg_temp.ram_assert_count('business_members', format('membership_id = %L', pg_temp.fid('mem_unassigned_customer_a')), 0,
    'Agent', 'NEGATIVE', 'AG-004 scoping', 'Agent A cannot see a Customer row in the SAME business that is not assigned to them');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('business_members', format('business_id = %L', pg_temp.fid('biz_a')), 5,
    'Owner', 'POSITIVE', 'schema §1.8', 'Owner A sees all 5 membership rows in their own business (Owner, Agent, Investor, 2x Customer)');

-- =============================================================================
-- MODULE 2 — LOAN TEMPLATES
-- =============================================================================
DO $$
DECLARE v_tmpl_active UUID; v_tmpl_inactive UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO loan_templates (business_id, template_name, status, default_amount, repayment_frequency, duration_value, default_roi_or_interest, default_processing_fee, default_grace_period_days, effective_date)
    VALUES (pg_temp.fid('biz_a')::UUID, 'RAM Active Template', 'Active', 10000, 'Daily', 100, 2.0, 100, 3, CURRENT_DATE) RETURNING template_id INTO v_tmpl_active;
    INSERT INTO loan_templates (business_id, template_name, status, default_amount, repayment_frequency, duration_value, default_roi_or_interest, default_processing_fee, default_grace_period_days, effective_date)
    VALUES (pg_temp.fid('biz_a')::UUID, 'RAM Inactive Template', 'Inactive', 10000, 'Daily', 100, 2.0, 100, 3, CURRENT_DATE) RETURNING template_id INTO v_tmpl_inactive;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('tmpl_active', v_tmpl_active::TEXT), ('tmpl_inactive', v_tmpl_inactive::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('loan_templates', format('template_id = %L', pg_temp.fid('tmpl_active')), 1,
    'Customer', 'POSITIVE', 'schema §2.1', 'Customer A can see an Active loan template in their own business');
SELECT pg_temp.ram_assert_count('loan_templates', format('template_id = %L', pg_temp.fid('tmpl_inactive')), 0,
    'Customer', 'NEGATIVE', 'derived: CW-003 template picker should never offer a retired template',
    'Customer A cannot see an Inactive loan template (never offered a retired template at loan-request time)');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('loan_templates', format('template_id = %L', pg_temp.fid('tmpl_active')), 0,
    'Customer (cross-tenant)', 'NEGATIVE', 'BR-202/203', 'Customer B cannot see Business A''s template at all');

-- =============================================================================
-- MODULE 3 — CUSTOMER DOMAIN
-- =============================================================================
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_a')), 1,
    'Agent (assigned)', 'POSITIVE', 'schema §3.1 + can_view_customers', 'Agent A (can_view_customers, assigned) can read their assigned Customer A''s row');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_a')), 0,
    'Investor', 'NEGATIVE', 'derived: no PERMISSION section grants Investor customer-record access',
    'Investor A cannot read a customer profile row at all — no spec grants Investor visibility into Customer PII');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_a')), 0,
    'Customer (cross-tenant)', 'NEGATIVE', 'BR-202/203', 'Customer B cannot read Customer A''s profile row');
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_b')), 1,
    'Customer (self)', 'POSITIVE', 'schema §3.1', 'Customer B can read their own customer profile row');

-- customer_remarks: internal-only, never customer-visible.
DO $$
DECLARE v_remark UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO customer_remarks (customer_id, entered_by_person_id, remark_text, business_date)
    VALUES (pg_temp.fid('cust_row_a')::UUID, pg_temp.fid('agent_a')::BIGINT, 'RAM internal remark', CURRENT_DATE) RETURNING remark_id INTO v_remark;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('remark_a', v_remark::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customer_remarks', format('remark_id = %L', pg_temp.fid('remark_a')), 0,
    'Customer (self, own record)', 'NEGATIVE', 'derived: internal operational notes are never customer-facing (no CW screen shows remarks)',
    'Customer A cannot read a remark entered ABOUT them — customer_remarks is internal-only per every CW screen spec reviewed');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customer_remarks', format('remark_id = %L', pg_temp.fid('remark_a')), 1,
    'Agent (assigned, can_view_customers)', 'POSITIVE', 'schema §3.3', 'Agent A can read a remark on their own assigned customer');

-- =============================================================================
-- MODULE 4 — AGENT DOMAIN (financially sensitive)
-- =============================================================================
DO $$
DECLARE v_comp UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO agent_compensation_history (agent_id, fixed_salary_amount, salary_cycle, effective_date)
    VALUES ((SELECT agent_id FROM agents WHERE membership_id = pg_temp.fid('mem_agent_a')::UUID), 15000, 'Monthly', CURRENT_DATE)
    RETURNING compensation_id INTO v_comp;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('comp_agent_a', v_comp::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('agent_compensation_history', format('compensation_id = %L', pg_temp.fid('comp_agent_a')), 1,
    'Agent (self)', 'POSITIVE', 'schema §4.2', 'Agent A can see their own salary/compensation row');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('agent_compensation_history', format('compensation_id = %L', pg_temp.fid('comp_agent_a')), 0,
    'Agent (different agent, cross-tenant)', 'NEGATIVE', 'derived: financially sensitive, no Agent-to-Agent visibility in any spec',
    'Agent B cannot see Agent A''s compensation (prevents Agent-to-Agent salary snooping, and is also a cross-tenant boundary)');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('agent_compensation_history', format('compensation_id = %L', pg_temp.fid('comp_agent_a')), 0,
    'Investor', 'NEGATIVE', 'derived: no spec grants Investor visibility into Agent pay', 'Investor A cannot see Agent A''s compensation row');

-- agent_permissions: Agent self-SELECT only, explicitly no self-UPDATE
-- (independently flagged as a privilege-escalation risk before reading
-- rls_role_matrix.md — same conclusion reached there; agreement, not blind trust).
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_write(
    format('UPDATE agent_permissions SET can_issue_loans = TRUE WHERE agent_id = (SELECT agent_id FROM agents WHERE membership_id = %L)', pg_temp.fid('mem_agent_a')),
    FALSE, 'agent_permissions', 'Agent (self)', 'NEGATIVE', 'derived: self-granting permissions is a privilege-escalation hole',
    'Agent A cannot UPDATE their own agent_permissions row (would otherwise be able to self-grant any permission flag)'
);

-- =============================================================================
-- MODULE 5 — INVESTOR DOMAIN (financially sensitive)
-- =============================================================================
DO $$
DECLARE v_inv UUID;
BEGIN
    SELECT investment_id::TEXT INTO v_inv FROM investments WHERE business_id = pg_temp.fid('biz_a')::UUID LIMIT 1;
    INSERT INTO ram_fixture_ids VALUES ('investment_a', v_inv);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('investments', format('investment_id = %L', pg_temp.fid('investment_a')), 1,
    'Investor (self)', 'POSITIVE', 'schema §5.2', 'Investor A can see their own investment row');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('investments', format('investment_id = %L', pg_temp.fid('investment_a')), 0,
    'Investor (different investor)', 'NEGATIVE', 'BR-202/203', 'Investor B cannot see Investor A''s investment row — the exact "one Investor never sees another Investor''s row" case');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('investments', format('investment_id = %L', pg_temp.fid('investment_a')), 0,
    'Customer', 'NEGATIVE', 'derived: no spec grants Customer visibility into Investor financials', 'Customer A cannot see any investment row');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('investments', format('investment_id = %L', pg_temp.fid('investment_a')), 1,
    'Agent (can_view_investor_info)', 'POSITIVE', 'schema §5.2, judgment-call: business-wide because no assigned-investor concept exists',
    'Agent A (can_view_investor_info=TRUE, same business) can see Investment A even though not personally "assigned" to that investor — flag: confirm this business-wide grant is intentional, since it is broader than the Agent-Customer assignment model used elsewhere');

-- =============================================================================
-- MODULE 6 — LOAN DOMAIN
-- =============================================================================
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('loans', format('loan_id = %L', pg_temp.fid('loan_a')), 1,
    'Customer (self)', 'POSITIVE', 'schema §6.1', 'Customer A can see their own loan');
SELECT pg_temp.ram_assert_count('loans', format('loan_id = %L', pg_temp.fid('loan_b')), 0,
    'Customer (cross-tenant, similar loan amount)', 'NEGATIVE', 'BR-202/203',
    'Customer A cannot see Customer B''s loan, even though it has the identical repayment_amount (₹11,000) — rules out an amount-based or business_id-agnostic policy bug');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('loans', format('loan_id = %L', pg_temp.fid('loan_a')), 0,
    'Agent (cross-tenant)', 'NEGATIVE', 'BR-202/203', 'Agent B cannot see Business A''s loan');

-- penalty_entries: can_apply_penalty is OFF by default (BR-236) — confirm
-- an Agent WITHOUT that flag explicitly enabled is rejected on INSERT even
-- though they otherwise have full customer/loan visibility.
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_write(
    format('INSERT INTO penalty_entries (loan_id, penalty_option, penalty_value, penalty_amount_applied, applied_by_person_id, business_date)
            VALUES (%L, ''Flat Amount'', 100, 100, %L, CURRENT_DATE)', pg_temp.fid('loan_a'), pg_temp.fid('agent_a')),
    FALSE, 'penalty_entries', 'Agent (can_apply_penalty=FALSE, the default)', 'NEGATIVE', 'BR-236',
    'Agent A cannot INSERT a penalty_entries row while can_apply_penalty is FALSE — BR-236 default-off must be enforced even for an otherwise fully-permissioned Agent'
);

-- =============================================================================
-- MODULE 7 — COLLECTION DOMAIN
-- =============================================================================
DO $$
DECLARE v_coll UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO collections (loan_id, customer_id, receipt_number, collected_amount, payer_type, collected_by_membership_id, business_date, result_type)
    VALUES (pg_temp.fid('loan_a')::UUID, pg_temp.fid('cust_row_a')::UUID, 'RAM-RCT-A-001', 110, 'Customer', pg_temp.fid('mem_agent_a')::UUID, CURRENT_DATE, 'Full')
    RETURNING collection_id INTO v_coll;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('collection_a', v_coll::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('collections', format('collection_id = %L', pg_temp.fid('collection_a')), 1,
    'Customer (self)', 'POSITIVE', 'schema §7.1', 'Customer A can see the collection recorded against their own loan');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('collections', format('collection_id = %L', pg_temp.fid('collection_a')), 0,
    'Investor', 'NEGATIVE', 'derived: no spec grants Investor visibility into individual collection transactions',
    'Investor A cannot see collection-level detail (even though it indirectly relates to overall business performance)');

-- collection_drafts: Agent-self-scoped even within the SAME business —
-- Agent A2 must not see Agent A's in-progress draft.
DO $$
DECLARE v_agent_a2 BIGINT; v_mem_a2 UUID; v_draft UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1AMAGTA02', 'MLPI', '1', 'RAM Agent A2', 'Father A', 'System', 'New') RETURNING person_id INTO v_agent_a2;
    INSERT INTO business_members (person_id, business_id, role, membership_status, onboarding_method, verification_status)
    VALUES (v_agent_a2, pg_temp.fid('biz_a')::UUID, 'Agent', 'Active', 'Direct Registration', 'Verified') RETURNING membership_id INTO v_mem_a2;
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_mem_a2, v_agent_a2, CURRENT_DATE);
    INSERT INTO collection_drafts (draft_type, created_by_membership_id, payload_json, status)
    VALUES ('Collection', pg_temp.fid('mem_agent_a')::UUID, '{"amount": 110}'::JSON, 'Draft') RETURNING draft_id INTO v_draft;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('agent_a2', v_agent_a2::TEXT), ('draft_agent_a', v_draft::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a2')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('collection_drafts', format('draft_id = %L', pg_temp.fid('draft_agent_a')), 0,
    'Agent (different agent, SAME business)', 'NEGATIVE', 'BR-026/174 + rls_role_matrix.md agreement',
    'Agent A2 cannot see Agent A''s in-progress draft even though both are Active Agents of the SAME business — draft visibility is created_by-scoped, not business-scoped');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('collection_drafts', format('draft_id = %L', pg_temp.fid('draft_agent_a')), 1,
    'Agent (owner of the draft)', 'POSITIVE', 'schema §7.4', 'Agent A can see their own draft');

-- =============================================================================
-- MODULE 8 — FINANCE / CASH / DAY CLOSURE (no Customer/Investor access at all)
-- =============================================================================
DO $$
DECLARE v_ledger UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO day_ledger (business_id, business_date, opening_balance, total_collections, total_loan_distribution,
                            investor_deposits, investor_withdrawals, total_expenses, closing_balance, status)
    VALUES (pg_temp.fid('biz_a')::UUID, CURRENT_DATE, 10000, 500, 0, 0, 0, 0, 10500, 'Open') RETURNING ledger_id INTO v_ledger;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('ledger_a', v_ledger::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('day_ledger', format('ledger_id = %L', pg_temp.fid('ledger_a')), 0,
    'Customer', 'NEGATIVE', 'briefing/derived: zero visibility into business-internal cash figures',
    'Customer A cannot see the business day_ledger at all — business-internal cash aggregate, never customer-facing on any CW screen');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('investor_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('day_ledger', format('ledger_id = %L', pg_temp.fid('ledger_a')), 0,
    'Investor', 'NEGATIVE', 'derived: no IW screen shows business-wide daily cash figures',
    'Investor A cannot see the business day_ledger either — IW-001/003 show only the investor''s own investment figures, never business-wide cash');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('day_ledger', format('ledger_id = %L', pg_temp.fid('ledger_a')), 1,
    'Owner', 'POSITIVE', 'schema §8.2', 'Owner A can see their own business day_ledger row');

-- audit_log: single most restrictive table — Owner SELECT-only, business_id
-- IS NULL rows visible to nobody.
DO $$
DECLARE v_audit_biz UUID; v_audit_platform UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, entry_timestamp)
    VALUES (pg_temp.fid('biz_a')::UUID, pg_temp.fid('owner_a')::BIGINT, 'Settings Change', 'businesses', 1, now()) RETURNING audit_id INTO v_audit_biz;
    INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, entry_timestamp)
    VALUES (NULL, pg_temp.fid('owner_a')::BIGINT, 'Other Admin Event', 'platform', 1, now()) RETURNING audit_id INTO v_audit_platform;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('audit_biz_a', v_audit_biz::TEXT), ('audit_platform', v_audit_platform::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('audit_log', format('audit_id = %L', pg_temp.fid('audit_biz_a')), 1,
    'Owner', 'POSITIVE', 'schema §9.2 / BR-158/124', 'Owner A can SELECT their own business''s audit_log row');
SELECT pg_temp.ram_assert_count('audit_log', format('audit_id = %L', pg_temp.fid('audit_platform')), 0,
    'Owner', 'NEGATIVE', 'briefing: "platform-level events visible to no client role"',
    'Owner A cannot see a platform-level (business_id IS NULL) audit_log row, even though they''re a legitimate Owner elsewhere in the system');
SELECT pg_temp.ram_assert_write(
    format('INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, entry_timestamp)
            VALUES (%L, %L, ''Other Admin Event'', ''loans'', 1, now())', pg_temp.fid('biz_a'), pg_temp.fid('owner_a')),
    FALSE, 'audit_log', 'Owner', 'NEGATIVE', 'briefing: "append-only, service_role/trigger-populated exclusively, Owner included"',
    'Owner A cannot INSERT into audit_log directly, even for their own business — must be system/trigger-populated only'
);
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('audit_log', format('audit_id = %L', pg_temp.fid('audit_biz_a')), 0,
    'Agent', 'NEGATIVE', 'briefing: "no Agent/Investor/Customer read access at all"', 'Agent A cannot read audit_log at all, even for their own business');

-- =============================================================================
-- MODULE 9 — NOTIFICATIONS
-- =============================================================================
DO $$
DECLARE v_notif_a UUID; v_notif_owner_b UUID;
BEGIN
    SET LOCAL ROLE postgres;
    INSERT INTO notifications (recipient_person_id, business_id, notification_type, message)
    VALUES (pg_temp.fid('customer_a')::BIGINT, pg_temp.fid('biz_a')::UUID, 'Other', 'RAM test notification for Customer A');
    SELECT notification_id INTO v_notif_a FROM notifications WHERE recipient_person_id = pg_temp.fid('customer_a')::BIGINT ORDER BY created_at DESC LIMIT 1;
    RESET ROLE;
    INSERT INTO ram_fixture_ids VALUES ('notif_customer_a', v_notif_a::TEXT);
END $$;
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('notifications', format('notification_id = %L', pg_temp.fid('notif_customer_a')), 1,
    'Customer (self)', 'POSITIVE', 'schema §9.1', 'Customer A can see their own notification');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('customer_b')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('notifications', format('notification_id = %L', pg_temp.fid('notif_customer_a')), 0,
    'Customer (different person)', 'NEGATIVE', 'schema §9.1', 'Customer B cannot see Customer A''s notification');
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('owner_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('notifications', format('notification_id = %L', pg_temp.fid('notif_customer_a')), 0,
    'Owner', 'NEGATIVE', 'derived: notifications table has no shared-business-partner policy anywhere in the spec, self-only by design',
    'Owner A cannot read Customer A''s notification even though A is in Owner A''s own business — notifications are strictly self-scoped, not business-scoped');

-- =============================================================================
-- BR-202 ROLE-TRANSITION SCENARIO: Agent A (also a Customer under Business B)
-- must have zero bleed-through between the two role contexts.
-- =============================================================================
DO $$ BEGIN PERFORM pg_temp.ram_login(pg_temp.fid('agent_a')::BIGINT); END $$;
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_a')), 1,
    'Agent A acting under Business A context', 'POSITIVE', 'BR-202', 'Agent A, querying as themselves, still sees their assigned Customer A row via the Agent-in-Business-A relationship');
SELECT pg_temp.ram_assert_count('customers', format('customer_id = %L', pg_temp.fid('cust_row_b')), 0,
    'Agent A (same person, Customer-role in Business B)', 'NEGATIVE', 'BR-202',
    'Agent A cannot see Customer B''s row via their OWN Customer-role membership in Business B (that role has zero visibility into other customers'' profile rows) — confirms role-context does not leak extra Agent-style visibility into their Customer role');
SELECT pg_temp.ram_assert_count('agent_compensation_history', format('compensation_id = %L', pg_temp.fid('comp_agent_a')), 1,
    'Agent A', 'POSITIVE', 'BR-202', 'Agent A still sees their own Agent-role compensation row (their Customer role under Business B does not revoke their Agent-role self-access under Business A)');

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$ BEGIN RESET ROLE; END $$;
DO $$
DECLARE v_total INT; v_passed INT; v_failed INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed) INTO v_total, v_passed, v_failed FROM ram_results;
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'RLS ACCESS MATRIX TESTS: % total, % passed, % FAILED', v_total, v_passed, v_failed;
    RAISE NOTICE '=============================================================';
END $$;

SELECT seq, table_name, role_under_test, direction, br_ref, description, passed FROM ram_results ORDER BY seq;

-- No permanent fixtures or grants are left behind.
ROLLBACK;

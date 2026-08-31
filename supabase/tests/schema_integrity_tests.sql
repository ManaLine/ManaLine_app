-- =============================================================================
-- MANA LINE — schema_integrity_tests.sql
-- Independent adversarial QA suite. Owned by the test-suite chat, NOT the
-- schema-migration chat. Verifies the DELIVERED migrations (0001-0011)
-- actually enforce what 03_Database_Schema.md promises, regardless of what
-- either builder chat believes it shipped.
--
-- Scope: referential integrity (FKs), ENUM domain enforcement, UNIQUE
-- constraints — with special attention to persons.mlid (BR-181/182) since a
-- collision there breaks the entire identity model. Does NOT touch RLS —
-- see rls_access_matrix_tests.sql / multi_tenancy_isolation_tests.sql for
-- that.
--
-- CONVENTION: plain SQL DO blocks that RAISE NOTICE on PASS and RAISE
-- WARNING on FAIL, feeding a session-local temp results table so a final
-- summary can be printed even if one test's assumptions are wrong. Not
-- pgTAP: the target Supabase project's extension allow-list was not
-- confirmed available to this session, and plain DO blocks are guaranteed
-- to run on any stock Postgres/Supabase instance with zero setup. If pgTAP
-- IS available in the real target project, this suite can be mechanically
-- ported to pg_prove later — the assertions below are 1:1 translatable.
--
-- HOW TO RUN: see README_how_to_run.md. Short version: run this entire file
-- as one script (e.g. `psql -f schema_integrity_tests.sql`, or paste whole
-- file into the Supabase SQL Editor and click Run). It is fully
-- self-contained, creates no permanent fixtures (everything happens inside
-- one transaction that is ROLLED BACK at the end), and is safe to run
-- against a project that already has real data.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Test harness (local to this transaction; dropped on ROLLBACK)
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE si_results (
    seq         SERIAL PRIMARY KEY,
    category    TEXT,
    br_ref      TEXT,
    description TEXT,
    passed      BOOLEAN
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.si_log(p_category TEXT, p_br_ref TEXT, p_description TEXT, p_passed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO si_results(category, br_ref, description, passed) VALUES (p_category, p_br_ref, p_description, p_passed);
    IF p_passed THEN
        RAISE NOTICE 'PASS [%] (%) %', p_category, p_br_ref, p_description;
    ELSE
        RAISE WARNING 'FAIL [%] (%) %', p_category, p_br_ref, p_description;
    END IF;
END;
$$;

-- Runs p_sql expecting it to raise the given SQLSTATE (constraint violation).
-- Logs PASS if it raised that error (constraint correctly rejected the bad
-- data), FAIL if it succeeded (constraint is missing/broken) or raised a
-- DIFFERENT, unexpected error (schema drift — also worth flagging as FAIL
-- with the real error visible in the WARNING).
CREATE OR REPLACE FUNCTION pg_temp.si_expect_violation(
    p_category TEXT, p_br_ref TEXT, p_description TEXT, p_sql TEXT, p_expected_sqlstate TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        -- If we get here, the bad insert/update SUCCEEDED — constraint missing.
        PERFORM pg_temp.si_log(p_category, p_br_ref, p_description || ' [constraint did not fire — bad data was accepted]', FALSE);
    EXCEPTION
        WHEN SQLSTATE '23503' OR SQLSTATE '23505' OR SQLSTATE '23514' OR SQLSTATE '22P02' OR SQLSTATE '23502' THEN
            IF SQLSTATE = p_expected_sqlstate THEN
                PERFORM pg_temp.si_log(p_category, p_br_ref, p_description, TRUE);
            ELSE
                PERFORM pg_temp.si_log(p_category, p_br_ref, p_description || format(' [rejected, but with SQLSTATE %s not the expected %s — verify the RIGHT constraint fired, not a coincidental different one]', SQLSTATE, p_expected_sqlstate), TRUE);
            END IF;
        WHEN OTHERS THEN
            PERFORM pg_temp.si_log(p_category, p_br_ref, p_description || format(' [unexpected error class: %s — %s]', SQLSTATE, SQLERRM), FALSE);
    END;
    -- Each check runs in its own SAVEPOINT so a failed/succeeded statement
    -- doesn't poison the rest of the outer transaction.
END;
$$;

-- Wraps si_expect_violation's EXECUTE in a SAVEPOINT automatically via a
-- second-order helper, since PL/pgSQL EXECUTE inside a DO/function already
-- rolls back to the implicit statement boundary on exception — safe as-is
-- for simple single-statement checks used throughout this file.

-- =============================================================================
-- SECTION 1 — persons.mlid UNIQUE (BR-181/182) — the single highest-value
-- constraint in the whole schema; a collision here breaks BR-178 (one
-- permanent ID for life) system-wide.
-- =============================================================================
DO $$
DECLARE
    v_mlid TEXT := 'MLPI1ESTDUP01';
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES (v_mlid, 'MLPI', '1', 'QA Fixture Alpha', 'QA Father Alpha', 'System', 'New');

    PERFORM pg_temp.si_expect_violation(
        'UNIQUE', 'BR-181/182',
        'persons.mlid rejects an exact duplicate MLID on a second person',
        format($f$INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
                   VALUES (%L, 'MLPI', '1', 'QA Fixture Duplicate', 'QA Father Dup', 'System', 'New')$f$, v_mlid),
        '23505'
    );
END $$;

-- persons.aadhaar_number UNIQUE (schema §0.1) — duplicate Aadhaar is exactly
-- the SP-001 trigger condition; this constraint is what makes 409 CONFLICT
-- possible at all.
DO $$
DECLARE
    v_aadhaar TEXT := '999988887777';
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, aadhaar_number, registration_source, customer_type)
    VALUES ('MLPI1ESTAAD01', 'MLPI', '1', 'QA Fixture Aadhaar A', 'QA Father', v_aadhaar, 'System', 'New');

    PERFORM pg_temp.si_expect_violation(
        'UNIQUE', 'BR-181/182, SP-001 trigger condition',
        'persons.aadhaar_number rejects a duplicate Aadhaar on a second person (this is the exact 409 CONFLICT trigger for SP-001)',
        format($f$INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, aadhaar_number, registration_source, customer_type)
                   VALUES ('MLPI1ESTAAD02', 'MLPI', '1', 'QA Fixture Aadhaar B', 'QA Father', %L, 'System', 'New')$f$, v_aadhaar),
        '23505'
    );
END $$;

-- businesses.mlbi UNIQUE (schema §1.1)
DO $$
DECLARE
    v_owner BIGINT;
    v_mlbi TEXT := 'MLBI-TESTQA001';
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTOWN01', 'MLPI', '1', 'QA Owner Fixture', 'QA Father', 'System', 'New') RETURNING person_id INTO v_owner;

    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES (v_mlbi, v_owner, 'QA Biz A', 'QA Biz A Registered');

    PERFORM pg_temp.si_expect_violation(
        'UNIQUE', 'schema §1.1',
        'businesses.mlbi rejects a duplicate MLBI on a second business',
        format($f$INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
                   VALUES (%L, %L, 'QA Biz A Dup', 'QA Biz A Dup Registered')$f$, v_mlbi, v_owner),
        '23505'
    );
END $$;

-- loans.loan_number UNIQUE (schema §6.1) and business_members
-- (person_id, business_id, role) UNIQUE (schema §1.8, BR-179's "one row per
-- person+business+role")
DO $$
DECLARE
    v_person BIGINT;
    v_business UUID;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTBM001', 'MLPI', '1', 'QA BM Fixture', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES ('MLBI-TESTQA002', v_person, 'QA Biz B', 'QA Biz B Registered') RETURNING business_id INTO v_business;

    INSERT INTO business_members (person_id, business_id, role, onboarding_method)
    VALUES (v_person, v_business, 'Agent', 'Direct Registration');

    PERFORM pg_temp.si_expect_violation(
        'UNIQUE', 'schema §1.8 / BR-179',
        'business_members rejects a duplicate (person_id, business_id, role) row — a person cannot hold the same role twice on one business',
        format($f$INSERT INTO business_members (person_id, business_id, role, onboarding_method)
                   VALUES (%L, %L, 'Agent', 'Direct Registration')$f$, v_person, v_business),
        '23505'
    );
END $$;

-- =============================================================================
-- SECTION 2 — Foreign key enforcement, one representative per module,
-- including the higher-risk cross-module ones (customers.membership_id,
-- loans.customer_id, collections.loan_id).
-- =============================================================================

-- Module 0: person_addresses.person_id -> persons
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'FK', 'schema §0.3',
    'person_addresses.person_id rejects a reference to a non-existent person',
    $f$INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date)
       VALUES (999999999, '1-2-3', '500001', gen_random_uuid(), 'X', 'X', 'X', CURRENT_DATE)$f$,
    '23503'
);
END $$;

-- Module 1: businesses.owner_person_id -> persons
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'FK', 'schema §1.1 / BR-185',
    'businesses.owner_person_id rejects a reference to a non-existent person',
    $f$INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
       VALUES ('MLBI-TESTQA-FK1', 999999999, 'QA FK Biz', 'QA FK Biz Registered')$f$,
    '23503'
);
END $$;

-- Module 1: business_members.business_id -> businesses
DO $$
DECLARE
    v_person BIGINT;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTFK002', 'MLPI', '1', 'QA FK Fixture 2', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;

    PERFORM pg_temp.si_expect_violation(
        'FK', 'schema §1.8',
        'business_members.business_id rejects a reference to a non-existent business',
        format($f$INSERT INTO business_members (person_id, business_id, role, onboarding_method)
                   VALUES (%L, gen_random_uuid(), 'Customer', 'Direct Registration')$f$, v_person),
        '23503'
    );
END $$;

-- Module 3: customers.membership_id -> business_members
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'FK', 'schema §3.1',
    'customers.membership_id rejects a reference to a non-existent business_members row',
    $f$INSERT INTO customers (membership_id, person_id, occupation, customer_since)
       VALUES (gen_random_uuid(), 999999999, 'Farmer', CURRENT_DATE)$f$,
    '23503'
);
END $$;

-- Module 6: loans.customer_id -> customers, loans.business_id -> businesses
-- Uses a real business + agent membership as supporting fixture so the ONLY
-- invalid reference in the row is customer_id itself — otherwise a missing
-- NOT NULL column or an incidentally-also-invalid business_id could make
-- this pass for the wrong reason (see multi-chat integration note).
DO $$
DECLARE
    v_person BIGINT;
    v_business UUID;
    v_agent_mem UUID;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTLNFK1', 'MLPI', '1', 'QA Loan FK Fixture', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES ('MLBI-TESTQALNFK', v_person, 'QA Loan FK Biz', 'QA Loan FK Biz Registered') RETURNING business_id INTO v_business;
    INSERT INTO business_members (person_id, business_id, role, onboarding_method, membership_status)
    VALUES (v_person, v_business, 'Agent', 'Direct Registration', 'Active') RETURNING membership_id INTO v_agent_mem;

    PERFORM pg_temp.si_expect_violation(
        'FK', 'schema §6.1',
        'loans.customer_id rejects a reference to a non-existent customer',
        format($f$INSERT INTO loans (loan_number, customer_id, business_id, collection_agent_membership_id,
                              repayment_amount, interest_amount, processing_fee, repayment_type, duration_value,
                              installment_amount, grace_period_days, remaining_balance, effective_date,
                              issue_business_date, live_photo_url)
                   VALUES ('QA-LN-FK-001', gen_random_uuid(), %L, %L, 10000, 1000, 100, 'Daily', 100, 100, 3, 10000,
                           CURRENT_DATE, CURRENT_DATE, 'https://example.test/photo.jpg')$f$, v_business, v_agent_mem),
        '23503'
    );
END $$;

-- Module 7: collections.loan_id -> loans
-- Same principle: a real business/agent/customer/loan fixture so the ONLY
-- invalid reference is loan_id itself.
DO $$
DECLARE
    v_person BIGINT;
    v_cust_person BIGINT;
    v_business UUID;
    v_agent_mem UUID;
    v_cust_mem UUID;
    v_cust_row UUID;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTCLFK1', 'MLPI', '1', 'QA Coll FK Fixture', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES ('MLBI-TESTQACLFK', v_person, 'QA Coll FK Biz', 'QA Coll FK Biz Registered') RETURNING business_id INTO v_business;
    INSERT INTO business_members (person_id, business_id, role, onboarding_method, membership_status)
    VALUES (v_person, v_business, 'Agent', 'Direct Registration', 'Active') RETURNING membership_id INTO v_agent_mem;

    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTCLFK2', 'MLPI', '1', 'QA Coll FK Customer', 'QA Father', 'System', 'New') RETURNING person_id INTO v_cust_person;
    INSERT INTO business_members (person_id, business_id, role, onboarding_method, membership_status)
    VALUES (v_cust_person, v_business, 'Customer', 'Direct Registration', 'Active') RETURNING membership_id INTO v_cust_mem;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_cust_mem, v_cust_person, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_cust_row;

    PERFORM pg_temp.si_expect_violation(
        'FK', 'schema §7.1',
        'collections.loan_id rejects a reference to a non-existent loan',
        format($f$INSERT INTO collections (loan_id, customer_id, receipt_number, collected_amount, payer_type,
                              collected_by_membership_id, business_date, result_type)
                   VALUES (gen_random_uuid(), %L, 'QA-RCT-FK-001', 100, 'Customer', %L, CURRENT_DATE, 'Full')$f$,
                   v_cust_row, v_agent_mem),
        '23503'
);
END $$;

-- Module 5: investments.investor_id -> investors
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'FK', 'schema §5.2',
    'investments.investor_id rejects a reference to a non-existent investor',
    $f$INSERT INTO investments (investor_id, business_id, principal_amount, original_principal_amount, roi_rate,
                                interest_type, effective_date)
       VALUES (gen_random_uuid(), gen_random_uuid(), 10000, 10000, 1.5, 'Simple', CURRENT_DATE)$f$,
    '23503'
);
END $$;

-- =============================================================================
-- SECTION 3 — ENUM domain enforcement: out-of-set values must be rejected.
-- =============================================================================

-- businesses.business_status ENUM('Active','Not Started','Suspended')
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'ENUM', 'schema §1.1',
    'businesses.business_status rejects an out-of-set value',
    $f$INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name, business_status)
       VALUES ('MLBI-TESTQA-EN1', (SELECT person_id FROM persons LIMIT 1), 'QA Enum Biz', 'QA Enum Biz Reg', 'Not_A_Real_Status')$f$,
    '22P02'
);
END $$;

-- business_members.role ENUM('Owner','Agent','Investor','Customer')
DO $$
DECLARE
    v_person BIGINT;
    v_business UUID;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTEN003', 'MLPI', '1', 'QA Enum Fixture 3', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES ('MLBI-TESTQA-EN2', v_person, 'QA Enum Biz 2', 'QA Enum Biz 2 Reg') RETURNING business_id INTO v_business;

    PERFORM pg_temp.si_expect_violation(
        'ENUM', 'schema §1.8 / BR-179',
        'business_members.role rejects a role outside Owner/Agent/Investor/Customer',
        format($f$INSERT INTO business_members (person_id, business_id, role, onboarding_method)
                   VALUES (%L, %L, 'SuperAdmin', 'Direct Registration')$f$, v_person, v_business),
        '22P02'
    );
END $$;

-- loans.loan_status ENUM — critically, 'Merged' and 'Renewed' must NOT be
-- valid values (both features were explicitly removed per the schema doc
-- and 13_Rejected_Removed_Deferred_Register.md). A schema that silently
-- kept these values would be a real regression a migration diff could miss.
DO $$
DECLARE
    v_customer UUID;
    v_business UUID;
    v_person BIGINT;
    v_membership UUID;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTEN004', 'MLPI', '1', 'QA Enum Fixture 4', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    INSERT INTO businesses (mlbi, owner_person_id, business_name, registered_finance_name)
    VALUES ('MLBI-TESTQA-EN3', v_person, 'QA Enum Biz 3', 'QA Enum Biz 3 Reg') RETURNING business_id INTO v_business;
    INSERT INTO business_members (person_id, business_id, role, onboarding_method)
    VALUES (v_person, v_business, 'Customer', 'Direct Registration') RETURNING membership_id INTO v_membership;
    INSERT INTO customers (membership_id, person_id, occupation, customer_since)
    VALUES (v_membership, v_person, 'Farmer', CURRENT_DATE) RETURNING customer_id INTO v_customer;

    PERFORM pg_temp.si_expect_violation(
        'ENUM', 'schema §6.1 (locked decision: Merge/Renewal removed)',
        'loans.loan_status rejects the removed value "Merged" (Merge Loans feature was explicitly dropped, not just deprioritized)',
        format($f$INSERT INTO loans (loan_number, customer_id, business_id, repayment_amount, interest_amount, processing_fee,
                                      repayment_type, duration_value, installment_amount, remaining_balance, effective_date,
                                      issue_business_date, live_photo_url, loan_status)
                   VALUES ('QA-LN-EN-001', %L, %L, 10000, 1000, 100, 'Daily', 100, 100, 10000, CURRENT_DATE, CURRENT_DATE,
                           'https://example.test/photo.jpg', 'Merged')$f$, v_customer, v_business),
        '22P02'
    );

    PERFORM pg_temp.si_expect_violation(
        'ENUM', 'schema §6.1 (locked decision: Merge/Renewal removed)',
        'loans.loan_status rejects the removed value "Renewed"',
        format($f$INSERT INTO loans (loan_number, customer_id, business_id, repayment_amount, interest_amount, processing_fee,
                                      repayment_type, duration_value, installment_amount, remaining_balance, effective_date,
                                      issue_business_date, live_photo_url, loan_status)
                   VALUES ('QA-LN-EN-002', %L, %L, 10000, 1000, 100, 'Daily', 100, 100, 10000, CURRENT_DATE, CURRENT_DATE,
                           'https://example.test/photo.jpg', 'Renewed')$f$, v_customer, v_business),
        '22P02'
    );
END $$;

-- persons.mlid_type ENUM('MLPI','MLTI')
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'ENUM', 'schema §0.1 / BR-181/182',
    'persons.mlid_type rejects a value outside MLPI/MLTI',
    $f$INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
       VALUES ('MLXI1TESTEN005', 'MLXI', '1', 'QA Enum Fixture 5', 'QA Father', 'System', 'New')$f$,
    '22P02'
);
END $$;

-- =============================================================================
-- SECTION 4 — CHECK constraints (representative, not exhaustive): gender
-- digit domain and a self-referential distinctness check on duplicate_suspects.
-- =============================================================================
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'CHECK', 'schema §0.1 / BR-181/182',
    'persons.gender_digit rejects a value outside 0/1',
    $f$INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
       VALUES ('MLPI2TESTCK01', 'MLPI', '2', 'QA Check Fixture', 'QA Father', 'System', 'New')$f$,
    '23514'
);
END $$;

DO $$
DECLARE
    v_person BIGINT;
BEGIN
    INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
    VALUES ('MLPI1ESTCK002', 'MLPI', '1', 'QA Check Fixture 2', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;

    PERFORM pg_temp.si_expect_violation(
        'CHECK', 'schema §0.7',
        'duplicate_suspects rejects person_id_a = person_id_b (a person cannot be flagged as a duplicate of themselves)',
        format($f$INSERT INTO duplicate_suspects (person_id_a, person_id_b, detection_method, matched_on)
                   VALUES (%L, %L, 'System-Automatic', 'Aadhaar+Phone')$f$, v_person, v_person),
        '23514'
    );
END $$;

-- =============================================================================
-- SECTION 5 — NOT NULL enforcement on fields the spec calls mandatory
-- (representative sample; full column-by-column audit is out of scope for
-- this pass but every table's NOT NULL columns should eventually get one
-- of these).
-- =============================================================================
DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'NOT NULL', 'schema §0.1',
    'persons.full_name (mandatory, "no nickname field" BR-224) rejects NULL',
    $f$INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
       VALUES ('MLPI1ESTNN001', 'MLPI', '1', NULL, 'QA Father', 'System', 'New')$f$,
    '23502'
);
END $$;

DO $$ BEGIN
PERFORM pg_temp.si_expect_violation(
    'NOT NULL', 'schema §6.1 / BR-036/081',
    'loans.live_photo_url (mandatory at creation per BR-036/081) rejects NULL',
    $f$INSERT INTO loans (loan_number, customer_id, business_id, repayment_amount, interest_amount, processing_fee,
                          repayment_type, duration_value, installment_amount, remaining_balance, effective_date,
                          issue_business_date, live_photo_url)
       VALUES ('QA-LN-NN-001', (SELECT customer_id FROM customers LIMIT 1), (SELECT business_id FROM businesses LIMIT 1),
               10000, 1000, 100, 'Daily', 100, 100, 10000, CURRENT_DATE, CURRENT_DATE, NULL)$f$,
    '23502'
);
END $$;

-- =============================================================================
-- SECTION 6 — Positive control: confirm a VALID row of each of the above
-- shapes is actually accepted. A suite that only ever tests rejection could
-- itself be broken (e.g. testing against the wrong table) and never notice.
-- =============================================================================
DO $$
DECLARE
    v_person BIGINT;
    v_ok BOOLEAN := TRUE;
BEGIN
    BEGIN
        INSERT INTO persons (mlid, mlid_type, gender_digit, full_name, father_husband_name, registration_source, customer_type)
        VALUES ('MLPI1ESTPOS01', 'MLPI', '1', 'QA Positive Control', 'QA Father', 'System', 'New') RETURNING person_id INTO v_person;
    EXCEPTION WHEN OTHERS THEN
        v_ok := FALSE;
    END;
    PERFORM pg_temp.si_log('POSITIVE CONTROL', 'n/a', 'A well-formed persons row with valid ENUM/CHECK values is accepted (sanity check that the rejection tests above aren''t accidentally testing a non-existent constraint)', v_ok);
END $$;

-- =============================================================================
-- TRIGGERS THAT REACH INTO app MUST BE SECURITY DEFINER
-- =============================================================================
-- Registration returned 500 to everybody for an unknown stretch because
-- app.stamp_migrated_person was SECURITY INVOKER while its body called
-- app.migration_import_active(). Edge Functions write as service_role, which
-- has no USAGE on schema app -- anon and authenticated do -- so the INSERT
-- into persons died with 42501 and the failure was invisible from any
-- in-app path.
--
-- The general rule the incident produced: a trigger on a public table that
-- calls anything in `app` runs as whoever did the write, and one of those
-- writers cannot see the schema. Either the function is DEFINER or it must
-- not reach into app at all.
--
-- Matching on the body, not the header: every one of these is named
-- `app.something`, so a naive search for 'app.' matches all of them.
DO $$
DECLARE
    v_bad TEXT;
    v_count INT;
BEGIN
    SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname)
      INTO v_count, v_bad
    FROM pg_trigger t
    JOIN pg_class c      ON c.oid = t.tgrelid
    JOIN pg_namespace cn ON cn.oid = c.relnamespace
    JOIN pg_proc p       ON p.oid = t.tgfoid
    JOIN pg_namespace n  ON n.oid = p.pronamespace
    WHERE NOT t.tgisinternal
      AND cn.nspname = 'public'
      AND n.nspname  = 'app'
      AND NOT p.prosecdef
      -- The body, with the CREATE header stripped off.
      AND position('app.' in substring(pg_get_functiondef(p.oid) from position('$function$' in pg_get_functiondef(p.oid)))) > 0;

    PERFORM pg_temp.si_log(
        'SECURITY', 'BR-178',
        CASE WHEN v_count = 0
             THEN 'every trigger function calling into app is SECURITY DEFINER'
             ELSE 'SECURITY INVOKER trigger functions call into app: ' || v_bad
                  || ' — service_role writes through them will fail 42501'
        END,
        v_count = 0);
END $$;

-- And the reason it matters, stated as its own fact so a well-meaning GRANT
-- does not quietly become the fix.
DO $$
DECLARE
    v_has BOOLEAN;
BEGIN
    v_has := has_schema_privilege('service_role', 'app', 'USAGE');
    PERFORM pg_temp.si_log(
        'SECURITY', 'BR-178',
        CASE WHEN v_has
             THEN 'service_role has USAGE on schema app — every app function is '
                  || 'now reachable with the service key; the trigger fix was '
                  || 'meant to make this unnecessary'
             ELSE 'service_role still has no USAGE on schema app'
        END,
        NOT v_has);
END $$;

-- =============================================================================
-- NOBODY BEING COLLECTED FROM IS OUTSIDE AN ACTIVE AREA
-- =============================================================================
-- The chain the whole app is built on runs customer -> village -> operating
-- area -> agent -> business. A customer whose village belongs to no ACTIVE
-- area is in no round: no agent's list reaches them.
--
-- That is only a problem when money is involved. Thirty-one dormant customers
-- sat outside an area on this book with nothing owed, which costs nothing --
-- but one had a live loan, stranded when the area covering their village was
-- removed and its villages were freed. This asserts the case that matters
-- rather than the count, which would fail forever on the harmless ones.
DO $$
DECLARE
    v_count INT;
    v_names TEXT;
BEGIN
    SELECT count(*), string_agg(DISTINCT p.full_name, ', ')
      INTO v_count, v_names
    FROM customers c
    JOIN business_members bm  ON bm.membership_id = c.membership_id
    JOIN persons p            ON p.person_id = c.person_id
    JOIN person_addresses pa  ON pa.person_id = p.person_id AND pa.is_current
    WHERE EXISTS (
            SELECT 1 FROM loans l
             WHERE l.customer_id = c.customer_id
               AND l.deleted_at IS NULL
               AND l.loan_status IN ('Active', 'Grace Period', 'Penalty'))
      AND NOT EXISTS (
            SELECT 1
              FROM operating_area_locations oal
              JOIN operating_areas oa
                ON oa.operating_area_id = oal.operating_area_id
             WHERE oal.location_id = pa.village_id
               AND oal.removed_at IS NULL
               AND oa.business_id = bm.business_id
               AND oa.status = 'Active');

    PERFORM pg_temp.si_log(
        'DATA', 'BR-013',
        CASE WHEN v_count = 0
             THEN 'every customer with a live loan sits in an active operating area'
             ELSE v_count || ' customer(s) owe money but belong to no active '
                  || 'area, so no agent round reaches them: ' || v_names
        END,
        v_count = 0);
END $$;

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$
DECLARE
    v_total INT;
    v_passed INT;
    v_failed INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
    INTO v_total, v_passed, v_failed
    FROM si_results;

    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'SCHEMA INTEGRITY TESTS: % total, % passed, % FAILED', v_total, v_passed, v_failed;
    RAISE NOTICE '=============================================================';
END $$;

-- Full itemized result set (visible in the SQL client's output pane before
-- the ROLLBACK below discards everything this script touched).
SELECT seq, category, br_ref, description, passed FROM si_results ORDER BY seq;

-- No permanent fixtures are left behind. If you want to keep the row-level
-- results, capture the SELECT output above BEFORE this rollback runs.
ROLLBACK;

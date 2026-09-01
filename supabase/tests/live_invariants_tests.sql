-- =============================================================================
-- MANA LINE — live_invariants_tests.sql
-- @target: production
--
-- The assertions that are only meaningful against a real book, and that are
-- safe to run against one because they read and never write.
--
-- WHY THIS FILE EXISTS SEPARATELY. Every other file in this directory
-- fabricates its own fixtures — persons, businesses, loans — and must never be
-- pointed at a live database. That makes them branch-only. But the checks that
-- matter most day to day are the opposite: a customer stranded outside every
-- active area, a village whose state the directory does not carry, a loan that
-- asks for nothing while money is owed. None of those can be reproduced with
-- fixtures, because the thing being tested IS the production data. Run against
-- an empty branch they all pass trivially and prove nothing.
--
-- So the two kinds are split, and the runner treats them differently. Files
-- marked `@target: scratch` are refused against production. This one is marked
-- `@target: production` and the runner opens the session with
-- default_transaction_read_only=on, so a write does not merely violate a
-- convention — it raises 25006 and stops the file.
--
-- That read-only session is the actual guard, and it is deliberately a RUNTIME
-- one. The static version — grep the file for INSERT — is what I had, and it
-- reported migration_weekly_ledger_tests.sql as writing nothing at all. Its
-- writes happen inside app.import_weekly_account, which no amount of reading
-- the file's own statements will reveal. Only executing it does.
--
-- NO DDL ANYWHERE BELOW, and that is a constraint rather than a style. The
-- other files here open with a temp results table and a pg_temp log function;
-- both are DDL, and a read-only transaction refuses CREATE TABLE and CREATE
-- FUNCTION alike — verified by running it, not assumed. So each assertion
-- raises its own NOTICE or WARNING inline, and the failure count rides in a
-- custom GUC, which set_config is permitted to write. The runner only ever
-- reads the WARNING lines, so nothing is lost.
-- =============================================================================

DO $$ BEGIN PERFORM set_config('mana.li_failures', '0', false); END $$;

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
      AND position('app.' in substring(pg_get_functiondef(p.oid) from position('$function$' in pg_get_functiondef(p.oid)))) > 0;

    IF v_count = 0 THEN
        RAISE NOTICE 'PASS [SECURITY] (BR-178) every trigger function calling into app is SECURITY DEFINER';
    ELSE
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + 1)::text, false);
        RAISE WARNING 'FAIL [SECURITY] (BR-178) SECURITY INVOKER trigger functions call into app: % — service_role writes through them will fail 42501', v_bad;
    END IF;
END $$;

-- And the reason it matters, stated as its own fact so a well-meaning GRANT
-- does not quietly become the fix.
DO $$
DECLARE
    v_has BOOLEAN;
BEGIN
    v_has := has_schema_privilege('service_role', 'app', 'USAGE');
    IF NOT v_has THEN
        RAISE NOTICE 'PASS [SECURITY] (BR-178) service_role still has no USAGE on schema app';
    ELSE
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + 1)::text, false);
        RAISE WARNING 'FAIL [SECURITY] (BR-178) service_role HAS USAGE on schema app — every app function is now reachable with the service key; the trigger fix was meant to make this unnecessary';
    END IF;
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

    IF v_count = 0 THEN
        RAISE NOTICE 'PASS [DATA] (BR-013) every customer with a live loan sits in an active operating area';
    ELSE
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + 1)::text, false);
        RAISE WARNING 'FAIL [DATA] (BR-013) % customer(s) owe money but belong to no active area, so no agent round reaches them: %', v_count, v_names;
    END IF;
END $$;

-- =============================================================================
-- EVERY VILLAGE'S STATE IS ONE THE DIRECTORY KNOWS
-- =============================================================================
-- A village row recorded its state as "Andhrapradesh" where the directory --
-- and every other row -- says "Andhra Pradesh".
--
-- That is not a spelling nit. manaReferenceOptions narrows the district and
-- mandal pickers by matching the chosen state EXACTLY against lgd_villages,
-- so a state the directory does not carry narrows to nothing: the person
-- editing that address gets an empty district list and falls back to free
-- text, which is how the row was created in the first place. One typed value
-- reproduces itself.
--
-- Matched on the state alone rather than the whole village row on purpose.
-- A village that is genuinely absent from the directory is allowed -- rural
-- India has plenty, and Add New Village exists for them. A STATE that is
-- absent is a typo every time.
DO $$
DECLARE
    v_count INT;
    v_bad TEXT;
BEGIN
    SELECT count(*), string_agg(DISTINCT l.state, ', ')
      INTO v_count, v_bad
      FROM locations l
     WHERE l.state IS NOT NULL
       AND btrim(l.state) <> ''
       AND NOT EXISTS (SELECT 1 FROM lgd_villages v WHERE v.state = l.state);

    IF v_count = 0 THEN
        RAISE NOTICE 'PASS [DATA] (BR-013) every village records a state the PIN directory knows';
    ELSE
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + 1)::text, false);
        RAISE WARNING 'FAIL [DATA] (BR-013) % village row(s) record a state the directory does not carry, so their district and mandal pickers can never narrow: %', v_count, v_bad;
    END IF;
END $$;

-- =============================================================================
-- NO LOAN UNDERSTATES WHAT IS DUE TO ZERO
-- =============================================================================
-- Regression for the Rs 0 that Garikipati Kamala Reddy's round showed while
-- she owed Rs 12,000. Her Rs 24,000 loan was half repaid before the cut-off,
-- so the import materialised six Rs 2,000 rows -- the balance, not the term.
-- Deriving "already paid" from (repayment - remaining) counted those six
-- payments a second time and cancelled the whole amount due.
--
-- The failure direction is what makes it dangerous: the app asked for LESS
-- than was owed. Nobody reports being under-charged.
DO $$
DECLARE
    v_count INT;
    v_which TEXT;
BEGIN
    SELECT count(*), string_agg(DISTINCT p.full_name, ', ')
      INTO v_count, v_which
      FROM app.v_collection_due v
      JOIN loans l     ON l.loan_id = v.loan_id
      JOIN customers c ON c.customer_id = l.customer_id
      JOIN persons p   ON p.person_id = c.person_id
     WHERE l.deleted_at IS NULL
       AND v.remaining_balance > 0
       AND v.total_due = 0
       -- Every scheduled instalment already fell due, and the schedule totals
       -- exactly what is still owed: there is nothing left to wait for, so a
       -- due of zero can only be the double count.
       AND NOT EXISTS (SELECT 1 FROM loan_schedule s
                        WHERE s.loan_id = l.loan_id AND s.due_date > CURRENT_DATE)
       AND (SELECT COALESCE(sum(s.installment_amount), 0) FROM loan_schedule s
             WHERE s.loan_id = l.loan_id) = l.remaining_balance;

    IF v_count = 0 THEN
        RAISE NOTICE 'PASS [MONEY] (BR-013) no loan understates what is due to zero';
    ELSE
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + 1)::text, false);
        RAISE WARNING 'FAIL [MONEY] (BR-013) % loan(s) owe money, have no future instalments, and still show nothing due: %', v_count, v_which;
    END IF;
END $$;

-- =============================================================================
-- THE INTEREST ENGINE STILL AGREES WITH THE OWNER'S CALCULATOR
-- =============================================================================
-- Whole calendar months, then leftover days at one thirtieth of the monthly
-- rate. Every figure below was read off the Owner's own calculator (JMK Easy
-- Apps) or their profit-share sheet. A pure function with no fixtures, so it
-- belongs with the checks that can run anywhere.
DO $$
DECLARE
    r RECORD;
    v_failed INT := 0;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
          ('11 days inside one month = 413',
           app.mana_interest(75000,  1.5, DATE '2026-03-20', DATE '2026-03-31'), 413),
          ('2 months 3 days = 2,363, not 2,400 (days/30 is wrong)',
           app.mana_interest(75000,  1.5, DATE '2026-03-20', DATE '2026-05-23'), 2363),
          ('4 months 5 days = 15,625',
           app.mana_interest(250000, 1.5, DATE '2026-03-20', DATE '2026-07-25'), 15625),
          ('1 month 3 days = 825',
           app.mana_interest(50000,  1.5, DATE '2026-03-20', DATE '2026-04-23'), 825),
          ('declared and paid the same day accrues nothing',
           app.mana_interest(50000,  1.5, DATE '2026-03-20', DATE '2026-03-20'), 0),
          ('a return date before the given date accrues nothing',
           app.mana_interest(50000,  1.5, DATE '2026-03-20', DATE '2026-03-01'), 0)
        ) AS t(label, actual, expected)
    LOOP
        IF r.actual = r.expected THEN
            RAISE NOTICE 'PASS [MONEY] (CALC-ENGINE) %', r.label;
        ELSE
            v_failed := v_failed + 1;
            RAISE WARNING 'FAIL [MONEY] (CALC-ENGINE) % — got %, expected %', r.label, r.actual, r.expected;
        END IF;
    END LOOP;

    IF v_failed > 0 THEN
        PERFORM set_config('mana.li_failures',
                           (current_setting('mana.li_failures', true)::int + v_failed)::text, false);
    END IF;
END $$;

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$
DECLARE
    v_failed INT := COALESCE(current_setting('mana.li_failures', true)::int, 0);
BEGIN
    RAISE NOTICE '=============================================================';
    IF v_failed = 0 THEN
        RAISE NOTICE 'LIVE INVARIANTS: all passed';
    ELSE
        RAISE NOTICE 'LIVE INVARIANTS: % FAILED', v_failed;
    END IF;
    RAISE NOTICE '=============================================================';
END $$;

-- No ROLLBACK, and none is possible to need: this file opens no transaction and
-- writes nothing. The runner enforces that with default_transaction_read_only,
-- and test/sql_tests_wired_test.dart requires a @target line on every file so a
-- new one cannot quietly inherit the wrong treatment.

-- =============================================================================
-- MANA LINE — migration_weekly_ledger_tests.sql
-- The regression that stops the pre-existing-business migration drifting.
--
-- Replays the Owner's real 2026 book — 12 weeks, 2-1-26 to 20-3-26, taken from
-- Weekly sheet.docx and cross-checked against Account sheet.xlsx — and asserts
-- the figures the Owner's own sheet states:
--
--     final BF            100        (a previous design derived 4,350: WRONG)
--     collections     1,160,700
--     fee                52,900      (their book; the loans carry 64,900)
--     expenses          184,500
--     investor interest  77,332
--     withdrawal int      7,750
--
-- and, once loans carrying 720,600 of interest exist,
--     profit = 720,600 + 52,900 - 184,500 - (77,332 - 7,750) = 519,418.
--
-- Same convention as the other files here: DO blocks, RAISE NOTICE on PASS,
-- RAISE WARNING on FAIL, one transaction, ROLLBACK at the end.
-- =============================================================================

BEGIN;

CREATE TEMP TABLE wk_results (
    seq         SERIAL PRIMARY KEY,
    description TEXT,
    passed      BOOLEAN
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.wk_log(p_description TEXT, p_passed BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO wk_results (description, passed) VALUES (p_description, p_passed);
    IF p_passed THEN
        RAISE NOTICE 'PASS  %', p_description;
    ELSE
        RAISE WARNING 'FAIL  %', p_description;
    END IF;
END;
$$;

DO $test$
DECLARE
  v_biz    uuid;
  v_person bigint;
  v_result json;
  v_summary json;
  v_bf numeric;
  v_through date;
  v_weeks json := '[
   {"account_date":"2026-01-02","opening_bf":0,"collection":0,"interest":112800,"fee":6280,"investor_in":1000000,"investor_in_interest":39000,"loans_gross_out":626800,"closing_bf":491380,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-01-09","opening_bf":491380,"collection":33020,"interest":76600,"fee":4940,"loans_gross_out":423600,"closing_bf":181440,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-01-16","opening_bf":181440,"collection":48720,"interest":5200,"fee":520,"investor_in":26000,"investor_in_interest":832,"loans_gross_out":31200,"closing_bf":229260,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400},{"label":"Bike repair","amount":520}]},
   {"account_date":"2026-01-23","opening_bf":229260,"collection":94820,"interest":7200,"fee":720,"loans_gross_out":43200,"closing_bf":134800,"expenses":[{"label":"Petrol","amount":600},{"label":"Sadaru","amount":400},{"label":"New Bike","amount":150000},{"label":"Train tickets","amount":3000}]},
   {"account_date":"2026-01-30","opening_bf":134800,"collection":71520,"interest":44400,"fee":4140,"loans_gross_out":251400,"closing_bf":2460,"expenses":[{"label":"Petrol","amount":600},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-02-06","opening_bf":2460,"collection":74020,"interest":27000,"fee":2700,"investor_in":500000,"investor_in_interest":11000,"loans_gross_out":162000,"closing_bf":443280,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-02-13","opening_bf":443280,"collection":53120,"interest":0,"fee":0,"loans_gross_out":0,"closing_bf":495500,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-02-20","opening_bf":495500,"collection":68620,"interest":144000,"fee":14400,"investor_in":1000000,"investor_in_interest":15000,"investor_out":400000,"investor_out_interest":6000,"loans_gross_out":864000,"closing_bf":457820,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":200}]},
   {"account_date":"2026-02-27","opening_bf":457820,"collection":173140,"interest":144000,"fee":3800,"investor_in":1000000,"investor_in_interest":11500,"loans_gross_out":834000,"closing_bf":925760,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400},{"label":"tickets","amount":5000},{"label":"salary","amount":10800},{"label":"bike repair","amount":2300}]},
   {"account_date":"2026-03-06","opening_bf":925760,"collection":169840,"interest":33000,"fee":3000,"loans_gross_out":183000,"closing_bf":947700,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-03-13","opening_bf":947700,"collection":144940,"interest":111200,"fee":11000,"investor_out":500000,"investor_out_interest":1750,"loans_gross_out":661200,"closing_bf":52740,"expenses":[{"label":"Petrol","amount":500},{"label":"Sadaru","amount":400}]},
   {"account_date":"2026-03-20","opening_bf":52740,"collection":228940,"interest":15200,"fee":1400,"investor_out":210000,"investor_out_interest":0,"loans_gross_out":85200,"closing_bf":100,"expenses":[{"label":"Petrol","amount":580},{"label":"Sadaru","amount":400},{"label":"bike repair","amount":2000}]}
  ]'::json;
BEGIN
  SELECT business_id, owner_person_id INTO v_biz, v_person
    FROM businesses ORDER BY created_at LIMIT 1;
  IF v_biz IS NULL THEN
    RAISE WARNING 'SKIP  no business in this database to test against';
    RETURN;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('person_id', v_person)::text, true);

  v_result := app.import_weekly_account(v_biz, v_weeks);
  PERFORM pg_temp.wk_log('all 12 weeks import (identity and chain both hold)',
                         (v_result ->> 'weeks')::int = 12);
  PERFORM pg_temp.wk_log('final BF is 100, not derived',
                         (v_result ->> 'closing_bf')::numeric = 100);

  SELECT owner_bf_balance, migrated_through_date INTO v_bf, v_through
    FROM businesses WHERE business_id = v_biz;
  PERFORM pg_temp.wk_log('owner BF carries the declared closing', v_bf = 100);
  PERFORM pg_temp.wk_log('migrated span ends on the last account date',
                         v_through = DATE '2026-03-20');

  -- The freeze. Recomputing a migrated day must not move the declared closing.
  PERFORM app.recompute_day_ledger(v_biz, DATE '2026-03-20');
  SELECT closing_balance INTO v_bf FROM day_ledger
   WHERE business_id = v_biz AND business_date = DATE '2026-03-20';
  PERFORM pg_temp.wk_log('recompute leaves a declared day alone', v_bf = 100);

  v_summary := app.migration_profit_summary(v_biz, DATE '2026-03-20');
  PERFORM pg_temp.wk_log('fee comes from the book, 52,900',
                         (v_summary ->> 'fee')::numeric = 52900);
  PERFORM pg_temp.wk_log('expenses total 184,500',
                         (v_summary ->> 'expenses')::numeric = 184500);
  PERFORM pg_temp.wk_log('investor interest 77,332',
                         (v_summary ->> 'investor_interest')::numeric = 77332);
  PERFORM pg_temp.wk_log('withdrawal interest 7,750',
                         (v_summary ->> 'withdrawal_interest')::numeric = 7750);

  -- Profit is only the Owner's 519,418 once the loans carrying 720,600 of
  -- interest are also imported, which the customers sheet does. Assert the
  -- arithmetic on the components so this test stands alone.
  PERFORM pg_temp.wk_log('profit formula reproduces 519,418 from the book figures',
    720600 + (v_summary ->> 'fee')::numeric
           - (v_summary ->> 'expenses')::numeric
           - ((v_summary ->> 'investor_interest')::numeric
              - (v_summary ->> 'withdrawal_interest')::numeric) = 519418);
END;
$test$;

-- A week that does not balance must be refused outright.
DO $test$
DECLARE v_biz uuid; v_person bigint; v_ok boolean := false;
BEGIN
  SELECT business_id, owner_person_id INTO v_biz, v_person FROM businesses ORDER BY created_at LIMIT 1;
  IF v_biz IS NULL THEN RETURN; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('person_id', v_person)::text, true);
  BEGIN
    PERFORM app.import_weekly_account(v_biz,
      '[{"account_date":"2026-04-03","opening_bf":100,"collection":500,"closing_bf":999}]'::json);
  EXCEPTION WHEN OTHERS THEN
    v_ok := true;
  END;
  PERFORM pg_temp.wk_log('a week that does not balance is refused', v_ok);
END;
$test$;

-- A broken opening/closing chain must be refused too.
DO $test$
DECLARE v_biz uuid; v_person bigint; v_ok boolean := false;
BEGIN
  SELECT business_id, owner_person_id INTO v_biz, v_person FROM businesses ORDER BY created_at LIMIT 1;
  IF v_biz IS NULL THEN RETURN; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('person_id', v_person)::text, true);
  BEGIN
    PERFORM app.import_weekly_account(v_biz, '[
      {"account_date":"2026-04-03","opening_bf":0,"collection":100,"closing_bf":100},
      {"account_date":"2026-04-10","opening_bf":999,"collection":0,"closing_bf":999}]'::json);
  EXCEPTION WHEN OTHERS THEN
    v_ok := true;
  END;
  PERFORM pg_temp.wk_log('a broken opening/closing chain is refused', v_ok);
END;
$test$;

-- Interest over a period: whole calendar months, then leftover days at one
-- thirtieth of the monthly rate. Every figure below was read off the Owner's
-- own calculator (JMK Easy Apps) or their profit-share sheet.
DO $test$
BEGIN
  PERFORM pg_temp.wk_log('11 days inside one month = 413',
    app.mana_interest(75000, 1.5, DATE '2026-03-20', DATE '2026-03-31') = 413);
  PERFORM pg_temp.wk_log('2 months 3 days = 2,363, not 2,400 (days/30 is wrong)',
    app.mana_interest(75000, 1.5, DATE '2026-03-20', DATE '2026-05-23') = 2363);
  PERFORM pg_temp.wk_log('4 months 5 days = 15,625',
    app.mana_interest(250000, 1.5, DATE '2026-03-20', DATE '2026-07-25') = 15625);
  PERFORM pg_temp.wk_log('1 month 3 days = 825',
    app.mana_interest(50000, 1.5, DATE '2026-03-20', DATE '2026-04-23') = 825);
  PERFORM pg_temp.wk_log('declared and paid the same day accrues nothing',
    app.mana_interest(50000, 1.5, DATE '2026-03-20', DATE '2026-03-20') = 0);
  PERFORM pg_temp.wk_log('a return date before the given date accrues nothing',
    app.mana_interest(50000, 1.5, DATE '2026-03-20', DATE '2026-03-01') = 0);
END;
$test$;

DO $$
DECLARE v_failed INT;
BEGIN
    SELECT count(*) INTO v_failed FROM wk_results WHERE NOT passed;
    IF v_failed = 0 THEN
        RAISE NOTICE '--- migration_weekly_ledger_tests: ALL PASSED ---';
    ELSE
        RAISE WARNING '--- migration_weekly_ledger_tests: % FAILED ---', v_failed;
    END IF;
END;
$$;

ROLLBACK;

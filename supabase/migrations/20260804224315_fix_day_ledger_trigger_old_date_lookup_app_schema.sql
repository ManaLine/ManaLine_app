-- Pre-existing bug, found by exercising a soft delete end to end.
--
-- app.tg_recompute_day_ledger's backdated-move branch read OLD.<column>
-- inside a SQL CASE EXPRESSION. plpgsql resolves every branch of such an
-- expression against the actual row type, so on `expenses` the unreachable
-- 'loans' branch (OLD.issue_business_date) still had to exist — it does
-- not. Every UPDATE on collections, expenses, cheti_payments,
-- investment_withdrawals and settlement_adjustments failed with 42703, and
-- loans/chetis/investments each lack two of the four columns too.
--
-- The CASE STATEMENT higher up in the same function is unaffected: plpgsql
-- parses a statement's branches lazily, an expression's eagerly.
--
-- Fixed by making the CASE yield a column NAME and reading the value out of
-- to_jsonb(OLD), which needs no compile-time field resolution.
DROP FUNCTION IF EXISTS public.tg_recompute_day_ledger();

CREATE OR REPLACE FUNCTION app.tg_recompute_day_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    r RECORD;
    v_business_id UUID;
    v_date DATE;
BEGIN
    r := COALESCE(NEW, OLD);

    CASE TG_TABLE_NAME
        WHEN 'collections' THEN
            SELECT l.business_id INTO v_business_id
              FROM loans l WHERE l.loan_id = r.loan_id;
            v_date := r.business_date;
        WHEN 'loans' THEN
            v_business_id := r.business_id;
            v_date := r.issue_business_date;
        WHEN 'expenses' THEN
            v_business_id := r.business_id;
            v_date := r.business_date;
        WHEN 'cheti_payments' THEN
            v_business_id := r.business_id;
            v_date := r.business_date;
        WHEN 'chetis' THEN
            v_business_id := r.business_id;
            v_date := r.availed_date;   -- NULL until availed; skipped below
        WHEN 'investments' THEN
            v_business_id := r.business_id;
            v_date := r.effective_date;
        WHEN 'investment_withdrawals' THEN
            SELECT i.business_id INTO v_business_id
              FROM investments i WHERE i.investment_id = r.investment_id;
            v_date := r.business_date;
        WHEN 'settlement_adjustments' THEN
            v_business_id := r.business_id;
            v_date := r.business_date;
    END CASE;

    IF v_business_id IS NOT NULL AND v_date IS NOT NULL THEN
        PERFORM app.recompute_day_ledger_onward(v_business_id, v_date);
    END IF;

    -- An UPDATE that moves a row to a different day leaves the day it came
    -- from wrong unless that one is recomputed too.
    --
    -- The column name comes out of a CASE and the VALUE out of to_jsonb(OLD).
    -- Reading OLD.<column> directly here made plpgsql resolve every branch
    -- against the actual row type, so the unreachable 'loans' branch still
    -- had to exist on `expenses` — it does not, and every UPDATE on five of
    -- these eight tables failed with 42703.
    IF TG_OP = 'UPDATE' AND OLD IS NOT NULL THEN
        DECLARE
            v_old_date DATE;
        BEGIN
            v_old_date := (to_jsonb(OLD) ->> (CASE TG_TABLE_NAME
                WHEN 'loans'       THEN 'issue_business_date'
                WHEN 'chetis'      THEN 'availed_date'
                WHEN 'investments' THEN 'effective_date'
                ELSE 'business_date'
            END))::DATE;
            IF v_old_date IS NOT NULL AND v_old_date IS DISTINCT FROM v_date
               AND v_business_id IS NOT NULL THEN
                PERFORM app.recompute_day_ledger_onward(v_business_id, v_old_date);
            END IF;
        END;
    END IF;

    RETURN NULL;  -- AFTER trigger; return value is ignored
END;
$$;

COMMENT ON FUNCTION app.tg_recompute_day_ledger() IS
  'Recomputes the affected business day (and onward) when any of the eight source tables changes. The old-day lookup reads to_jsonb(OLD) by column name: referencing OLD.<column> in a CASE expression forced every branch to resolve against every table, which no single table satisfies.';

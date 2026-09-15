-- The backdated-move branch read OLD.<column> inside a SQL CASE EXPRESSION.
-- plpgsql resolves every branch of such an expression against the actual row
-- type, so on `expenses` the unreachable `OLD.issue_business_date` branch
-- still had to exist — and does not. Any UPDATE on collections, expenses,
-- cheti_payments, investment_withdrawals or settlement_adjustments therefore
-- failed with 42703, and so did loans/chetis/investments on the branches they
-- lack. The CASE STATEMENT above it is unaffected because plpgsql parses a
-- statement's branches lazily; only this expression was eager.
--
-- Fixed by making the CASE return a column NAME and reading it out of
-- to_jsonb(OLD), which needs no compile-time field resolution.
CREATE OR REPLACE FUNCTION tg_recompute_day_ledger()
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

COMMENT ON FUNCTION tg_recompute_day_ledger() IS
  'Recomputes the affected business day (and onward) when any of the eight source tables changes. The old-day lookup reads to_jsonb(OLD) by column name: referencing OLD.<column> directly in a CASE expression forced every branch to resolve against every table, which no single table satisfies.';

-- day_ledger had no writer. Every figure on the Daily Record Book read
-- whatever the four hand-made rows happened to contain, and a collection or
-- a loan recorded through the app changed none of them.
--
-- WHY RECOMPUTE RATHER THAN INCREMENT: incrementing counters from the client
-- drifts. A failed retry double-counts, a deleted row never un-counts, and two
-- agents settling at once race each other. Recomputing the whole day from the
-- source tables is idempotent -- running it twice is the same as running it
-- once -- so a lost or repeated call cannot corrupt the ledger.
--
-- SECURITY DEFINER because day_ledger is owner-only by RLS, but an AGENT
-- recording a collection must still move the day's totals. The function only
-- ever writes a row it derived itself from the source tables, so it cannot be
-- used to write an arbitrary value.

CREATE OR REPLACE FUNCTION app.recompute_day_ledger(
    p_business_id UUID,
    p_business_date DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $fn$
DECLARE
    v_opening      DECIMAL(14,0);
    v_collections  DECIMAL(14,0);
    v_loans        DECIMAL(14,0);
    v_deposits     DECIMAL(14,0);
    v_withdrawals  DECIMAL(14,0);
    v_expenses     DECIMAL(14,0);
    v_cheti_paid   DECIMAL(14,0);
    v_cheti_recv   DECIMAL(14,0);
    v_short        DECIMAL(14,0);
    v_excess       DECIMAL(14,0);
    v_closing      DECIMAL(14,0);
BEGIN
    -- Opening is the previous ledger day's closing. With no earlier day it
    -- falls back to the business's declared starting cash, which is the same
    -- figure a migrated loan or cheti was entered against.
    SELECT closing_balance INTO v_opening
      FROM day_ledger
     WHERE business_id = p_business_id
       AND business_date < p_business_date
     ORDER BY business_date DESC
     LIMIT 1;

    IF v_opening IS NULL THEN
        SELECT COALESCE(owner_bf_balance, 0) INTO v_opening
          FROM businesses WHERE business_id = p_business_id;
    END IF;
    v_opening := COALESCE(v_opening, 0);

    -- collections carries no business_id of its own; it reaches the business
    -- through the loan it pays down.
    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE l.business_id = p_business_id
       AND c.business_date = p_business_date;

    -- amount_given, not repayment_amount: the ledger tracks CASH, and only
    -- the cash actually handed over left the till. Interest and fee were
    -- withheld from the disbursement and never moved.
    SELECT COALESCE(SUM(amount_given), 0) INTO v_loans
      FROM loans
     WHERE business_id = p_business_id
       AND issue_business_date = p_business_date;

    SELECT COALESCE(SUM(principal_amount), 0) INTO v_deposits
      FROM investments
     WHERE business_id = p_business_id
       AND effective_date = p_business_date;

    SELECT COALESCE(SUM(w.amount), 0) INTO v_withdrawals
      FROM investment_withdrawals w
      JOIN investments i ON i.investment_id = w.investment_id
     WHERE i.business_id = p_business_id
       AND w.business_date = p_business_date;

    SELECT COALESCE(SUM(amount), 0) INTO v_expenses
      FROM expenses
     WHERE business_id = p_business_id
       AND business_date = p_business_date;

    -- net_paid, so an Auction cheti's dividend correctly reduces the cash out.
    SELECT COALESCE(SUM(net_paid), 0) INTO v_cheti_paid
      FROM cheti_payments
     WHERE business_id = p_business_id
       AND business_date = p_business_date;

    -- A cheti availed BEFORE migration is excluded: that cash is already
    -- inside the declared opening balance and counting it again would inflate
    -- BF by the whole lumpsum. Verified against an 85,000 pre-migration
    -- availing, which correctly leaves cheti_received at 0.
    SELECT COALESCE(SUM(availed_amount), 0) INTO v_cheti_recv
      FROM chetis
     WHERE business_id = p_business_id
       AND availed_date = p_business_date
       AND NOT availed_pre_migration;

    SELECT COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Short'), 0),
           COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Excess'), 0)
      INTO v_short, v_excess
      FROM settlement_adjustments
     WHERE business_id = p_business_id
       AND business_date = p_business_date;

    -- Short and excess are deliberately NOT folded in. They describe the gap
    -- between this expected figure and the physically counted cash in
    -- day_closures; folding them back into the expectation would be circular
    -- and would always reconcile to zero.
    v_closing := v_opening
               + v_collections
               - v_loans
               + v_deposits
               - v_withdrawals
               - v_expenses
               - v_cheti_paid
               + v_cheti_recv;

    INSERT INTO day_ledger (
        business_id, business_date, opening_balance, total_collections,
        total_loan_distribution, investor_deposits, investor_withdrawals,
        total_expenses, cheti_paid, cheti_received, short_amount,
        excess_amount, closing_balance
    ) VALUES (
        p_business_id, p_business_date, v_opening, v_collections,
        v_loans, v_deposits, v_withdrawals,
        v_expenses, v_cheti_paid, v_cheti_recv, v_short,
        v_excess, v_closing
    )
    ON CONFLICT (business_id, business_date) DO UPDATE SET
        opening_balance         = EXCLUDED.opening_balance,
        total_collections       = EXCLUDED.total_collections,
        total_loan_distribution = EXCLUDED.total_loan_distribution,
        investor_deposits       = EXCLUDED.investor_deposits,
        investor_withdrawals    = EXCLUDED.investor_withdrawals,
        total_expenses          = EXCLUDED.total_expenses,
        cheti_paid              = EXCLUDED.cheti_paid,
        cheti_received          = EXCLUDED.cheti_received,
        short_amount            = EXCLUDED.short_amount,
        excess_amount           = EXCLUDED.excess_amount,
        closing_balance         = EXCLUDED.closing_balance;
        -- status and remarks are preserved: closing a day and annotating it
        -- are deliberate human acts, and a recompute must not undo them.
END;
$fn$;

-- A backdated entry changes that day's closing, which is the NEXT day's
-- opening, and so on. Without this every later day silently keeps a stale
-- opening balance -- the exact drift the cheti columns were added to prevent.
CREATE OR REPLACE FUNCTION app.recompute_day_ledger_onward(
    p_business_id UUID,
    p_business_date DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $fn$
DECLARE
    v_date DATE;
BEGIN
    PERFORM app.recompute_day_ledger(p_business_id, p_business_date);

    -- Bounded by ledger rows that actually exist, not by a date range.
    FOR v_date IN
        SELECT business_date FROM day_ledger
         WHERE business_id = p_business_id
           AND business_date > p_business_date
         ORDER BY business_date
    LOOP
        PERFORM app.recompute_day_ledger(p_business_id, v_date);
    END LOOP;
END;
$fn$;

-- One trigger body for every source table. TG_TABLE_NAME resolves the two
-- things that differ -- which column holds the business and which holds the
-- date -- so the arithmetic above stays in exactly one place.
CREATE OR REPLACE FUNCTION app.tg_recompute_day_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $fn$
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
            v_old_date := CASE TG_TABLE_NAME
                WHEN 'loans' THEN OLD.issue_business_date
                WHEN 'chetis' THEN OLD.availed_date
                WHEN 'investments' THEN OLD.effective_date
                ELSE OLD.business_date
            END;
            IF v_old_date IS NOT NULL AND v_old_date IS DISTINCT FROM v_date
               AND v_business_id IS NOT NULL THEN
                PERFORM app.recompute_day_ledger_onward(v_business_id, v_old_date);
            END IF;
        END;
    END IF;

    RETURN NULL;  -- AFTER trigger; return value is ignored
END;
$fn$;

CREATE TRIGGER trg_collections_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON collections
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_loans_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON loans
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_expenses_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON expenses
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_cheti_payments_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON cheti_payments
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_chetis_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON chetis
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_investments_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON investments
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_investment_withdrawals_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON investment_withdrawals
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

CREATE TRIGGER trg_settlement_adjustments_day_ledger
    AFTER INSERT OR UPDATE OR DELETE ON settlement_adjustments
    FOR EACH ROW EXECUTE FUNCTION app.tg_recompute_day_ledger();

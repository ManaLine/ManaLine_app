-- A day in the past must not report today's balance as its cash.
--
-- app.recompute_day_ledger summed investments.principal_amount for the day an
-- investment started. That column is the CURRENT balance, so the further the
-- balance drifted from the deposit -- through compounding, through withdrawals
-- -- the more wrong that historical day became, and every closing after it.
--
-- The body below is pg_get_functiondef's own output with ONE SELECT replaced.
-- Rewriting a 126-line money function by hand to change five words is how
-- something nobody was looking at gets changed too.
--
-- CREATE OR REPLACE and not DROP-then-CREATE: the signature is unchanged
-- (uuid, date) and there is exactly one overload, so the rule in CLAUDE.md
-- about parameter lists does not apply here. Verified: 1 overload before.

CREATE OR REPLACE FUNCTION app.recompute_day_ledger(p_business_id uuid, p_business_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_frozen_through DATE;
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
    SELECT migrated_through_date INTO v_frozen_through
      FROM businesses WHERE business_id = p_business_id;

    -- Declared, not derived. The first live day after the span opens on the
    -- last migrated closing, so the chain continues without a seam.
    IF v_frozen_through IS NOT NULL AND p_business_date <= v_frozen_through THEN
        RETURN;
    END IF;

    SELECT closing_balance INTO v_opening
      FROM day_ledger
     WHERE business_id = p_business_id
       AND business_date < p_business_date
     ORDER BY business_date DESC
     LIMIT 1;

    IF v_opening IS NULL THEN
        SELECT COALESCE(opening_bf_declared_amount, 0) INTO v_opening
          FROM businesses WHERE business_id = p_business_id;
    END IF;
    v_opening := COALESCE(v_opening, 0);

    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE l.business_id = p_business_id
       AND c.business_date = p_business_date
       AND c.deleted_at IS NULL
       AND l.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount_given), 0) INTO v_loans
      FROM loans
     WHERE business_id = p_business_id
       AND issue_business_date = p_business_date
       AND deleted_at IS NULL;

    -- original_principal_amount, NOT principal_amount.
    --
    -- principal_amount is the investment's CURRENT balance and it moves:
    -- yearly compounding adds accrued interest to it, and a withdrawal takes
    -- its principal portion out. Summing it here meant the cash a day
    -- recorded as an investor deposit was re-derived from a figure that had
    -- changed since -- so a day in the past reported today's balance as that
    -- day's inflow, and every closing after it inherited the error.
    --
    -- Seen on sri tirumala finance: Rs 5,00,000 deposited on 2025-01-01, and
    -- that day's ledger said Rs 4,62,200 -- which is 500,000 + 91,250 of
    -- compounding - 129,050 of withdrawn principal, i.e. the balance on the
    -- day somebody looked, not the deposit. The history screen showed
    -- "+Rs 5,00,000" beside a closing of Rs 4,62,200 because the two halves
    -- read different columns.
    --
    -- It also DOUBLE COUNTED the withdrawal: once by shrinking principal_amount
    -- and again as v_withdrawals below. And it treated compounding as cash,
    -- which it is not -- interest added to a principal is a liability moving,
    -- not a rupee arriving in the till.
    --
    -- original_principal_amount is NOT NULL and is the amount that actually
    -- came in. Checked before relying on it: 6 investments, 0 null, and 3
    -- already diverged from principal_amount -- three books whose deposit day
    -- was misreported.
    SELECT COALESCE(SUM(original_principal_amount), 0) INTO v_deposits
      FROM investments
     WHERE business_id = p_business_id
       AND effective_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(w.amount), 0) INTO v_withdrawals
      FROM investment_withdrawals w
      JOIN investments i ON i.investment_id = w.investment_id
     WHERE i.business_id = p_business_id
       AND w.business_date = p_business_date
       AND w.deleted_at IS NULL
       AND i.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount), 0) INTO v_expenses
      FROM expenses
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(net_paid), 0) INTO v_cheti_paid
      FROM cheti_payments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(availed_amount), 0) INTO v_cheti_recv
      FROM chetis
     WHERE business_id = p_business_id
       AND availed_date = p_business_date
       AND NOT availed_pre_migration
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Short'), 0),
           COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Excess'), 0)
      INTO v_short, v_excess
      FROM settlement_adjustments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    v_closing := v_opening + v_collections - v_loans + v_deposits
               - v_withdrawals - v_expenses - v_cheti_paid + v_cheti_recv;

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
END;
$function$;

-- ---------------------------------------------------------------------------
-- THE ROWS ALREADY WRITTEN, which the fix above does not reach on its own.
--
-- recompute_day_ledger only runs when something touches one of the eight
-- source tables. Every day already in day_ledger was computed by the old
-- query and keeps its wrong figure until asked again. This asks.
--
-- Rebuilt in DATE ORDER per business, because one day's closing is the next
-- day's opening -- a backdated correction has to cascade forward, which is
-- the whole reason this table is recomputed rather than incremented.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT business_id, business_date
          FROM day_ledger
         ORDER BY business_id, business_date
    LOOP
        PERFORM app.recompute_day_ledger(r.business_id, r.business_date);
    END LOOP;

    -- And the derived cash figure on top of them. recompute_business_bf reads
    -- the LATEST closing, so it has to run after the rebuild above, not
    -- before -- it was correct all along and simply never re-run after the
    -- withdrawal that moved the closing.
    FOR r IN SELECT business_id FROM businesses LOOP
        PERFORM app.recompute_business_bf(r.business_id);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- app.refresh_business_figures -- what a pull-to-refresh calls.
--
-- BF IS DERIVED, NEVER A STORED RUNNING TOTAL (CLAUDE.md). owner_bf_balance is
-- a cache of that derivation, and a cache can go stale: sri tirumala finance
-- showed Rs 4,90,000 for sixteen days after a Rs 2,00,000 withdrawal, because
-- the withdrawal moved the day ledger and nothing re-derived the cash figure
-- on top of it. Every screen that reads BF read a number that was 2,37,800 too
-- high.
--
-- A recompute is idempotent and reads only source rows, so calling it from a
-- gesture is safe: if the figure is already right this changes nothing, and if
-- it has drifted the Owner gets the truth by pulling down. That is the
-- self-healing this design is supposed to have and did not.
--
-- IT DOES NOT REBUILD THE DAY LEDGER, deliberately. That is hundreds of days
-- for an established book and seconds of work, on a gesture somebody makes
-- while standing at a door. The ledger rows are corrected once, by the
-- backfill above, and stay correct because the function that writes them is
-- fixed. If a day ever does drift, it is a bug to find rather than something
-- for a pull-to-refresh to paper over on every swipe.
--
-- Owner-gated: it writes to businesses.
CREATE OR REPLACE FUNCTION app.refresh_business_figures(p_business_id UUID)
RETURNS DECIMAL(14,0)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized - Owner only' USING ERRCODE = '42501';
  END IF;

  PERFORM app.recompute_business_bf(p_business_id);

  RETURN (SELECT owner_bf_balance FROM businesses WHERE business_id = p_business_id);
END;
$function$;

COMMENT ON FUNCTION app.refresh_business_figures(UUID) IS
  'Pull-to-refresh on OW-001. Re-derives owner_bf_balance from the day ledger and what agents hold, and returns it. Idempotent; does NOT rebuild the day ledger.';

GRANT EXECUTE ON FUNCTION app.refresh_business_figures(UUID) TO authenticated;

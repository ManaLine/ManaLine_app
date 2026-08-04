-- =============================================================================
-- SOFT DELETE (1/2) — the columns, the permission, and making deleted rows
-- disappear everywhere without rewriting every read in the app
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   Nothing in this app deletes a record permanently any more. A delete now
--   marks the row: who deleted it, when, and why. The row keeps existing, so
--   a mistake can be undone, and the Recent Deletes list can show it. After
--   30 days it is purged for real (see 2/2).
--
--   THE IMPORTANT PART — a soft-deleted row must stop counting as money.
--   day_ledger is RECOMPUTED from its eight source tables, never
--   incremented, so the recompute has to skip deleted rows or a "deleted"
--   collection would still sit in the day's closing balance. Every one of
--   those eight filters is added below. This does mean a delete rewrites a
--   past day's closing and cascades forward — that is the point of deleting
--   a wrong entry, and it is exactly why the delete is recoverable.
--
--   Making them disappear from SCREENS is done with RESTRICTIVE policies
--   rather than by adding a filter to every query in the app. A restrictive
--   policy is ANDed with the existing permissive ones, so one policy per
--   table hides deleted rows from every existing read — including the
--   v_collection_due view, which is security_invoker — and there is no way
--   for a caller to forget the filter. Recent Deletes therefore cannot use
--   a plain table read; it goes through a SECURITY DEFINER RPC in 2/2.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. The columns. Same three on every soft-deletable table.
--    deleted_by_membership_id is the membership, not the person: it is the
--    same identity every other money row is attributed by, and it scopes to
--    the business the delete happened in.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'collections', 'loans', 'expenses', 'cheti_payments', 'chetis',
    'investments', 'investment_withdrawals', 'settlement_adjustments',
    'cash_transfers', 'customer_remarks', 'customer_documents'
  ] LOOP
    EXECUTE format($f$
      ALTER TABLE %I
        ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL,
        ADD COLUMN IF NOT EXISTS deleted_by_membership_id UUID NULL
            REFERENCES business_members(membership_id),
        ADD COLUMN IF NOT EXISTS delete_reason TEXT NULL
    $f$, t);

    -- Partial index on the live rows: every ordinary read now carries
    -- "deleted_at IS NULL", and that is the hot path.
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_live ON %I (deleted_at) WHERE deleted_at IS NULL',
      t, t);

    -- Purge scan in 2/2 walks deleted rows by age.
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_deleted_at ON %I (deleted_at) WHERE deleted_at IS NOT NULL',
      t, t);

    -- The restrictive policy. ANDed with whatever permissive policies the
    -- table already has, so it cannot be bypassed by a read that forgets.
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_hide_deleted', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I
        AS RESTRICTIVE
        FOR SELECT
        USING (deleted_at IS NULL)
    $f$, t || '_hide_deleted', t);
  END LOOP;
END $$;

COMMENT ON COLUMN collections.deleted_at IS
  'NULL = live. Non-NULL = soft-deleted and invisible to every ordinary read (restrictive RLS policy), excluded from day_ledger, and purged for real 30 days later.';

-- ---------------------------------------------------------------------------
-- 2. The permission. Owner always may; an agent only if the Owner grants it.
--    OFF by default, same BR-236 pattern as can_record_expenses.
-- ---------------------------------------------------------------------------
ALTER TABLE agent_permissions
  ADD COLUMN IF NOT EXISTS can_delete_records BOOLEAN NOT NULL DEFAULT FALSE;

-- ---------------------------------------------------------------------------
-- 3. day_ledger recompute — skip deleted rows.
--
--    Identical to the live version except for the deleted_at filters. A
--    collection is skipped if the collection itself is deleted OR its loan
--    is: deleting a loan must not leave its repayments counting as cash.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_day_ledger(
    p_business_id UUID,
    p_business_date DATE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
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
       AND c.business_date = p_business_date
       AND c.deleted_at IS NULL
       AND l.deleted_at IS NULL;

    -- amount_given, not repayment_amount: the ledger tracks CASH, and only
    -- the cash actually handed over left the till. Interest and fee were
    -- withheld from the disbursement and never moved.
    SELECT COALESCE(SUM(amount_given), 0) INTO v_loans
      FROM loans
     WHERE business_id = p_business_id
       AND issue_business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(principal_amount), 0) INTO v_deposits
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

    -- net_paid, so an Auction cheti's dividend correctly reduces the cash out.
    SELECT COALESCE(SUM(net_paid), 0) INTO v_cheti_paid
      FROM cheti_payments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    -- A cheti availed BEFORE migration is excluded: that cash is already
    -- inside the declared opening balance and counting it again would inflate
    -- BF by the whole lumpsum.
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
$$;

COMMENT ON FUNCTION app.recompute_day_ledger(UUID, DATE) IS
  'Rebuilds one business day from its eight source tables. Skips soft-deleted rows in all eight, so deleting an entry corrects the books; the day''s closing is the next day''s opening, so the correction cascades forward.';

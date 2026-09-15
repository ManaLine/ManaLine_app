DO $outer$
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

    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_live ON %I (deleted_at) WHERE deleted_at IS NULL',
      t, t);

    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS idx_%s_deleted_at ON %I (deleted_at) WHERE deleted_at IS NOT NULL',
      t, t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_hide_deleted', t);
    EXECUTE format($f$
      CREATE POLICY %I ON %I
        AS RESTRICTIVE
        FOR SELECT
        USING (deleted_at IS NULL)
    $f$, t || '_hide_deleted', t);
  END LOOP;
END $outer$;

COMMENT ON COLUMN collections.deleted_at IS
  'NULL = live. Non-NULL = soft-deleted and invisible to every ordinary read (restrictive RLS policy), excluded from day_ledger, and purged for real 30 days later.';

ALTER TABLE agent_permissions
  ADD COLUMN IF NOT EXISTS can_delete_records BOOLEAN NOT NULL DEFAULT FALSE;

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
END;
$$;

COMMENT ON FUNCTION app.recompute_day_ledger(UUID, DATE) IS
  'Rebuilds one business day from its eight source tables. Skips soft-deleted rows in all eight, so deleting an entry corrects the books; the day''s closing is the next day''s opening, so the correction cascades forward.';

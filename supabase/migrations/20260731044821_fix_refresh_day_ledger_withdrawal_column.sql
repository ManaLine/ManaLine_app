-- investment_withdrawals has `amount`, not `approved_amount`. plpgsql does
-- not resolve table columns at CREATE time, so the previous version parsed
-- cleanly and would only have failed the first time a day was refreshed.
CREATE OR REPLACE FUNCTION app.refresh_day_ledger(
  p_business_id uuid,
  p_business_date date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_open DECIMAL(14,0);
  v_coll DECIMAL(14,0);
  v_disb DECIMAL(14,0);
  v_dep  DECIMAL(14,0);
  v_wd   DECIMAL(14,0);
  v_exp  DECIMAL(14,0);
  v_status day_ledger_status_enum;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may refresh the day ledger' USING ERRCODE = '42501';
  END IF;

  SELECT opening_balance, status INTO v_open, v_status
  FROM day_ledger WHERE business_id = p_business_id AND business_date = p_business_date
  FOR UPDATE;
  IF v_open IS NULL THEN
    RETURN;
  END IF;
  IF v_status = 'Closed' THEN
    RAISE EXCEPTION 'This business day is closed. Reopen it before recalculating.'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(SUM(s.amount), 0) INTO v_coll
  FROM collection_payment_splits s
  JOIN collections c ON c.collection_id = s.collection_id
  JOIN loans l ON l.loan_id = c.loan_id
  WHERE l.business_id = p_business_id
    AND c.business_date = p_business_date
    AND s.payment_mode = 'Cash';

  SELECT COALESCE(SUM(l.amount_given), 0) INTO v_disb
  FROM loans l
  WHERE l.business_id = p_business_id
    AND l.issue_business_date = p_business_date
    AND l.loan_status <> 'Cancelled';

  SELECT COALESCE(SUM(i.original_principal_amount), 0) INTO v_dep
  FROM investments i
  WHERE i.business_id = p_business_id AND i.effective_date = p_business_date;

  SELECT COALESCE(SUM(w.amount), 0) INTO v_wd
  FROM investment_withdrawals w
  JOIN investments i ON i.investment_id = w.investment_id
  WHERE i.business_id = p_business_id AND w.business_date = p_business_date;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_exp
  FROM expenses e
  WHERE e.business_id = p_business_id AND e.business_date = p_business_date;

  UPDATE day_ledger SET
    total_collections = v_coll,
    total_loan_distribution = v_disb,
    investor_deposits = v_dep,
    investor_withdrawals = v_wd,
    total_expenses = v_exp,
    closing_balance = v_open + v_coll - v_disb + v_dep - v_wd - v_exp
  WHERE business_id = p_business_id AND business_date = p_business_date;
END;
$function$;

-- Backfill: the 10,00,000 investment already on the books was recorded
-- before investments moved cash, so owner_bf_balance is 0 while the money
-- exists. Bring the pool in line with what has actually been invested,
-- net of withdrawals already taken.
UPDATE businesses b SET owner_bf_balance = b.owner_bf_balance + COALESCE((
  SELECT SUM(i.original_principal_amount)
  FROM investments i WHERE i.business_id = b.business_id AND i.status = 'Active'
), 0) - COALESCE((
  SELECT SUM(w.amount)
  FROM investment_withdrawals w
  JOIN investments i2 ON i2.investment_id = w.investment_id
  WHERE i2.business_id = b.business_id
), 0);

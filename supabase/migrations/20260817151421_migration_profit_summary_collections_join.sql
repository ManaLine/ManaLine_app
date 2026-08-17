-- collections has no business_id of its own - it reaches the business through
-- its loan. The original SELECT applied cleanly because plpgsql bodies are not
-- type-checked at CREATE time; it failed on first call.
CREATE OR REPLACE FUNCTION app.migration_profit_summary(
  p_business_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_interest numeric := 0;
  v_fee numeric := 0;
  v_expenses numeric := 0;
  v_inv_interest numeric := 0;
  v_wd_interest numeric := 0;
  v_line_balance numeric := 0;
  v_collections numeric := 0;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(l.interest_amount), 0), COALESCE(SUM(l.processing_fee), 0),
         COALESCE(SUM(CASE WHEN l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')
                           THEN l.remaining_balance ELSE 0 END), 0)
    INTO v_interest, v_fee, v_line_balance
    FROM loans l
   WHERE l.business_id = p_business_id AND l.deleted_at IS NULL
     AND l.issue_business_date <= p_as_of;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
    FROM expenses e
   WHERE e.business_id = p_business_id AND e.deleted_at IS NULL AND e.business_date <= p_as_of;

  SELECT COALESCE(SUM(il.amount), 0) INTO v_inv_interest
    FROM investment_interest_ledger il
    JOIN investments i ON i.investment_id = il.investment_id
   WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
     AND il.entry_type = 'Payment' AND il.business_date <= p_as_of;

  SELECT COALESCE(SUM(w.interest_portion), 0) INTO v_wd_interest
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
   WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
     AND w.deleted_at IS NULL AND w.business_date <= p_as_of;

  SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
    FROM collections c
    JOIN loans l ON l.loan_id = c.loan_id
   WHERE l.business_id = p_business_id AND c.deleted_at IS NULL AND c.business_date <= p_as_of;

  RETURN json_build_object(
    'as_of', p_as_of,
    'interest', v_interest,
    'fee', v_fee,
    'expenses', v_expenses,
    'investor_interest', v_inv_interest,
    'withdrawal_interest', v_wd_interest,
    'profit', v_interest + v_fee - v_expenses - (v_inv_interest - v_wd_interest),
    'line_balance', v_line_balance,
    'collections', v_collections
  );
END;
$$;

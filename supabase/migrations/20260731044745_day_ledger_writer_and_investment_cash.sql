-- Two confirmed decisions, 2026-07-31.
--
-- (1) INVESTMENT MOVES CASH. Recording an investment credits the business
--     cash pool; deleting or reducing one debits it. Per GLOBAL BR-022
--     (single business cash pool) and day_ledger's own investor_deposits /
--     investor_withdrawals columns, the investor's money genuinely IS
--     business cash. Until now an investment created a row and touched no
--     balance anywhere, so BF read zero with 10 lakh on the books.
--     Done as RPCs so the investment write and the cash write cannot drift
--     apart.
--
-- (2) day_ledger GETS A WRITER. Nothing in the app had ever inserted a
--     row, which is why BF, OW-011 Day Closure and the Daily Record Book
--     were three dead screens sharing one missing writer.
--
--     Totals are RECOMPUTED from the source tables rather than incremented
--     at each write site. Incremental counters spread across every
--     collection, loan and expense path drift the moment one path is
--     missed or a row is corrected — and this schema explicitly allows
--     corrections. Recompute is idempotent and self-healing.
--
-- NOTE: refresh_day_ledger is superseded later in this same batch by
-- 20260731044821, which corrects investment_withdrawals.approved_amount to
-- its real name, `amount`. plpgsql does not resolve column references at
-- CREATE time, so the version below parses but fails on first execution.
-- Kept as-is rather than rewritten, so the migration history matches what
-- was actually applied.

-- --------------------------------------------------------------------
-- 1. Open a business day. Carries yesterday's closing into today.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.open_business_day(
  p_business_id uuid,
  p_business_date date DEFAULT CURRENT_DATE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_id UUID;
  v_prev_closing DECIMAL(14,0);
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may open a business day' USING ERRCODE = '42501';
  END IF;

  SELECT ledger_id INTO v_id FROM day_ledger
  WHERE business_id = p_business_id AND business_date = p_business_date;
  IF v_id IS NOT NULL THEN
    RETURN v_id;   -- idempotent
  END IF;

  -- Yesterday's closing becomes today's opening. With no prior day at
  -- all, fall back to the Owner's standing cash pool so the first day of
  -- a migrated business does not start from a false zero.
  SELECT closing_balance INTO v_prev_closing
  FROM day_ledger
  WHERE business_id = p_business_id AND business_date < p_business_date
  ORDER BY business_date DESC LIMIT 1;

  IF v_prev_closing IS NULL THEN
    SELECT owner_bf_balance INTO v_prev_closing FROM businesses WHERE business_id = p_business_id;
  END IF;

  INSERT INTO day_ledger (
    business_id, business_date, opening_balance, total_collections,
    total_loan_distribution, investor_deposits, investor_withdrawals,
    total_expenses, short_amount, excess_amount, closing_balance, status
  ) VALUES (
    p_business_id, p_business_date, COALESCE(v_prev_closing, 0), 0,
    0, 0, 0, 0, 0, 0, COALESCE(v_prev_closing, 0), 'Open'
  ) RETURNING ledger_id INTO v_id;

  RETURN v_id;
END;
$function$;

-- --------------------------------------------------------------------
-- 2. Recompute a day's totals from source. Idempotent, self-healing.
--    (Corrected in 20260731044821 — see note at the top of this file.)
-- --------------------------------------------------------------------
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
    RETURN;   -- day not open; nothing to refresh
  END IF;
  IF v_status = 'Closed' THEN
    -- A closed day is immutable (GLOBAL BR-222 — reopening is a separate
    -- Owner action). Refusing silently would hide a real edit attempt.
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

  SELECT COALESCE(SUM(w.approved_amount), 0) INTO v_wd
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

-- --------------------------------------------------------------------
-- 3. Investment writes, now atomic with the cash pool.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_investment(
  p_investor_id uuid,
  p_amount numeric,
  p_roi_rate numeric,
  p_interest_type investment_interest_type_enum,
  p_effective_date date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_investment_id UUID;
  v_amount DECIMAL(14,0) := CEIL(p_amount);
BEGIN
  SELECT bm.business_id INTO v_business_id
  FROM investors i JOIN business_members bm ON bm.membership_id = i.membership_id
  WHERE i.investor_id = p_investor_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Investor not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may record an investment' USING ERRCODE = '42501';
  END IF;
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'Investment amount must be greater than zero' USING ERRCODE = '23514';
  END IF;

  INSERT INTO investments (
    investor_id, business_id, principal_amount, original_principal_amount,
    roi_rate, interest_type, effective_date, status
  ) VALUES (
    p_investor_id, v_business_id, v_amount, v_amount,
    p_roi_rate, p_interest_type, p_effective_date, 'Active'
  ) RETURNING investment_id INTO v_investment_id;

  -- The money is now business cash (BR-022).
  UPDATE businesses SET owner_bf_balance = owner_bf_balance + v_amount
  WHERE business_id = v_business_id;

  PERFORM app.refresh_day_ledger(v_business_id, p_effective_date);

  RETURN v_investment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.edit_investment(
  p_investment_id uuid,
  p_amount numeric,
  p_roi_rate numeric,
  p_interest_type investment_interest_type_enum,
  p_effective_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_inv RECORD;
  v_amount DECIMAL(14,0) := CEIL(p_amount);
  v_delta DECIMAL(14,0);
BEGIN
  SELECT * INTO v_inv FROM investments WHERE investment_id = p_investment_id FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may edit an investment' USING ERRCODE = '42501';
  END IF;

  -- Cash moves by the difference against the ORIGINAL amount, which is
  -- what was credited at record time. principal_amount may have grown
  -- through compounding, and that growth was never cash.
  v_delta := v_amount - v_inv.original_principal_amount;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, old_value, new_value, business_date
  ) VALUES (
    v_inv.business_id, app.current_person_id(), 'Other Admin Event', 'investment', 0,
    p_investment_id,
    json_build_object('principal_amount', v_inv.principal_amount,
                      'original_principal_amount', v_inv.original_principal_amount,
                      'roi_rate', v_inv.roi_rate, 'interest_type', v_inv.interest_type,
                      'effective_date', v_inv.effective_date),
    json_build_object('principal_amount', v_amount,
                      'original_principal_amount', v_amount,
                      'roi_rate', p_roi_rate, 'interest_type', p_interest_type,
                      'effective_date', p_effective_date),
    CURRENT_DATE
  );

  -- Derived compounding is invalidated by a changed amount or date.
  DELETE FROM investment_interest_ledger
  WHERE investment_id = p_investment_id AND entry_type = 'Compounding Event';

  UPDATE investments SET
    principal_amount = v_amount,
    original_principal_amount = v_amount,
    roi_rate = p_roi_rate,
    interest_type = p_interest_type,
    effective_date = p_effective_date,
    last_compounding_date = NULL
  WHERE investment_id = p_investment_id;

  IF v_delta <> 0 THEN
    UPDATE businesses SET owner_bf_balance = owner_bf_balance + v_delta
    WHERE business_id = v_inv.business_id;
  END IF;

  PERFORM app.refresh_day_ledger(v_inv.business_id, p_effective_date);
END;
$function$;

CREATE OR REPLACE FUNCTION app.delete_investment(p_investment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_inv RECORD;
BEGIN
  SELECT * INTO v_inv FROM investments WHERE investment_id = p_investment_id FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may delete an investment' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (SELECT 1 FROM investment_interest_ledger
             WHERE investment_id = p_investment_id AND entry_type = 'Payment') THEN
    RAISE EXCEPTION 'This investment has interest payments recorded against it and cannot be deleted. Correct it with Edit instead.'
      USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM investment_withdrawals WHERE investment_id = p_investment_id) THEN
    RAISE EXCEPTION 'This investment has withdrawals against it and cannot be deleted. Correct it with Edit instead.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, old_value, business_date
  ) VALUES (
    v_inv.business_id, app.current_person_id(), 'Other Admin Event', 'investment_deleted', 0,
    p_investment_id,
    json_build_object('principal_amount', v_inv.principal_amount,
                      'original_principal_amount', v_inv.original_principal_amount,
                      'roi_rate', v_inv.roi_rate, 'interest_type', v_inv.interest_type,
                      'effective_date', v_inv.effective_date),
    CURRENT_DATE
  );

  DELETE FROM investment_interest_ledger WHERE investment_id = p_investment_id;
  DELETE FROM investments WHERE investment_id = p_investment_id;

  UPDATE businesses SET owner_bf_balance = owner_bf_balance - v_inv.original_principal_amount
  WHERE business_id = v_inv.business_id;

  PERFORM app.refresh_day_ledger(v_inv.business_id, v_inv.effective_date);
END;
$function$;

GRANT EXECUTE ON FUNCTION app.open_business_day(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.refresh_day_ledger(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.record_investment(uuid, numeric, numeric, investment_interest_type_enum, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.edit_investment(uuid, numeric, numeric, investment_interest_type_enum, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.delete_investment(uuid) TO authenticated;

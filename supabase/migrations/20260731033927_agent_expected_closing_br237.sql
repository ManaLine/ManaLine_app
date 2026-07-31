-- CALC BR-237 — Expected Closing Balance, server-side, per agent.
--
-- TWO problems this fixes.
--
-- (1) submit_agent_settlement took `p_expected_closing_balance` as a
--     CLIENT-SUPPLIED parameter and computed difference from it. The Zero
--     Difference Policy (GLOBAL BR-219) — the rule that blocks day closure
--     unless difference is exactly 0 — was therefore being enforced
--     against a number the client made up. A wrong or tampered client
--     value produced a difference of 0 and a clean settlement. For an app
--     whose entire purpose is that every rupee is accounted for, the
--     expected balance has to be computed by the server.
--
-- (2) BR-173 cash transfers between agents were in NO formula anywhere.
--     An agent who handed cash to another agent read as SHORT by exactly
--     that amount, and the receiving agent read as EXCESS.
--
-- TWO deliberate interpretations, flagged rather than buried:
--
--   * BR-237 says "+ Total Collections (all payment modes)" but compares
--     the result against "Physical Closing Balance (actual counted cash)".
--     Those cannot both be right — you cannot count a UPI payment in your
--     hand. This computes CASH ONLY. Non-cash modes are settled through
--     their own columns on account_settlements.
--   * Only transfers where BOTH agents have confirmed are counted
--     (BR-173 records both confirmations). An unconfirmed transfer would
--     otherwise be a one-tap way to make a short disappear.
CREATE OR REPLACE FUNCTION app.agent_expected_closing(
  p_agent_id uuid,
  p_business_date date
)
RETURNS TABLE(
  opening_bf numeric,
  cash_collected numeric,
  upi_collected numeric,
  bank_collected numeric,
  cheque_collected numeric,
  loans_disbursed numeric,
  expenses numeric,
  transfers_in numeric,
  transfers_out numeric,
  expected_cash_closing numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_membership_id UUID;
  v_business_id UUID;
  v_open  DECIMAL(14,0) := 0;
  v_cash  DECIMAL(14,0) := 0;
  v_upi   DECIMAL(14,0) := 0;
  v_bank  DECIMAL(14,0) := 0;
  v_chq   DECIMAL(14,0) := 0;
  v_disb  DECIMAL(14,0) := 0;
  v_exp   DECIMAL(14,0) := 0;
  v_in    DECIMAL(14,0) := 0;
  v_out   DECIMAL(14,0) := 0;
BEGIN
  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT bm.business_id INTO v_business_id
  FROM business_members bm WHERE bm.membership_id = v_membership_id;

  -- The agent themselves, or the Owner of their business.
  IF NOT (app.is_owner(v_business_id)
          OR EXISTS (SELECT 1 FROM agents a
                     WHERE a.agent_id = p_agent_id AND a.person_id = app.current_person_id())) THEN
    RAISE EXCEPTION 'Not authorized for this agent' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(b.opening_bf, 0) INTO v_open
  FROM agent_bf_assignments b
  WHERE b.membership_id = v_membership_id
    AND (b.business_date IS NULL OR b.business_date <= p_business_date)
  ORDER BY COALESCE(b.business_date::TIMESTAMP, b.created_at) DESC
  LIMIT 1;
  v_open := COALESCE(v_open, 0);

  SELECT
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cash' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'UPI' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Bank Transfer' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cheque' THEN s.amount END), 0)
  INTO v_cash, v_upi, v_bank, v_chq
  FROM collection_payment_splits s
  JOIN collections c ON c.collection_id = s.collection_id
  WHERE c.collected_by_membership_id = v_membership_id
    AND c.business_date = p_business_date;

  SELECT COALESCE(SUM(l.amount_given), 0) INTO v_disb
  FROM loans l
  WHERE l.collection_agent_membership_id = v_membership_id
    AND l.issue_business_date = p_business_date
    AND l.loan_status <> 'Cancelled';

  SELECT COALESCE(SUM(e.amount), 0) INTO v_exp
  FROM expenses e
  WHERE e.recorded_by_membership_id = v_membership_id
    AND e.business_date = p_business_date;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_in
  FROM cash_transfers t
  WHERE t.to_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_out
  FROM cash_transfers t
  WHERE t.from_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL;

  RETURN QUERY SELECT
    v_open, v_cash, v_upi, v_bank, v_chq, v_disb, v_exp, v_in, v_out,
    v_open + v_cash - v_disb - v_exp + v_in - v_out;
END;
$function$;

COMMENT ON FUNCTION app.agent_expected_closing(uuid, date) IS
  'CALC BR-237 per-agent expected CASH closing, including BR-173 confirmed cash transfers. Server-side source of truth for the Zero Difference Policy.';

GRANT EXECUTE ON FUNCTION app.agent_expected_closing(uuid, date) TO authenticated;

-- Settlement now computes the expected balance itself. The parameter is
-- kept so the existing client signature still binds, but it is treated as
-- the client's CLAIM and rejected if it disagrees with the server, rather
-- than being trusted. That turns a silent wrong-number bug into a loud
-- mismatch the Owner can see.
CREATE OR REPLACE FUNCTION app.submit_agent_settlement(
  p_account_period_id uuid, p_agent_id uuid, p_cycle_type settlement_cycle_type_enum,
  p_opening_balance numeric, p_cash_collected numeric, p_upi_collected numeric,
  p_bank_collected numeric, p_cheque_collected numeric, p_loan_distribution numeric,
  p_expenses numeric, p_expected_closing_balance numeric, p_physical_cash_declared numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_settlement_id UUID;
  v_difference DECIMAL(14,0);
  v_membership_id UUID;
  v_business_id UUID;
  v_transfer_amount DECIMAL(14,0);
  v_expected DECIMAL(14,0);
  v_calc RECORD;
  v_business_date DATE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM agents WHERE agent_id = p_agent_id AND person_id = app.current_person_id()) THEN
    RAISE EXCEPTION 'Not authorized - not your own agent record' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(ap.actual_end_date::date, CURRENT_DATE) INTO v_business_date
  FROM account_periods ap WHERE ap.account_period_id = p_account_period_id;
  v_business_date := COALESCE(v_business_date, CURRENT_DATE);

  SELECT * INTO v_calc FROM app.agent_expected_closing(p_agent_id, v_business_date);
  v_expected := v_calc.expected_cash_closing;

  IF p_expected_closing_balance IS NOT NULL
     AND p_expected_closing_balance <> v_expected THEN
    RAISE EXCEPTION
      'Expected closing balance mismatch: this device calculated %, the server calculates %. Refresh and resubmit.',
      p_expected_closing_balance, v_expected
      USING ERRCODE = '23514';
  END IF;

  v_difference := p_physical_cash_declared - v_expected;

  INSERT INTO account_settlements (
    account_period_id, agent_id, cycle_type, opening_balance, cash_collected, upi_collected,
    bank_collected, cheque_collected, loan_distribution, expenses, expected_closing_balance,
    physical_cash_declared, difference, status
  ) VALUES (
    p_account_period_id, p_agent_id, p_cycle_type, v_calc.opening_bf, v_calc.cash_collected,
    v_calc.upi_collected, v_calc.bank_collected, v_calc.cheque_collected, v_calc.loans_disbursed,
    v_calc.expenses, v_expected, p_physical_cash_declared, v_difference, 'Pending Owner Review'
  ) RETURNING settlement_id INTO v_settlement_id;

  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  SELECT bm.business_id INTO v_business_id FROM business_members bm WHERE bm.membership_id = v_membership_id;

  SELECT agent_bf_current INTO v_transfer_amount
  FROM agent_bf_assignments
  WHERE membership_id = v_membership_id
  ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
  LIMIT 1
  FOR UPDATE;

  IF v_transfer_amount IS NOT NULL AND v_transfer_amount <> 0 THEN
    UPDATE agent_bf_assignments
    SET agent_bf_current = 0, updated_at = now()
    WHERE assignment_id = (
      SELECT assignment_id FROM agent_bf_assignments
      WHERE membership_id = v_membership_id
      ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
      LIMIT 1
    );

    UPDATE businesses
    SET owner_bf_balance = owner_bf_balance + v_transfer_amount
    WHERE business_id = v_business_id;
  END IF;

  RETURN v_settlement_id;
END;
$function$;

-- =============================================================================
-- BATCH A (6/6) — settlement: the money is worked out by the server, not
-- the phone; a returned settlement reverses the hand-over
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   1. submit_agent_settlement: the expected figures (opening, collected
--      cash/UPI/bank/cheque, loans handed out, expenses, transfers) are now
--      COMPUTED BY THE SERVER from the account period's own records — the
--      agent only declares the physical cash they actually counted. Until
--      now the phone sent the "expected" number itself, so a wrong or
--      edited figure produced a clean settlement no matter the truth.
--      The agent's whole BF still returns to the Owner at submit (exactly
--      once), and an agent cannot submit the same period twice.
--   2. return_settlement: when the Owner sends a settlement back, the money
--      that moved to the Owner moves back to the agent, so the agent can
--      correct and re-submit. (The reversal amount is stored on the
--      settlement row itself — nothing is guessed.)
-- -----------------------------------------------------------------------------

-- The settlement row now remembers how much actually moved to the Owner at
-- submit, so a Return can reverse exactly that amount.
ALTER TABLE account_settlements
  ADD COLUMN agent_bf_handed_over DECIMAL(14,0) NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 1. submit_agent_settlement — rebuilt (param list changed, so the old
--    function is dropped first).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL);

CREATE OR REPLACE FUNCTION app.submit_agent_settlement(
  p_account_period_id UUID,
  p_agent_id UUID,
  p_cycle_type settlement_cycle_type_enum,
  p_physical_cash_declared DECIMAL(14,0)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_period_business UUID;
  v_period_membership UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_period_status account_period_status_enum;
  v_membership_id UUID;
  v_settlement_id UUID;
  v_opening DECIMAL(14,0) := 0;
  v_cash DECIMAL(14,0) := 0;
  v_upi DECIMAL(14,0) := 0;
  v_bank DECIMAL(14,0) := 0;
  v_cheque DECIMAL(14,0) := 0;
  v_loans DECIMAL(14,0) := 0;
  v_expenses DECIMAL(14,0) := 0;
  v_transfers_in DECIMAL(14,0) := 0;
  v_transfers_out DECIMAL(14,0) := 0;
  v_expected_cash DECIMAL(14,0);
  v_difference DECIMAL(14,0);
  v_handed DECIMAL(14,0);
  v_assignment_id UUID;
BEGIN
  -- Only the agent themselves may submit their own settlement.
  IF NOT EXISTS (SELECT 1 FROM agents WHERE agent_id = p_agent_id AND person_id = app.current_person_id()) THEN
    RAISE EXCEPTION 'Not authorized — not your own agent record' USING ERRCODE = '42501';
  END IF;

  -- Lock the period so two taps cannot both submit.
  SELECT business_id, agent_membership_id,
         business_start_date::date, COALESCE(planned_business_end_date::date, business_start_date::date),
         status
    INTO v_period_business, v_period_membership, v_period_start, v_period_end, v_period_status
  FROM account_periods
  WHERE account_period_id = p_account_period_id
  FOR UPDATE;
  IF v_period_business IS NULL THEN
    RAISE EXCEPTION 'Account period not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_period_status <> 'Running' THEN
    RAISE EXCEPTION 'This account period is not running' USING ERRCODE = '23514';
  END IF;

  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  IF v_membership_id <> v_period_membership THEN
    RAISE EXCEPTION 'This account period does not belong to this agent' USING ERRCODE = '42501';
  END IF;

  -- No double submission: a second submit is refused while a Pending or
  -- Approved settlement exists. (A RETURNED one is fine — that is the
  -- correction-and-resubmit path.)
  IF EXISTS (
    SELECT 1 FROM account_settlements
    WHERE account_period_id = p_account_period_id AND status <> 'Returned'
  ) THEN
    RAISE EXCEPTION 'A settlement for this period has already been submitted' USING ERRCODE = '23514';
  END IF;

  IF p_physical_cash_declared < 0 THEN
    RAISE EXCEPTION 'Physical cash declared cannot be negative' USING ERRCODE = '23514';
  END IF;

  -- ---- The server works the figures out from the period's own records ----
  -- Opening cash: the agent's starting BF for this period.
  SELECT opening_bf INTO v_opening
  FROM agent_bf_assignments
  WHERE membership_id = v_membership_id AND business_date <= v_period_start
  ORDER BY business_date DESC NULLS LAST
  LIMIT 1;

  -- Collections by mode (the splits say how the money came in).
  SELECT COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cash'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'UPI'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Bank Transfer'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cheque'), 0)
    INTO v_cash, v_upi, v_bank, v_cheque
  FROM collections c
  JOIN collection_payment_splits s ON s.collection_id = c.collection_id
  WHERE c.collected_by_membership_id = v_membership_id
    AND c.business_date BETWEEN v_period_start AND v_period_end;

  -- Loans the agent handed out.
  SELECT COALESCE(SUM(l.amount_given), 0) INTO v_loans
  FROM loans l
  WHERE l.collection_agent_membership_id = v_membership_id
    AND l.issue_business_date BETWEEN v_period_start AND v_period_end;

  -- Expenses the agent recorded.
  SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
  FROM expenses e
  WHERE e.recorded_by_membership_id = v_membership_id
    AND e.business_date BETWEEN v_period_start AND v_period_end;

  -- Confirmed transfers only (an unconfirmed transfer must not make a
  -- short disappear).
  SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.to_agent_id = p_agent_id), 0),
         COALESCE(SUM(t.amount) FILTER (WHERE t.from_agent_id = p_agent_id), 0)
    INTO v_transfers_in, v_transfers_out
  FROM cash_transfers t
  WHERE (t.from_agent_id = p_agent_id OR t.to_agent_id = p_agent_id)
    AND t.from_agent_confirmed_at IS NOT NULL AND t.to_agent_confirmed_at IS NOT NULL
    AND t.business_date BETWEEN v_period_start AND v_period_end;

  -- BR-237 expected CASH closing (cash only — you cannot count a UPI
  -- payment in your hand). Short/excess is declared cash vs this.
  v_expected_cash := v_opening + v_cash - v_loans - v_expenses + v_transfers_in - v_transfers_out;
  v_difference := p_physical_cash_declared - v_expected_cash;

  -- ---- The whole BF returns to the Owner (the hand-over) ----------------
  SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_handed
  FROM agent_bf_assignments
  WHERE membership_id = v_membership_id
  ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
  LIMIT 1
  FOR UPDATE;

  IF v_handed IS NOT NULL AND v_handed <> 0 THEN
    UPDATE agent_bf_assignments
    SET agent_bf_current = 0, updated_at = now()
    WHERE assignment_id = v_assignment_id;

    UPDATE businesses
    SET owner_bf_balance = owner_bf_balance + v_handed
    WHERE business_id = v_period_business;
  END IF;

  INSERT INTO account_settlements (
    account_period_id, agent_id, cycle_type, opening_balance, cash_collected, upi_collected,
    bank_collected, cheque_collected, loan_distribution, expenses, expected_closing_balance,
    physical_cash_declared, difference, agent_bf_handed_over, status
  ) VALUES (
    p_account_period_id, p_agent_id, p_cycle_type, v_opening, v_cash, v_upi,
    v_bank, v_cheque, v_loans, v_expenses, v_expected_cash,
    p_physical_cash_declared, v_difference, COALESCE(v_handed, 0), 'Pending Owner Review'
  ) RETURNING settlement_id INTO v_settlement_id;

  RETURN json_build_object(
    'settlement_id', v_settlement_id,
    'expected_closing_balance', v_expected_cash,
    'difference', v_difference,
    'agent_bf_handed_over', COALESCE(v_handed, 0)
  );
END;
$$;

COMMENT ON FUNCTION app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL) IS
  'AG-006. The agent only declares the physical cash they counted; every other figure is computed by the server from the period''s records. The agent''s whole BF returns to the Owner exactly once; a period cannot be submitted twice.';

GRANT EXECUTE ON FUNCTION app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. return_settlement — Owner sends it back; the hand-over reverses.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.return_settlement(p_settlement_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_status settlement_status_enum;
  v_handed DECIMAL(14,0);
  v_agent_id UUID;
  v_membership_id UUID;
  v_assignment_id UUID;
BEGIN
  SELECT ap.business_id, s.status, s.agent_bf_handed_over, s.agent_id
    INTO v_business_id, v_status, v_handed, v_agent_id
  FROM account_settlements s
  JOIN account_periods ap ON ap.account_period_id = s.account_period_id
  WHERE s.settlement_id = p_settlement_id
  FOR UPDATE;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Settlement not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may return a settlement' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'Pending Owner Review' THEN
    RAISE EXCEPTION 'Only a pending settlement can be returned' USING ERRCODE = '23514';
  END IF;

  -- The reversal goes back to the agent's BF, so they can correct and
  -- re-submit. Resolve the agent's membership (agent_bf_assignments keys on
  -- membership_id, not agent_id).
  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = v_agent_id;

  -- Put the money back into the agent's float (their current row).
  IF v_handed > 0 THEN
    UPDATE businesses SET owner_bf_balance = owner_bf_balance - v_handed
    WHERE business_id = v_business_id;

    SELECT assignment_id INTO v_assignment_id
    FROM agent_bf_assignments
    WHERE membership_id = v_membership_id
    ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
    LIMIT 1
    FOR UPDATE;
    IF v_assignment_id IS NOT NULL THEN
      UPDATE agent_bf_assignments
      SET agent_bf_current = agent_bf_current + v_handed, updated_at = now()
      WHERE assignment_id = v_assignment_id;
    END IF;
  END IF;

  UPDATE account_settlements
  SET status = 'Returned',
      return_reason = COALESCE(p_reason, 'Returned by Owner'),
      reviewed_by_person_id = app.current_person_id(),
      reviewed_at = now()
  WHERE settlement_id = p_settlement_id;
END;
$$;

COMMENT ON FUNCTION app.return_settlement(UUID, TEXT) IS
  'OW-013. Owner sends a pending settlement back: the hand-over reverses (Owner BF back down, agent float back up) so the agent can correct and re-submit. Approve stays a pure status change.';

GRANT EXECUTE ON FUNCTION app.return_settlement(UUID, TEXT) TO authenticated;

-- Submitting a settlement failed outright, and would have been wrong if it
-- had worked.
--
-- It failed because v_opening is read with SELECT INTO from a row that does
-- not exist -- the agent's assignment is dated after the period start, so the
-- WHERE matched nothing and INTO set the variable to NULL, overwriting its
-- := 0 initialiser. opening_balance is NOT NULL, so every submit ended in a
-- constraint violation. On the handset: "Submit settlement — not working".
--
-- It would have been wrong because it moved the money at SUBMIT: the old body
-- zeroed agent_bf_current and credited owner_bf_balance, then wrote the row as
-- "Pending Owner Review". A settlement pending review that has already handed
-- the cash over is not pending anything, and the Owner approving it was
-- approving something that had already happened.
--
-- And its date window used planned_business_end_date, so an agent who worked
-- seven days against a four-day plan had every collection after day four
-- counted as zero -- the same forecast-as-boundary mistake
-- app.account_period_window was written to end.
--
-- What the Owner asked for: one figure -- everything the agent is holding --
-- and a submit that notifies rather than transfers. So:
--
--   submit  records what is held and asks. No money moves.
--   approve moves it, and closes the period.
--
-- physical_cash_declared is no longer asked for. The column stays (it is NOT
-- NULL and the history needs a value) and carries the same figure as the
-- amount held: the app knows what the agent has, so there is nothing for them
-- to count and nothing to disagree with. difference is 0 by construction
-- rather than by luck.
DROP FUNCTION IF EXISTS app.submit_agent_settlement(
  uuid, uuid, settlement_cycle_type_enum, numeric);

CREATE OR REPLACE FUNCTION app.submit_agent_settlement(
  p_account_period_id UUID,
  p_agent_id UUID,
  p_cycle_type settlement_cycle_type_enum
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_period_business UUID;
  v_period_membership UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_period_status account_period_status_enum;
  v_membership_id UUID;
  v_settlement_id UUID;
  v_opening DECIMAL(14,0);
  v_cash DECIMAL(14,0) := 0;
  v_upi DECIMAL(14,0) := 0;
  v_bank DECIMAL(14,0) := 0;
  v_cheque DECIMAL(14,0) := 0;
  v_loans DECIMAL(14,0) := 0;
  v_expenses DECIMAL(14,0) := 0;
  v_held DECIMAL(14,0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM agents WHERE agent_id = p_agent_id AND person_id = app.current_person_id()) THEN
    RAISE EXCEPTION 'Not authorized — not your own agent record' USING ERRCODE = '42501';
  END IF;

  SELECT business_id, agent_membership_id, business_start_date::date, status
    INTO v_period_business, v_period_membership, v_period_start, v_period_status
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

  IF EXISTS (
    SELECT 1 FROM account_settlements
    WHERE account_period_id = p_account_period_id AND status <> 'Returned'
  ) THEN
    RAISE EXCEPTION 'A settlement for this period has already been submitted' USING ERRCODE = '23514';
  END IF;

  -- A Running period runs to today, whatever it was planned to do.
  v_period_end := GREATEST(CURRENT_DATE, v_period_start);

  -- COALESCE around the SELECT, not on the variable: INTO writes NULL when
  -- nothing matches, which is what broke this.
  SELECT COALESCE(
    (SELECT opening_bf FROM agent_bf_assignments
      WHERE membership_id = v_membership_id
      ORDER BY business_date DESC NULLS LAST, created_at DESC
      LIMIT 1), 0) INTO v_opening;

  SELECT COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cash'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'UPI'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Bank Transfer'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cheque'), 0)
    INTO v_cash, v_upi, v_bank, v_cheque
  FROM collections c
  JOIN collection_payment_splits s ON s.collection_id = c.collection_id
  WHERE c.collected_by_membership_id = v_membership_id
    AND c.deleted_at IS NULL
    AND c.business_date BETWEEN v_period_start AND v_period_end;

  SELECT COALESCE(SUM(l.amount_given), 0) INTO v_loans
  FROM loans l
  WHERE l.collection_agent_membership_id = v_membership_id
    AND l.deleted_at IS NULL
    AND l.issue_business_date BETWEEN v_period_start AND v_period_end;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
  FROM expenses e
  WHERE e.recorded_by_membership_id = v_membership_id
    AND e.deleted_at IS NULL
    AND e.business_date BETWEEN v_period_start AND v_period_end;

  -- The one figure the screen shows: everything this agent is holding, in
  -- whatever form it arrived. Derived, not declared.
  SELECT COALESCE(agent_bf_current, 0) INTO v_held
  FROM agent_bf_assignments
  WHERE membership_id = v_membership_id
  ORDER BY business_date DESC NULLS LAST, created_at DESC
  LIMIT 1;
  v_held := COALESCE(v_held, 0);

  INSERT INTO account_settlements (
    account_period_id, agent_id, cycle_type, opening_balance, cash_collected,
    upi_collected, bank_collected, cheque_collected, loan_distribution,
    expenses, expected_closing_balance, physical_cash_declared, difference,
    agent_bf_handed_over, status
  ) VALUES (
    p_account_period_id, p_agent_id, p_cycle_type, v_opening, v_cash,
    v_upi, v_bank, v_cheque, v_loans,
    v_expenses, v_held, v_held, 0,
    v_held, 'Pending Owner Review'
  ) RETURNING settlement_id INTO v_settlement_id;

  -- The period is Submitted, not Running: the agent has handed it over and
  -- must not keep collecting into an account they have closed off.
  UPDATE account_periods
     SET status = 'Submitted'
   WHERE account_period_id = p_account_period_id;

  RETURN json_build_object(
    'settlement_id', v_settlement_id,
    'amount_held', v_held,
    'status', 'Pending Owner Review'
  );
END;
$$;

-- Approving is where the money moves, and it is the only place it does.
CREATE OR REPLACE FUNCTION app.approve_agent_settlement(p_settlement_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_business_id UUID;
  v_membership_id UUID;
  v_period_id UUID;
  v_status settlement_status_enum;
  v_amount DECIMAL(14,0);
  v_assignment_id UUID;
  v_held DECIMAL(14,0);
BEGIN
  SELECT s.account_period_id, s.status, s.agent_bf_handed_over,
         ap.business_id, ap.agent_membership_id
    INTO v_period_id, v_status, v_amount, v_business_id, v_membership_id
  FROM account_settlements s
  JOIN account_periods ap ON ap.account_period_id = s.account_period_id
  WHERE s.settlement_id = p_settlement_id
  FOR UPDATE OF s;

  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'No such settlement' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner can approve a settlement' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'Pending Owner Review' THEN
    RAISE EXCEPTION 'This settlement has already been decided' USING ERRCODE = '23514';
  END IF;

  -- Taken from what the agent holds NOW, capped at it. Between submitting and
  -- approving they may have collected again; that money belongs to the next
  -- account, not to this one, and must not be swept up by an approval.
  SELECT assignment_id, COALESCE(agent_bf_current, 0) INTO v_assignment_id, v_held
  FROM agent_bf_assignments
  WHERE membership_id = v_membership_id
  ORDER BY business_date DESC NULLS LAST, created_at DESC
  LIMIT 1
  FOR UPDATE;

  v_amount := LEAST(COALESCE(v_amount, 0), COALESCE(v_held, 0));

  IF v_assignment_id IS NOT NULL AND v_amount > 0 THEN
    UPDATE agent_bf_assignments
       SET agent_bf_current = agent_bf_current - v_amount, updated_at = now()
     WHERE assignment_id = v_assignment_id;

    UPDATE businesses
       SET owner_bf_balance = owner_bf_balance + v_amount
     WHERE business_id = v_business_id;
  END IF;

  UPDATE account_settlements
     SET status = 'Approved',
         agent_bf_handed_over = v_amount,
         reviewed_by_person_id = app.current_person_id(),
         reviewed_at = now()
   WHERE settlement_id = p_settlement_id;

  UPDATE account_periods
     SET status = 'Approved', actual_end_date = now()
   WHERE account_period_id = v_period_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    'settlement_approved', 0, p_settlement_id,
    json_build_object('amount', v_amount, 'membership_id', v_membership_id),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'approved',
    'settlement_id', p_settlement_id,
    'amount_transferred', v_amount
  );
END;
$$;

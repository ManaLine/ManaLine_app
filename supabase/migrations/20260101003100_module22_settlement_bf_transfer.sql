-- =============================================================================
-- 0031 — Module 22: Settlement BF Transfer (Merged Addendum item 4)
-- =============================================================================
-- Resolves a real, honestly-flagged ambiguity found in TWO separate files
-- while wiring submitSettlement: agent_settlement_state.dart's header
-- comment and account_review_state.dart's approveSettlement() comment both
-- independently concluded Submit (not Owner Approve) is the correct trigger
-- point for "FULL agent_bf_current returns to businesses.owner_bf_balance"
-- (Merged Addendum item 4) — but neither file actually implemented the
-- transfer; both left it as a flagged gap pointing at each other.
--
-- Fixed here: app.submit_agent_settlement (0021) now also atomically zeros
-- the agent's agent_bf_current and adds that same amount to
-- businesses.owner_bf_balance, in the same transaction as the
-- account_settlements insert. account_review_state.dart's approveSettlement
-- remains correctly a pure status-change (no transfer there) — its own
-- comment already said as much, now confirmed correct rather than merely
-- assumed.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.submit_agent_settlement(
  p_account_period_id UUID,
  p_agent_id UUID,
  p_cycle_type settlement_cycle_type_enum,
  p_opening_balance DECIMAL(14,0),
  p_cash_collected DECIMAL(14,0),
  p_upi_collected DECIMAL(14,0),
  p_bank_collected DECIMAL(14,0),
  p_cheque_collected DECIMAL(14,0),
  p_loan_distribution DECIMAL(14,0),
  p_expenses DECIMAL(14,0),
  p_expected_closing_balance DECIMAL(14,0),
  p_physical_cash_declared DECIMAL(14,0)
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_settlement_id UUID;
  v_difference DECIMAL(14,0);
  v_membership_id UUID;
  v_business_id UUID;
  v_transfer_amount DECIMAL(14,0);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM agents WHERE agent_id = p_agent_id AND person_id = app.current_person_id()) THEN
    RAISE EXCEPTION 'Not authorized — not your own agent record' USING ERRCODE = '42501';
  END IF;

  v_difference := p_physical_cash_declared - p_expected_closing_balance;

  INSERT INTO account_settlements (
    account_period_id, agent_id, cycle_type, opening_balance, cash_collected, upi_collected,
    bank_collected, cheque_collected, loan_distribution, expenses, expected_closing_balance,
    physical_cash_declared, difference, status
  ) VALUES (
    p_account_period_id, p_agent_id, p_cycle_type, p_opening_balance, p_cash_collected, p_upi_collected,
    p_bank_collected, p_cheque_collected, p_loan_distribution, p_expenses, p_expected_closing_balance,
    p_physical_cash_declared, v_difference, 'Pending Owner Review'
  ) RETURNING settlement_id INTO v_settlement_id;

  -- Merged Addendum item 4: FULL agent_bf_current returns to
  -- businesses.owner_bf_balance at Agent settlement (this submit step).
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
$$;

COMMENT ON FUNCTION app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL) IS
  'AG-006 settlement submission. Inserts account_settlements at Pending Owner Review AND atomically transfers agent_bf_current back to businesses.owner_bf_balance in the same transaction (Merged Addendum item 4) — this was previously missing (0021), causing a real gap where two separate files each correctly flagged the ambiguity but neither implemented the transfer. Owner approveSettlement (OW-013) remains correctly a pure status-change with no transfer of its own.';

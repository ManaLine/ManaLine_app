-- =============================================================================
-- 0021 — Module 12: Collection, Loan Wizard, Settlement, Cash Transfer,
-- and Owner-Edits-Customer RPCs
-- =============================================================================
-- Closes the RPC/RLS gaps flagged during Owner (Collection Mode, Customer,
-- Loan Wizard) and Agent (Settlement, Draft Transactions, Customer, Loan
-- Distribution) wiring. Same SECURITY DEFINER conventions as 0019/0020.
--
-- SCOPE NOTE: this migration does NOT include start_business_session,
-- add_area_to_session, remove_area_from_session, confirm_bf_assignment, or
-- request_bf_update (flagged by the Agent Dashboard sub-chat). Those need a
-- dedicated design pass: account_periods has exactly ONE operating_area_id
-- per period (not a list), so "add/remove area from session" as named does
-- not map onto the current schema shape — that mismatch needs resolving
-- against the AG-001/OW-002 spec before writing these, not guessed here.

-- -----------------------------------------------------------------------------
-- 12.1 owner_update_customer_phone / owner_update_customer_address
-- Owner has no RLS write path to another person's persons/person_addresses/
-- person_phone_history (only self-write + business-partner SELECT exist).
-- These RPCs run as the Owner, verify the target person shares an active
-- business membership with the caller, then perform the exact same
-- close-old/insert-new history pattern already established client-side in
-- investor_profile_state.dart.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_update_customer_phone(p_person_id BIGINT, p_phone_number VARCHAR(15))
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.shares_active_business(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  UPDATE person_phone_history SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = p_person_id AND is_current = TRUE;

  INSERT INTO person_phone_history (person_id, phone_number, from_date, is_current, reason)
  VALUES (p_person_id, p_phone_number, CURRENT_DATE, TRUE, 'Updated by Owner');

  UPDATE persons SET mobile_number = p_phone_number WHERE person_id = p_person_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_update_customer_phone(BIGINT, VARCHAR) TO authenticated;

CREATE OR REPLACE FUNCTION app.owner_update_customer_address(
  p_person_id BIGINT, p_door_no VARCHAR, p_pin_code VARCHAR, p_village_id UUID,
  p_mandal VARCHAR, p_district VARCHAR, p_state VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.shares_active_business(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  UPDATE person_addresses SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = p_person_id AND is_current = TRUE;

  INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
  VALUES (p_person_id, COALESCE(p_door_no, '-'), COALESCE(p_pin_code, '000000'), p_village_id,
          COALESCE(p_mandal, '-'), COALESCE(p_district, '-'), COALESCE(p_state, '-'), CURRENT_DATE, TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_update_customer_address(BIGINT, VARCHAR, VARCHAR, UUID, VARCHAR, VARCHAR, VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12.2 record_collection — atomic collection + payment split + balance update.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_collection(
  p_loan_id UUID,
  p_customer_id UUID,
  p_collected_amount DECIMAL(14,0),
  p_payer_type payer_type_enum,
  p_result_type collection_result_type_enum,
  p_business_date DATE,
  p_collected_by_membership_id UUID,
  p_guarantor_id UUID DEFAULT NULL,
  p_difference_amount DECIMAL(14,0) DEFAULT 0,
  p_excess_disposition excess_disposition_enum DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL,
  p_splits JSON DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_receipt VARCHAR(30);
  v_collection_id UUID;
  v_split JSON;
BEGIN
  SELECT business_id INTO v_business_id FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.own_active_agent_membership_permits(p_collected_by_membership_id, 'can_collect_payments')
     AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record collections on this loan' USING ERRCODE = '42501';
  END IF;

  v_receipt := 'RCT-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO collections (
    loan_id, customer_id, receipt_number, collected_amount, payer_type, guarantor_id,
    collected_by_membership_id, business_date, result_type, difference_amount,
    excess_disposition, remarks
  ) VALUES (
    p_loan_id, p_customer_id, v_receipt, p_collected_amount, p_payer_type, p_guarantor_id,
    p_collected_by_membership_id, p_business_date, p_result_type, p_difference_amount,
    p_excess_disposition, p_remarks
  ) RETURNING collection_id INTO v_collection_id;

  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
      VALUES (v_collection_id, (v_split->>'payment_mode')::payment_mode_enum, (v_split->>'amount')::DECIMAL(14,0));
    END LOOP;
  END IF;

  UPDATE loans SET remaining_balance = remaining_balance - p_collected_amount, updated_at = now()
  WHERE loan_id = p_loan_id;

  RETURN v_collection_id;
END;
$$;

COMMENT ON FUNCTION app.record_collection(UUID, UUID, DECIMAL, payer_type_enum, collection_result_type_enum, DATE, UUID, UUID, DECIMAL, excess_disposition_enum, TEXT, JSON) IS
  'AG-002/OW-006 Collection Mode. Atomically inserts collections + collection_payment_splits (payment_mode/amount, verified against 0008) and decrements loans.remaining_balance. Does NOT enforce SUM(collection_payment_splits.amount) = collected_amount — that invariant is explicitly flagged as unenforced by a plain CHECK in the table''s own 0008 comment (needs a trigger or app-layer validation, not added here).';

GRANT EXECUTE ON FUNCTION app.record_collection(UUID, UUID, DECIMAL, payer_type_enum, collection_result_type_enum, DATE, UUID, UUID, DECIMAL, excess_disposition_enum, TEXT, JSON) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12.3 create_loan_with_bf_check — atomic loan issuance with BF Cash gate.
-- Checks agent_bf_assignments.agent_bf_current (session-based BF per Merged
-- Addendum item 4) covers amount_given before creating the loan; deducts BF
-- on success. Schedule generation is a simple equal-installment, fixed-
-- interval generator (Daily/Weekly/Monthly per duration_value) — NOT the
-- full Calculation Engine; flagged, not a substitute for 15_Calculation_
-- Engine.md's real due-date/holiday logic if one exists.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.create_loan_with_bf_check(
  p_customer_id UUID,
  p_business_id UUID,
  p_repayment_amount DECIMAL(14,0),
  p_interest_amount DECIMAL(14,0),
  p_processing_fee DECIMAL(14,0),
  p_repayment_type repayment_frequency_enum,
  p_duration_value INT,
  p_installment_amount DECIMAL(14,0),
  p_grace_period_days INT,
  p_collection_agent_membership_id UUID,
  p_effective_date DATE,
  p_live_photo_url TEXT,
  p_template_id UUID DEFAULT NULL,
  p_penalty_template_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
  v_amount_given DECIMAL(14,0);
  v_bf_current DECIMAL(14,0);
  v_loan_id UUID;
  v_loan_number VARCHAR(30);
  v_interval INTERVAL;
  i INT;
BEGIN
  v_person_id := app.current_person_id();
  IF NOT app.is_owner(p_business_id) AND NOT app.own_active_agent_membership_permits(p_collection_agent_membership_id, 'can_issue_loans') THEN
    RAISE EXCEPTION 'Not authorized to issue loans for this business' USING ERRCODE = '42501';
  END IF;

  v_amount_given := p_repayment_amount - p_interest_amount - p_processing_fee;

  SELECT agent_bf_current INTO v_bf_current
  FROM agent_bf_assignments
  WHERE membership_id = p_collection_agent_membership_id
  ORDER BY business_date DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_bf_current IS NULL OR v_bf_current < v_amount_given THEN
    RAISE EXCEPTION 'BF Cash Validation failed: available % < required %', COALESCE(v_bf_current, 0), v_amount_given USING ERRCODE = '23514';
  END IF;

  v_loan_number := 'LN-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO loans (
    loan_number, customer_id, business_id, template_id, repayment_amount, interest_amount,
    processing_fee, repayment_type, duration_value, installment_amount, grace_period_days,
    penalty_template_note, remaining_balance, collection_agent_membership_id, effective_date,
    loan_status, issue_business_date, live_photo_url
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, p_template_id, p_repayment_amount, p_interest_amount,
    p_processing_fee, p_repayment_type, p_duration_value, p_installment_amount, p_grace_period_days,
    p_penalty_template_note, p_repayment_amount, p_collection_agent_membership_id, p_effective_date,
    'Active', p_effective_date, p_live_photo_url
  ) RETURNING loan_id INTO v_loan_id;

  v_interval := CASE p_repayment_type
    WHEN 'Daily' THEN INTERVAL '1 day'
    WHEN 'Weekly' THEN INTERVAL '7 days'
    WHEN 'Monthly' THEN INTERVAL '1 month'
  END;

  FOR i IN 1..p_duration_value LOOP
    INSERT INTO loan_schedule (loan_id, installment_number, due_date, installment_amount, status)
    VALUES (v_loan_id, i, (p_effective_date + (v_interval * i))::DATE, p_installment_amount, 'Pending');
  END LOOP;

  UPDATE agent_bf_assignments
  SET agent_bf_current = agent_bf_current - v_amount_given
  WHERE membership_id = p_collection_agent_membership_id
    AND (business_date = (SELECT business_date FROM agent_bf_assignments WHERE membership_id = p_collection_agent_membership_id ORDER BY business_date DESC NULLS LAST LIMIT 1)
         OR business_date IS NULL);

  RETURN v_loan_id;
END;
$$;

COMMENT ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) IS
  'OW-005 loan issuance. Atomically BF-checks, inserts loans + generated loan_schedule, and deducts BF. Guarantor insert is NOT included here (guarantors.loan_id needs a real loan_id first) — insert guarantors client-side after this returns, RLS permitting. Schedule generation is a simplified equal-interval model, not the full Calculation Engine.';

GRANT EXECUTE ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12.4 submit_agent_settlement — settlement submission.
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

  RETURN v_settlement_id;
END;
$$;

COMMENT ON FUNCTION app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL) IS
  'AG-006 settlement submission. Inserts account_settlements at Pending Owner Review. Does NOT resolve BF transfer / short-excess register write here — settlement_adjustments creation on Owner review is a separate, already-Owner-side flow (OW-013 Account Review), not duplicated in this RPC.';

GRANT EXECUTE ON FUNCTION app.submit_agent_settlement(UUID, UUID, settlement_cycle_type_enum, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL, DECIMAL) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12.5 initiate_cash_transfer / confirm_cash_transfer — agent-to-agent BF.
-- confirm resolves the confirming side from the caller's own identity
-- server-side, not a client-supplied flag.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.initiate_cash_transfer(p_to_agent_id UUID, p_amount DECIMAL(14,0), p_business_date DATE)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_from_agent_id UUID;
  v_transfer_id UUID;
BEGIN
  SELECT agent_id INTO v_from_agent_id FROM agents WHERE person_id = app.current_person_id();
  IF v_from_agent_id IS NULL THEN
    RAISE EXCEPTION 'Caller is not an agent' USING ERRCODE = '42501';
  END IF;
  IF v_from_agent_id = p_to_agent_id THEN
    RAISE EXCEPTION 'Cannot transfer to self' USING ERRCODE = '23514';
  END IF;

  INSERT INTO cash_transfers (from_agent_id, to_agent_id, amount, business_date, from_agent_confirmed_at)
  VALUES (v_from_agent_id, p_to_agent_id, p_amount, p_business_date, now())
  RETURNING transfer_id INTO v_transfer_id;

  RETURN v_transfer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.initiate_cash_transfer(UUID, DECIMAL, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION app.confirm_cash_transfer(p_transfer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_caller_agent_id UUID;
  v_from UUID;
  v_to UUID;
BEGIN
  SELECT agent_id INTO v_caller_agent_id FROM agents WHERE person_id = app.current_person_id();
  SELECT from_agent_id, to_agent_id INTO v_from, v_to FROM cash_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;

  IF v_caller_agent_id IS NULL OR (v_caller_agent_id <> v_from AND v_caller_agent_id <> v_to) THEN
    RAISE EXCEPTION 'Not a party to this transfer' USING ERRCODE = '42501';
  END IF;

  IF v_caller_agent_id = v_from THEN
    UPDATE cash_transfers SET from_agent_confirmed_at = now() WHERE transfer_id = p_transfer_id;
  ELSE
    UPDATE cash_transfers SET to_agent_confirmed_at = now() WHERE transfer_id = p_transfer_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION app.confirm_cash_transfer(UUID) IS
  'AG-007. Resolves which side (from/to) the caller is server-side via their own agent_id — never trusts a client-supplied "which side" flag, per the design note flagged during Sub-chat D review.';

GRANT EXECUTE ON FUNCTION app.confirm_cash_transfer(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 12.6 submit_draft — LIMITED SCOPE, flagged.
-- Only draft_type='Loan Distribution' is implemented (the one case named
-- explicitly in collection_drafts' own table comment, reusable by the BF-
-- Cash-Low auto-save-as-Draft flow). Every other draft_type raises a clear
-- exception rather than guessing a payload_json shape this pass has no
-- visibility into.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.submit_draft(p_draft_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_draft RECORD;
  v_loan_id UUID;
BEGIN
  SELECT * INTO v_draft FROM collection_drafts WHERE draft_id = p_draft_id FOR UPDATE;
  IF v_draft IS NULL THEN
    RAISE EXCEPTION 'Draft not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.own_active_agent_membership_permits(v_draft.created_by_membership_id, 'can_create_drafts') THEN
    RAISE EXCEPTION 'Not authorized for this draft' USING ERRCODE = '42501';
  END IF;

  IF v_draft.draft_type <> 'Loan Distribution' THEN
    RAISE EXCEPTION 'submit_draft only implements draft_type=Loan Distribution in this migration — % not yet supported', v_draft.draft_type
      USING ERRCODE = '0A000';
  END IF;

  -- payload_json shape for Loan Distribution assumed to mirror
  -- create_loan_with_bf_check's params — NOT independently verified against
  -- what the Draft-save UI actually writes; confirm before relying on this.
  v_loan_id := app.create_loan_with_bf_check(
    (v_draft.payload_json->>'customer_id')::UUID,
    app.business_id_for_membership(v_draft.created_by_membership_id),
    (v_draft.payload_json->>'repayment_amount')::DECIMAL,
    (v_draft.payload_json->>'interest_amount')::DECIMAL,
    (v_draft.payload_json->>'processing_fee')::DECIMAL,
    (v_draft.payload_json->>'repayment_type')::repayment_frequency_enum,
    (v_draft.payload_json->>'duration_value')::INT,
    (v_draft.payload_json->>'installment_amount')::DECIMAL,
    (v_draft.payload_json->>'grace_period_days')::INT,
    v_draft.created_by_membership_id,
    (v_draft.payload_json->>'effective_date')::DATE,
    v_draft.payload_json->>'live_photo_url'
  );

  UPDATE collection_drafts SET status = 'Submitted', loan_id = v_loan_id, updated_at = now()
  WHERE draft_id = p_draft_id;

  RETURN v_loan_id;
END;
$$;

COMMENT ON FUNCTION app.submit_draft(UUID) IS
  'AG-005. LIMITED SCOPE: only draft_type=Loan Distribution implemented — every other draft_type raises a clear not-yet-supported exception (ERRCODE 0A000), not a silent no-op. payload_json field names assumed, not verified against the actual draft-save UI.';

GRANT EXECUTE ON FUNCTION app.submit_draft(UUID) TO authenticated;

-- =============================================================================
-- 0024 — Module 15: create_loan_with_bf_check Return-Shape Fix
-- =============================================================================
-- Fixes a real integration bug found while wiring the guarantor insert:
-- loan_wizard_state.dart's checkEligibilityAndCreate (written by a sub-chat
-- before this RPC existed) parses the RPC response as a JSON map with
-- loan_id/loan_number keys — but 0021's create_loan_with_bf_check returns a
-- bare UUID. This would have thrown a cast exception on every successful
-- call (response as Map<String, dynamic> on a raw UUID string fails).
--
-- Postgres requires DROP+CREATE (not just CREATE OR REPLACE) to change a
-- function's return type, hence a fresh migration rather than editing 0021
-- in place — 0021 may already be applied to a live database.
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT);

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
RETURNS JSON
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

  RETURN json_build_object('loan_id', v_loan_id, 'loan_number', v_loan_number);
END;
$$;

COMMENT ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) IS
  'OW-005/AG-007 loan issuance. Returns {loan_id, loan_number} as JSON to match checkEligibilityAndCreate''s existing parsing (map[''loan_id'']/map[''loan_number'']) — 0021''s original bare-UUID return would have thrown a cast exception on every successful call. Guarantor insert still NOT included here — see loan_wizard_state.dart''s confirm(), which now inserts guarantors client-side after this RPC returns, per guarantors RLS (0014) permitting Owner/Agent write once loan_id/business_id/customer_id exist.';

GRANT EXECUTE ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- submit_draft (0021) also calls create_loan_with_bf_check and assigned its
-- result straight to a UUID variable — same bug, same root cause. Re-created
-- here rather than left broken by the return-type change above.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.submit_draft(p_draft_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_draft RECORD;
  v_result JSON;
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

  v_result := app.create_loan_with_bf_check(
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
  v_loan_id := (v_result->>'loan_id')::UUID;

  UPDATE collection_drafts SET status = 'Submitted', loan_id = v_loan_id, updated_at = now()
  WHERE draft_id = p_draft_id;

  RETURN v_loan_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.submit_draft(UUID) TO authenticated;

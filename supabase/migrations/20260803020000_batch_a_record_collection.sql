-- =============================================================================
-- BATCH A (2/6) — record_collection rewrite + submit_draft compatibility
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   1. Rebuilds "record a payment collected" (record_collection) so that:
--        a. only a member of the SAME business as the loan can record on it;
--        b. the amount must be a real positive number, the customer must be
--           the one on the loan, and the date cannot be in the future or
--           before the loan was issued;
--        c. the cash/UPI/bank/cheque split amounts must add up to the total
--           (if no splits given, the whole amount counts as cash);
--        d. whether a payment is Full / Partial / Excess is worked out by
--           the server, not trusted from the phone;
--        e. the collected money is ADDED to the collector's own cash
--           (BF): an agent's float if an agent collected it, or the
--           Owner's own balance if the Owner collected it;
--        f. a DUPLICATE GUARD: if someone already recorded a payment on
--           this loan today, the function returns a warning with that
--           earlier payment's details instead of saving — the app shows
--           "Close / Continue", and Continue re-calls with confirm=TRUE.
--   2. Updates submit_draft (resuming a saved draft) so it understands the
--      new JSON answers from record_collection and create_loan_with_bf_check
--      — and never deletes a draft when the money check failed.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. record_collection — rebuilt (return type changed, so the old function
--    is dropped first).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.record_collection(UUID, UUID, DECIMAL, payer_type_enum, collection_result_type_enum, DATE, UUID, UUID, DECIMAL, excess_disposition_enum, TEXT, JSON);

CREATE OR REPLACE FUNCTION app.record_collection(
  p_loan_id UUID,
  p_customer_id UUID,
  p_collected_amount DECIMAL(14,0),
  p_payer_type payer_type_enum,
  p_business_date DATE,
  p_collected_by_membership_id UUID,
  p_guarantor_id UUID DEFAULT NULL,
  p_result_type collection_result_type_enum DEFAULT NULL, -- NULL = let the server decide
  p_difference_amount DECIMAL(14,0) DEFAULT NULL,          -- NULL = let the server decide
  p_excess_disposition excess_disposition_enum DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL,
  p_splits JSON DEFAULT NULL,                              -- [ {payment_mode, amount}, ... ]
  p_confirm_duplicate BOOLEAN DEFAULT FALSE                -- TRUE = "Continue" after the warning
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_loan_customer UUID;
  v_installment DECIMAL(14,0);
  v_effective_date DATE;
  v_receipt VARCHAR(30);
  v_collection_id UUID;
  v_split JSON;
  v_total_splits DECIMAL(14,0) := 0;
  v_role business_member_role_enum;
  v_result_type collection_result_type_enum;
  v_difference DECIMAL(14,0) := 0;
BEGIN
  -- Lock the loan first, so two phones cannot both pass the duplicate check
  -- and record the same rupee at the same instant.
  SELECT business_id, customer_id, installment_amount, effective_date
    INTO v_business_id, v_loan_customer, v_installment, v_effective_date
  FROM loans
  WHERE loan_id = p_loan_id
  FOR UPDATE;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;

  -- Authorization: the Owner of this loan's business, or an agent who is a
  -- permitted member of THIS business (the cross-business fix).
  IF NOT app.own_active_agent_membership_permits(p_collected_by_membership_id, 'can_collect_payments', v_business_id)
     AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record collections on this loan' USING ERRCODE = '42501';
  END IF;

  -- The collector's own membership must live in the same business as the
  -- loan — otherwise money could be recorded against business B's loan by
  -- a membership of business A.
  IF app.business_id_for_membership(p_collected_by_membership_id) <> v_business_id THEN
    RAISE EXCEPTION 'Collector is not a member of this business' USING ERRCODE = '42501';
  END IF;

  -- --- Validations ---------------------------------------------------------
  IF p_collected_amount <= 0 THEN
    RAISE EXCEPTION 'Collected amount must be positive' USING ERRCODE = '23514';
  END IF;
  IF p_customer_id <> v_loan_customer THEN
    RAISE EXCEPTION 'This customer is not the borrower on this loan' USING ERRCODE = '23514';
  END IF;
  IF p_business_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Cannot record a payment for a future date' USING ERRCODE = '23514';
  END IF;
  IF p_business_date < v_effective_date THEN
    RAISE EXCEPTION 'Cannot record a payment before the loan was issued' USING ERRCODE = '23514';
  END IF;
  IF p_payer_type = 'Guarantor' AND p_guarantor_id IS NULL THEN
    RAISE EXCEPTION 'A guarantor id is required when the payer is a Guarantor' USING ERRCODE = '23514';
  END IF;

  -- The split amounts must be positive and add up to the total collected.
  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      IF (v_split->>'amount')::DECIMAL(14,0) <= 0 THEN
        RAISE EXCEPTION 'Split amounts must be positive' USING ERRCODE = '23514';
      END IF;
      v_total_splits := v_total_splits + (v_split->>'amount')::DECIMAL(14,0);
    END LOOP;
    IF v_total_splits <> p_collected_amount THEN
      RAISE EXCEPTION 'Payment splits must sum to the collected amount' USING ERRCODE = '23514';
    END IF;
  END IF;

  -- --- Duplicate guard ------------------------------------------------------
  -- Another member already recorded a payment on this loan TODAY. Return the
  -- warning with that payment's details so the app can show "Close / Continue".
  IF NOT p_confirm_duplicate THEN
    IF EXISTS (
      SELECT 1 FROM collections c
      WHERE c.loan_id = p_loan_id
        AND c.business_date = p_business_date
        AND c.collected_by_membership_id <> p_collected_by_membership_id
    ) THEN
      RETURN json_build_object(
        'status', 'duplicate_warning',
        'existing', (SELECT COALESCE(json_agg(json_build_object(
                        'collected_amount', c.collected_amount,
                        'result_type', c.result_type,
                        'recorded_by', p.full_name,
                        'at', c.created_at)),
                      '[]'::json)
                     FROM collections c
                     JOIN business_members bm ON bm.membership_id = c.collected_by_membership_id
                     JOIN persons p ON p.person_id = bm.person_id
                     WHERE c.loan_id = p_loan_id
                       AND c.business_date = p_business_date
                       AND c.collected_by_membership_id <> p_collected_by_membership_id)
      );
    END IF;
  END IF;

  -- --- Work out Full / Partial / Excess, unless the client already knew ----
  v_result_type := p_result_type;
  v_difference := p_difference_amount;
  IF v_result_type IS NULL THEN
    v_difference := p_collected_amount - v_installment;
    IF v_difference > 0 THEN
      v_result_type := 'Excess';
    ELSIF v_difference < 0 THEN
      v_result_type := 'Partial';
    ELSE
      v_result_type := 'Full';
    END IF;
  END IF;
  IF v_difference IS NULL THEN v_difference := 0; END IF;
  IF v_result_type = 'Excess' AND p_excess_disposition IS NULL THEN
    RAISE EXCEPTION 'An excess payment needs a disposition (how the extra was returned or carried)' USING ERRCODE = '23514';
  END IF;

  v_receipt := 'RCT-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO collections (
    loan_id, customer_id, receipt_number, collected_amount, payer_type, guarantor_id,
    collected_by_membership_id, business_date, result_type, difference_amount,
    excess_disposition, remarks
  ) VALUES (
    p_loan_id, p_customer_id, v_receipt, p_collected_amount, p_payer_type, p_guarantor_id,
    p_collected_by_membership_id, p_business_date, v_result_type, v_difference,
    p_excess_disposition, p_remarks
  ) RETURNING collection_id INTO v_collection_id;

  -- Payment-mode split rows. If none were sent, treat the whole amount as
  -- cash so the day ledger still sees it.
  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
      VALUES (v_collection_id, (v_split->>'payment_mode')::payment_mode_enum, (v_split->>'amount')::DECIMAL(14,0));
    END LOOP;
  ELSE
    INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
    VALUES (v_collection_id, 'Cash', p_collected_amount);
  END IF;

  -- Reduce the customer's remaining balance, never below zero.
  UPDATE loans
  SET remaining_balance = GREATEST(remaining_balance - p_collected_amount, 0), updated_at = now()
  WHERE loan_id = p_loan_id;

  -- --- Credit the collector's own cash (BF) with the collected money ------
  -- The cash physically sits with whoever collected it. An agent's share
  -- goes on their float; the Owner's own collections go on the Owner's BF.
  SELECT role INTO v_role FROM business_members WHERE membership_id = p_collected_by_membership_id;
  IF v_role = 'Owner' THEN
    UPDATE businesses SET owner_bf_balance = owner_bf_balance + p_collected_amount
    WHERE business_id = v_business_id;
  ELSIF v_role = 'Agent' THEN
    UPDATE agent_bf_assignments
    SET agent_bf_current = agent_bf_current + p_collected_amount, updated_at = now()
    WHERE assignment_id = (
      SELECT assignment_id FROM agent_bf_assignments
      WHERE membership_id = p_collected_by_membership_id
      ORDER BY business_date DESC NULLS LAST
      LIMIT 1
    );
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No BF assignment for this agent — the Owner must grant BF before collections can be credited' USING ERRCODE = 'P0002';
    END IF;
  ELSE
    RAISE EXCEPTION 'Collector must be the Owner or an Agent' USING ERRCODE = '42501';
  END IF;

  RETURN json_build_object(
    'status', 'saved',
    'collection_id', v_collection_id,
    'receipt_number', v_receipt,
    'result_type', v_result_type,
    'collected_amount', p_collected_amount,
    'remaining_balance', (SELECT remaining_balance FROM loans WHERE loan_id = p_loan_id)
  );
END;
$$;

COMMENT ON FUNCTION app.record_collection(UUID, UUID, DECIMAL, payer_type_enum, DATE, UUID, UUID, collection_result_type_enum, DECIMAL, excess_disposition_enum, TEXT, JSON, BOOLEAN) IS
  'AG-002/OW-006 Collection Mode. Server-classifies Full/Partial/Excess, validates amount/customer/date/splits, credits the collector''s BF (agent float or Owner BF), and guards against a same-day double entry by another member (returns status=duplicate_warning; the app re-calls with p_confirm_duplicate=TRUE to continue).';

GRANT EXECUTE ON FUNCTION app.record_collection(UUID, UUID, DECIMAL, payer_type_enum, DATE, UUID, UUID, collection_result_type_enum, DECIMAL, excess_disposition_enum, TEXT, JSON, BOOLEAN) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. submit_draft — redefined so it understands the new JSON answers.
--    A draft is only deleted when the action actually succeeded; on a
--    duplicate warning or insufficient BF it is KEPT so it can be retried.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.submit_draft(p_draft_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_draft RECORD;
  v_business_id UUID;
  v_loan_result JSON;
  v_col_result JSON;
  v_result JSON;
  v_remark_id UUID;
  v_document_id UUID;
BEGIN
  SELECT * INTO v_draft FROM collection_drafts WHERE draft_id = p_draft_id FOR UPDATE;
  IF v_draft IS NULL THEN
    RAISE EXCEPTION 'Draft not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.own_active_agent_membership_permits(v_draft.created_by_membership_id, 'can_create_drafts') THEN
    RAISE EXCEPTION 'Not authorized for this draft' USING ERRCODE = '42501';
  END IF;

  v_business_id := app.business_id_for_membership(v_draft.created_by_membership_id);

  CASE v_draft.draft_type
    WHEN 'Loan Distribution' THEN
      v_loan_result := app.create_loan_with_bf_check(
        (v_draft.payload_json->>'customer_id')::UUID,
        v_business_id,
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
      -- BF still too small at submit time: keep the draft, tell the caller.
      IF (v_loan_result->>'passed') = 'false' THEN
        RETURN json_build_object(
          'draft_type', 'Loan Distribution', 'passed', false,
          'failure_reason', v_loan_result->>'failure_reason'
        );
      END IF;
      v_result := json_build_object('draft_type', 'Loan Distribution', 'passed', true,
                                    'loan_id', v_loan_result->>'loan_id',
                                    'loan_number', v_loan_result->>'loan_number');

    WHEN 'Collection' THEN
      v_col_result := app.record_collection(
        (v_draft.payload_json->>'loan_id')::UUID,
        (v_draft.payload_json->>'customer_id')::UUID,
        (v_draft.payload_json->>'collected_amount')::DECIMAL,
        (v_draft.payload_json->>'payer_type')::payer_type_enum,
        (v_draft.payload_json->>'business_date')::DATE,
        v_draft.created_by_membership_id,
        NULLIF(v_draft.payload_json->>'guarantor_id', '')::UUID,
        NULLIF(v_draft.payload_json->>'result_type', '')::collection_result_type_enum,
        NULLIF(v_draft.payload_json->>'difference_amount', '')::DECIMAL,
        NULLIF(v_draft.payload_json->>'excess_disposition', '')::excess_disposition_enum,
        v_draft.payload_json->>'remarks',
        v_draft.payload_json->'splits',
        false
      );
      -- Another member already collected this loan today: keep the draft.
      IF (v_col_result->>'status') = 'duplicate_warning' THEN
        RETURN json_build_object('draft_type', 'Collection', 'passed', false,
                                 'failure_reason', 'duplicate_warning',
                                 'existing', v_col_result->'existing');
      END IF;
      v_result := json_build_object('draft_type', 'Collection', 'passed', true,
                                    'collection_id', v_col_result->>'collection_id');

    WHEN 'Customer Remark' THEN
      INSERT INTO customer_remarks (customer_id, entered_by_person_id, remark_text, priority, business_date)
      VALUES (
        (v_draft.payload_json->>'customer_id')::UUID,
        app.current_person_id(),
        v_draft.payload_json->>'remark_text',
        COALESCE(NULLIF(v_draft.payload_json->>'priority', '')::remark_priority_enum, 'Normal'),
        COALESCE((v_draft.payload_json->>'business_date')::DATE, CURRENT_DATE)
      ) RETURNING remark_id INTO v_remark_id;
      v_result := json_build_object('draft_type', 'Customer Remark', 'passed', true, 'remark_id', v_remark_id);

    WHEN 'Document Upload' THEN
      INSERT INTO customer_documents (customer_id, document_type, file_url)
      VALUES (
        (v_draft.payload_json->>'customer_id')::UUID,
        (v_draft.payload_json->>'document_type')::customer_document_type_enum,
        v_draft.payload_json->>'file_url'
      ) RETURNING document_id INTO v_document_id;
      v_result := json_build_object('draft_type', 'Document Upload', 'passed', true, 'document_id', v_document_id);

    ELSE
      RAISE EXCEPTION 'Unknown draft_type: %', v_draft.draft_type USING ERRCODE = '0A000';
  END CASE;

  -- Only reached when the action succeeded — the draft is a literal delete.
  DELETE FROM collection_drafts WHERE draft_id = p_draft_id;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION app.submit_draft(UUID) IS
  'AG-005. Submits one of the 4 draft types. Deletes the draft only on success; a duplicate warning or insufficient BF keeps the draft for retry.';

GRANT EXECUTE ON FUNCTION app.submit_draft(UUID) TO authenticated;

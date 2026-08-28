-- submit_draft still looked for 'duplicate_warning', which record_collection
-- no longer returns.
--
-- The consequence was not a cosmetic mismatch: the branch fell through, built
-- a success object with a NULL collection_id, and then DELETED the draft. A
-- collection that was refused because the loan already had an entry would
-- have destroyed the draft holding it and written nothing at all -- the exact
-- data loss this session set out to close, reintroduced one function away.
--
-- Only the Collection branch changes. Same signature, so CREATE OR REPLACE
-- cannot leave a second overload behind.
CREATE OR REPLACE FUNCTION app.submit_draft(p_draft_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      -- The draft is left where it is. Nothing was recorded, and a draft is
      -- the only copy of what the Agent entered.
      IF (v_col_result->>'status') = 'already_recorded' THEN
        RETURN json_build_object('draft_type', 'Collection', 'passed', false,
                                 'failure_reason', 'already_recorded',
                                 'existing', v_col_result);
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

  DELETE FROM collection_drafts WHERE draft_id = p_draft_id;

  RETURN v_result;
END;
$function$;

-- =============================================================================
-- 0025 — Module 16: submit_draft — all 4 draft types + submit-delete fix
-- =============================================================================
-- Extends 0021's submit_draft (previously only draft_type='Loan Distribution')
-- to cover all 4 types per collection_drafts.draft_type: Collection, Loan
-- Distribution, Customer Remark, Document Upload — confirmed against
-- AG-005's own spec, which names all 4 explicitly ("no gaps").
--
-- CORRECTION to 0021's own submit_draft (found while re-reading the spec for
-- this extension): AG-005 states submission does a LITERAL ROW DELETE of the
-- draft ("'Draft Deleted' in the source flow is a literal row delete — drafts
-- are the one record type in this schema where DELETE /drafts/{draft_id} is
-- genuinely used, since a draft was never committed data and generates no
-- audit trail of its own"). 0021's version instead soft-updated the draft to
-- status='Submitted' and kept it around with a loan_id link — that was an
-- unverified guess at the time (0021 built submit_draft before this
-- extension pass re-read the actual spec doc), not a deliberate choice.
-- Corrected here: submit_draft now DELETEs the draft row on success, for
-- all 4 types, matching the spec exactly.
-- -----------------------------------------------------------------------------

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
  v_result JSON;
  v_collection_id UUID;
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
      -- payload_json field names assumed to mirror create_loan_with_bf_check's
      -- params — not independently verified against what the Draft-save UI
      -- actually writes; confirm before relying on this in production.
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
      v_result := json_build_object('draft_type', 'Loan Distribution', 'loan_id', v_loan_result->>'loan_id', 'loan_number', v_loan_result->>'loan_number');

    WHEN 'Collection' THEN
      -- payload_json field names assumed to mirror record_collection's
      -- params — same caveat as above, not independently verified.
      v_collection_id := app.record_collection(
        (v_draft.payload_json->>'loan_id')::UUID,
        (v_draft.payload_json->>'customer_id')::UUID,
        (v_draft.payload_json->>'collected_amount')::DECIMAL,
        (v_draft.payload_json->>'payer_type')::payer_type_enum,
        (v_draft.payload_json->>'result_type')::collection_result_type_enum,
        (v_draft.payload_json->>'business_date')::DATE,
        v_draft.created_by_membership_id,
        NULLIF(v_draft.payload_json->>'guarantor_id', '')::UUID,
        COALESCE((v_draft.payload_json->>'difference_amount')::DECIMAL, 0),
        NULLIF(v_draft.payload_json->>'excess_disposition', '')::excess_disposition_enum,
        v_draft.payload_json->>'remarks',
        v_draft.payload_json->'splits'
      );
      v_result := json_build_object('draft_type', 'Collection', 'collection_id', v_collection_id);

    WHEN 'Customer Remark' THEN
      INSERT INTO customer_remarks (customer_id, entered_by_person_id, remark_text, priority, business_date)
      VALUES (
        (v_draft.payload_json->>'customer_id')::UUID,
        app.current_person_id(),
        v_draft.payload_json->>'remark_text',
        COALESCE(NULLIF(v_draft.payload_json->>'priority', '')::remark_priority_enum, 'Normal'),
        COALESCE((v_draft.payload_json->>'business_date')::DATE, CURRENT_DATE)
      ) RETURNING remark_id INTO v_remark_id;
      v_result := json_build_object('draft_type', 'Customer Remark', 'remark_id', v_remark_id);

    WHEN 'Document Upload' THEN
      -- Draft-time upload is assumed to have already put the file in
      -- Storage and recorded its URL in payload_json (this RPC does not
      -- and cannot handle binary upload itself) — same pattern as
      -- live_photo_url elsewhere in this migration set.
      INSERT INTO customer_documents (customer_id, document_type, file_url)
      VALUES (
        (v_draft.payload_json->>'customer_id')::UUID,
        (v_draft.payload_json->>'document_type')::customer_document_type_enum,
        v_draft.payload_json->>'file_url'
      ) RETURNING document_id INTO v_document_id;
      v_result := json_build_object('draft_type', 'Document Upload', 'document_id', v_document_id);

    ELSE
      RAISE EXCEPTION 'Unknown draft_type: %', v_draft.draft_type USING ERRCODE = '0A000';
  END CASE;

  -- Per AG-005 spec: submission is a literal row delete, not a soft
  -- status update — corrects 0021's original UPDATE-to-'Submitted' guess.
  DELETE FROM collection_drafts WHERE draft_id = p_draft_id;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION app.submit_draft(UUID) IS
  'AG-005. All 4 draft_types implemented (Collection, Loan Distribution, Customer Remark, Document Upload). Deletes the draft row on success per spec (literal delete, not status=Submitted). payload_json field names for each type are assumed to mirror their respective RPC/table params — not independently verified against the actual Draft-save UI''s payload shape; confirm before relying on this in production.';

GRANT EXECUTE ON FUNCTION app.submit_draft(UUID) TO authenticated;

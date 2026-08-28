-- One collection entry per loan per business day.
--
-- The old rule warned only when SOMEBODY ELSE had already collected on this
-- loan today, and let the same person record a second, third and fourth
-- entry against the same loan without a word. That is how a day ends with
-- two receipts for one payment and a balance that is short by an instalment
-- nobody can find. A correction is now an amendment (app.amend_collection),
-- not another row.
--
-- Per DAY, not per account cycle. An account period here spans several days,
-- and a Daily-repayment loan is collected on every one of them -- a
-- cycle-wide rule would refuse the second and third day's genuine
-- collections. The day is also the unit the round itself and
-- app.v_collection_due already work in.
--
-- The refusal is a RETURN, not an EXCEPTION: the caller is told which entry
-- already exists so it can offer to edit that one, which is the thing the
-- person at the door actually wants.
--
-- p_confirm_duplicate is kept in the signature and no longer does anything.
-- Removing it means DROP + CREATE, and a stale client still sending it would
-- then get PGRST202 rather than a working call -- the parameter costs one
-- ignored argument, and changing this function's parameter list has already
-- caused PGRST203 four times in this codebase.
CREATE OR REPLACE FUNCTION app.record_collection(
  p_loan_id uuid,
  p_customer_id uuid,
  p_collected_amount numeric,
  p_payer_type payer_type_enum,
  p_business_date date,
  p_collected_by_membership_id uuid,
  p_guarantor_id uuid DEFAULT NULL::uuid,
  p_result_type collection_result_type_enum DEFAULT NULL::collection_result_type_enum,
  p_difference_amount numeric DEFAULT NULL::numeric,
  p_excess_disposition excess_disposition_enum DEFAULT NULL::excess_disposition_enum,
  p_remarks text DEFAULT NULL::text,
  p_splits json DEFAULT NULL::json,
  p_confirm_duplicate boolean DEFAULT false,
  p_payer_name character varying DEFAULT NULL::character varying,
  p_idempotency_key text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_loan_customer UUID;
  v_installment DECIMAL(14,0);
  v_owed DECIMAL(14,0);
  v_effective_date DATE;
  v_receipt VARCHAR(30);
  v_collection_id UUID;
  v_split JSON;
  v_total_splits DECIMAL(14,0) := 0;
  v_role business_member_role_enum;
  v_result_type collection_result_type_enum;
  v_difference DECIMAL(14,0) := 0;
  v_replay JSON;
  v_result JSON;
  v_existing collections%ROWTYPE;
  v_existing_by TEXT;
BEGIN
  -- Before anything is validated or written: if this exact attempt already
  -- succeeded, hand back what it returned.
  v_replay := app.idempotent_replay(p_idempotency_key, 'record_collection');
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;

  SELECT business_id, customer_id, installment_amount, effective_date, remaining_balance
    INTO v_business_id, v_loan_customer, v_installment, v_effective_date, v_owed
  FROM loans
  WHERE loan_id = p_loan_id
  FOR UPDATE;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT app.own_active_agent_membership_permits(p_collected_by_membership_id, 'can_collect_payments', v_business_id)
     AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record collections on this loan' USING ERRCODE = '42501';
  END IF;

  IF app.business_id_for_membership(p_collected_by_membership_id) <> v_business_id THEN
    RAISE EXCEPTION 'Collector is not a member of this business' USING ERRCODE = '42501';
  END IF;

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

  -- Already answered today. Whoever recorded it, and however this call was
  -- flagged: a second row is not a correction.
  SELECT * INTO v_existing
    FROM collections c
   WHERE c.loan_id = p_loan_id
     AND c.business_date = p_business_date
     AND c.deleted_at IS NULL
   ORDER BY c.entry_timestamp DESC
   LIMIT 1;

  IF v_existing.collection_id IS NOT NULL THEN
    SELECT p.full_name INTO v_existing_by
      FROM business_members bm
      JOIN persons p ON p.person_id = bm.person_id
     WHERE bm.membership_id = v_existing.collected_by_membership_id;

    -- Nothing was written, so this is not stored against the idempotency key.
    RETURN json_build_object(
      'status',           'already_recorded',
      'collection_id',    v_existing.collection_id,
      'receipt_number',   v_existing.receipt_number,
      'collected_amount', v_existing.collected_amount,
      'result_type',      v_existing.result_type,
      'recorded_by',      COALESCE(v_existing_by, 'another member'),
      'mine',             app.membership_belongs_to_current_person(
                            v_existing.collected_by_membership_id)
    );
  END IF;

  v_result_type := p_result_type;
  v_difference := p_difference_amount;
  IF v_result_type IS NULL THEN
    -- Measured against what is OWED, not against one instalment. The
    -- balance already carries any penalty, because apply_loan_penalty adds
    -- it there.
    v_difference := p_collected_amount - COALESCE(v_owed, 0);
    IF v_difference > 0 THEN
      v_result_type := 'Excess';
    ELSIF p_collected_amount < COALESCE(v_owed, 0) THEN
      v_result_type := 'Partial';
    ELSE
      v_result_type := 'Full';
    END IF;
  END IF;
  IF v_difference IS NULL THEN v_difference := 0; END IF;
  -- Carried, not refused. Somebody handed over more than they owed; the book
  -- records it and holds the surplus as an advance unless told otherwise.
  IF v_result_type = 'Excess' AND p_excess_disposition IS NULL THEN
    p_excess_disposition := 'Advance';
  END IF;

  v_receipt := 'RCT-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO collections (
    loan_id, customer_id, receipt_number, collected_amount, payer_type, payer_name,
    guarantor_id, collected_by_membership_id, business_date, result_type,
    difference_amount, excess_disposition, remarks
  ) VALUES (
    p_loan_id, p_customer_id, v_receipt, p_collected_amount, p_payer_type,
    CASE WHEN p_payer_type = 'Others' THEN NULLIF(btrim(p_payer_name), '') END,
    p_guarantor_id, p_collected_by_membership_id, p_business_date, v_result_type,
    v_difference, p_excess_disposition, p_remarks
  ) RETURNING collection_id INTO v_collection_id;

  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
      VALUES (v_collection_id, (v_split->>'payment_mode')::payment_mode_enum, (v_split->>'amount')::DECIMAL(14,0));
    END LOOP;
  ELSE
    INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
    VALUES (v_collection_id, 'Cash', p_collected_amount);
  END IF;

  UPDATE loans
  SET remaining_balance = GREATEST(remaining_balance - p_collected_amount, 0), updated_at = now()
  WHERE loan_id = p_loan_id;

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

  v_result := json_build_object(
    'status', 'saved',
    'collection_id', v_collection_id,
    'receipt_number', v_receipt,
    'result_type', v_result_type,
    'collected_amount', p_collected_amount,
    'remaining_balance', (SELECT remaining_balance FROM loans WHERE loan_id = p_loan_id)
  );

  PERFORM app.idempotent_store(
    p_idempotency_key, 'record_collection', v_result, v_business_id);

  RETURN v_result;
END;
$function$;

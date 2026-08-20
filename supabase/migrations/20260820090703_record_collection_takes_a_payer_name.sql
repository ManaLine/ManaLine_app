-- Who actually handed the money over, when it was neither the customer nor a
-- registered guarantor. Appended so every existing caller is untouched, and
-- the old signature is dropped so PostgREST is not left choosing between two
-- overloads.
DROP FUNCTION IF EXISTS app.record_collection(
  uuid, uuid, numeric, payer_type_enum, date, uuid, uuid,
  collection_result_type_enum, numeric, excess_disposition_enum, text, json, boolean);

CREATE OR REPLACE FUNCTION app.record_collection(
  p_loan_id uuid,
  p_customer_id uuid,
  p_collected_amount numeric,
  p_payer_type payer_type_enum,
  p_business_date date,
  p_collected_by_membership_id uuid,
  p_guarantor_id uuid DEFAULT NULL,
  p_result_type collection_result_type_enum DEFAULT NULL,
  p_difference_amount numeric DEFAULT NULL,
  p_excess_disposition excess_disposition_enum DEFAULT NULL,
  p_remarks text DEFAULT NULL,
  p_splits json DEFAULT NULL,
  p_confirm_duplicate boolean DEFAULT false,
  p_payer_name varchar DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
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
  SELECT business_id, customer_id, installment_amount, effective_date
    INTO v_business_id, v_loan_customer, v_installment, v_effective_date
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
    loan_id, customer_id, receipt_number, collected_amount, payer_type, payer_name,
    guarantor_id, collected_by_membership_id, business_date, result_type,
    difference_amount, excess_disposition, remarks
  ) VALUES (
    p_loan_id, p_customer_id, v_receipt, p_collected_amount, p_payer_type,
    -- Only meaningful for Others; storing it against Customer would put a
    -- second name on a payment the customer made themselves.
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

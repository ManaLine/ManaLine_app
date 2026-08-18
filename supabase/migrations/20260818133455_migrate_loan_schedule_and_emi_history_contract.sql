-- Two loan-level rules the customers grid needs.
--
-- 1. A cut-off loan's schedule starts from where the customer actually IS, not
--    from the issue date. Seeding at the issue date invents one missed payment
--    for every instalment already paid - hundreds of phantom arrears across a
--    real book.
--
--       next due = issue + (CEIL(paid / instalment) + 1) x period
--
-- 2. Typed balance vs EMI history. A row may carry either or both. Both is the
--    useful case and also the dangerous one: the loan used to be created at the
--    typed balance and then have every historical instalment replayed against
--    it, so the balance came out at typed - SUM(history). Now, when history is
--    given, the loan opens UNPAID and the replay derives the balance; a typed
--    balance is checked against it and disagreement rejects the row rather than
--    quietly picking one of the two numbers.

CREATE OR REPLACE FUNCTION app.migrate_loan(
  p_customer_id uuid,
  p_business_id uuid,
  p_amount_given numeric,
  p_repayment_amount numeric,
  p_remaining_balance numeric,
  p_effective_date date,
  p_repayment_type repayment_frequency_enum,
  p_installment_amount numeric,
  p_grace_period_days integer DEFAULT 0,
  p_processing_fee numeric DEFAULT 0,
  p_collection_agent_membership_id uuid DEFAULT NULL::uuid
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_locked BOOLEAN;
  v_given DECIMAL(14,0) := CEIL(p_amount_given);
  v_repay DECIMAL(14,0) := CEIL(p_repayment_amount);
  v_remain DECIMAL(14,0) := CEIL(p_remaining_balance);
  v_fee DECIMAL(14,0) := CEIL(COALESCE(p_processing_fee, 0));
  v_inst DECIMAL(14,0) := CEIL(p_installment_amount);
  v_collected DECIMAL(14,0);
  v_interest DECIMAL(14,0);
  v_status loan_status_enum;
  v_agent_membership UUID;
  v_loan_id UUID;
  v_loan_number VARCHAR(30);
  v_interval INTERVAL;
  v_n INT;
  v_due DATE;
  v_left DECIMAL(14,0);
  v_amt DECIMAL(14,0);
  i INT;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(
               p_collection_agent_membership_id, 'can_migrate_records', p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to enter pre-existing records for this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is locked for this business. Reopen migration before entering pre-existing records.'
      USING ERRCODE = '23514';
  END IF;

  IF v_repay <= 0 OR v_given <= 0 OR v_inst <= 0 THEN
    RAISE EXCEPTION 'Amount Given, Repayment Amount and Installment Amount must all be greater than zero'
      USING ERRCODE = '23514';
  END IF;
  IF v_remain < 0 OR v_remain > v_repay THEN
    RAISE EXCEPTION 'Remaining Balance must be between 0 and the Repayment Amount (%)', v_repay
      USING ERRCODE = '23514';
  END IF;
  IF v_given + v_fee > v_repay THEN
    RAISE EXCEPTION 'Amount Given plus Processing Fee (%) cannot exceed the Repayment Amount (%) - that would make interest negative',
      v_given + v_fee, v_repay USING ERRCODE = '23514';
  END IF;

  v_agent_membership := p_collection_agent_membership_id;
  IF v_agent_membership IS NULL THEN
    v_agent_membership := app.covering_agent_membership_id(p_customer_id);
  END IF;
  IF v_agent_membership IS NULL THEN
    SELECT bm.membership_id INTO v_agent_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.business_id = p_business_id
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
      AND bm.person_id = b.owner_person_id
    LIMIT 1;
  END IF;
  IF v_agent_membership IS NULL THEN
    RAISE EXCEPTION 'No collecting agent could be determined for this loan. Agents are assigned to operating areas, not to customers - assign an agent to the area that covers this customer''s village first.'
      USING ERRCODE = '23502';
  END IF;

  v_collected := v_repay - v_remain;
  v_interest  := v_repay - v_given - v_fee;
  v_status    := (CASE WHEN v_remain <= 0 THEN 'Closed' ELSE 'Active' END)::loan_status_enum;

  v_interval := CASE p_repayment_type
                  WHEN 'Daily'   THEN INTERVAL '1 day'
                  WHEN 'Weekly'  THEN INTERVAL '7 days'
                  ELSE                INTERVAL '1 month'
                END;

  v_n := GREATEST(CEIL(v_remain::numeric / v_inst)::INT, 0);

  v_loan_number := 'LN-MIG-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO loans (
    loan_number, customer_id, business_id, repayment_amount, interest_amount,
    processing_fee, repayment_type, duration_value, installment_amount,
    grace_period_days, remaining_balance, collection_agent_membership_id, effective_date,
    loan_status, issue_business_date, live_photo_url
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, v_repay, v_interest,
    v_fee, p_repayment_type, v_n, v_inst,
    COALESCE(p_grace_period_days, 0), v_remain, v_agent_membership, p_effective_date,
    v_status,
    p_effective_date,
    'migrated:pre-existing-loan:no-live-photo'
  ) RETURNING loan_id INTO v_loan_id;

  -- Where the customer actually is, counted in instalments already paid.
  v_due := (p_effective_date
            + ((CEIL(v_collected::numeric / v_inst)::INT + 1) * v_interval))::date;
  v_left := v_remain;
  i := 1;
  WHILE v_left > 0 LOOP
    v_amt := LEAST(v_inst, v_left);
    INSERT INTO loan_schedule (loan_id, installment_number, due_date, installment_amount, status)
    VALUES (v_loan_id, i, v_due, v_amt, 'Pending');
    v_left := v_left - v_amt;
    v_due := (v_due + v_interval)::date;
    i := i + 1;
  END LOOP;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    p_business_id, app.current_person_id(), 'Other Admin Event', 'loan_migrated', 0,
    v_loan_id,
    json_build_object('amount_given', v_given, 'repayment_amount', v_repay,
                      'remaining_balance', v_remain, 'collected', v_collected,
                      'interest_amount', v_interest, 'effective_date', p_effective_date),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'loan_id', v_loan_id, 'loan_number', v_loan_number,
    'collected', v_collected, 'interest_amount', v_interest,
    'installments_created', GREATEST(i - 1, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION app.import_migrated_loans(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_locked   BOOLEAN;
  v_row      json;
  v_index    INT := 0;
  v_ok       INT := 0;
  v_errors   json[] := '{}';
  v_msg      TEXT;
  v_repay    NUMERIC;
  v_typed    NUMERIC;
  v_emi      NUMERIC;
  v_derived  NUMERIC;
  v_opening  NUMERIC;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.agent_permission(p_business_id, 'can_migrate_records') THEN
    RAISE EXCEPTION 'Not authorized to import records into this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked
    FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  -- BR-159. Once the book is live, historical entry is closed; importing past
  -- that point would rewrite balances the business has already traded on.
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    BEGIN
      v_repay := (v_row ->> 'repayment_amount')::NUMERIC;
      v_typed := (v_row ->> 'remaining_balance')::NUMERIC;
      v_emi   := (v_row ->> 'emi_total')::NUMERIC;

      IF v_emi IS NOT NULL THEN
        -- History given: the loan opens unpaid and the replayed instalments
        -- take it down. Otherwise the replay would subtract from an already
        -- reduced balance and land at typed - SUM(history).
        v_derived := v_repay - v_emi;
        IF v_derived < 0 THEN
          RAISE EXCEPTION 'The instalment history adds up to % but the loan is only %.',
            v_emi, v_repay;
        END IF;
        IF v_typed IS NOT NULL AND v_typed <> v_derived THEN
          RAISE EXCEPTION 'Remaining balance is typed as % but the instalment history gives % (repayment % less % paid). Fix whichever is wrong.',
            v_typed, v_derived, v_repay, v_emi;
        END IF;
        v_opening := v_repay;
      ELSE
        v_opening := v_typed;
      END IF;

      PERFORM app.migrate_loan(
        (v_row ->> 'customer_id')::UUID,
        p_business_id,
        (v_row ->> 'amount_given')::NUMERIC,
        v_repay,
        v_opening,
        (v_row ->> 'effective_date')::DATE,
        (v_row ->> 'repayment_type')::repayment_frequency_enum,
        (v_row ->> 'installment_amount')::NUMERIC,
        COALESCE((v_row ->> 'grace_period_days')::INT, 0),
        COALESCE((v_row ->> 'processing_fee')::NUMERIC, 0),
        NULLIF(v_row ->> 'collection_agent_membership_id', '')::UUID
      );
      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Captured, not swallowed: the message is carried out to the Owner and
      -- the whole import is refused below. A cast failure lands here too, so
      -- "31-02-2026" is reported as a bad row rather than killing the sheet.
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index,
        'customer_id', v_row ->> 'customer_id',
        'error', v_msg
      );
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0,
      'failed', array_length(v_errors, 1),
      'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object('imported', v_ok, 'failed', 0, 'total', v_index);
END;
$$;

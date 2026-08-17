-- Pre-existing-business migration, part C: identities become migration-aware,
-- and two fixes.

-- ---------------------------------------------------------------------------
-- profit_share_accrued: ROUND() was being handed the json ->> text operand.
-- plpgsql does not type-check a body at CREATE time, so this applied cleanly
-- and would have failed on first call.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.profit_share_accrued(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inv RECORD;
  v_days INT;
  v_profit numeric;
  v_base numeric;
BEGIN
  SELECT i.investment_id, i.business_id, i.roi_rate,
         i.profit_share_percent, i.profit_share_effective_date
    INTO v_inv
    FROM investments i
   WHERE i.investment_id = p_investment_id AND i.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF NOT app.is_owner(v_inv.business_id) AND NOT app.is_active_investor(v_inv.business_id) THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;
  IF v_inv.profit_share_percent IS NULL OR v_inv.profit_share_effective_date IS NULL THEN
    RETURN 0;
  END IF;

  -- Declared and paid on the same day is no accrual at all.
  v_days := GREATEST(p_as_of - v_inv.profit_share_effective_date, 0);
  IF v_days = 0 THEN
    RETURN 0;
  END IF;

  v_profit := (app.migration_profit_summary(v_inv.business_id, p_as_of) ->> 'profit')::numeric;
  v_base := v_profit * v_inv.profit_share_percent / 100;
  IF v_base <= 0 THEN
    RETURN 0;
  END IF;

  -- ROI is Rupees per 100 per MONTH; daily is that over a 30-day month, and
  -- money rounds up to whole rupees (numeric(_,0) columns cannot hold paise).
  RETURN CEIL(v_base * (v_inv.roi_rate / 100) / 30 * v_days);
END;
$$;

-- ---------------------------------------------------------------------------
-- bulk_import_identities: migration-aware
--
-- Two changes. It declares itself a migration import for the duration of the
-- transaction, which is what lets persons with neither phone nor Aadhaar
-- through persons_mlti_needs_hard_key and stamps the membership as
-- Migration/Pre-Existing. And it now resolves a named village to a real
-- locations row rather than the 'Unconfirmed' placeholder - the Areas &
-- Villages page has already created every village named in this sheet.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.bulk_import_identities(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_locked      BOOLEAN;
  v_row         json;
  v_index       INT := 0;
  v_ok          INT := 0;
  v_errors      json[] := '{}';
  v_created     json[] := '{}';
  v_msg         TEXT;
  v_type        TEXT;
  v_location    UUID;
  v_pin         VARCHAR;
  v_village     TEXT;
  v_agent_id    UUID;
  v_investor_id UUID;
  v_customer_id UUID;
  v_mlid        VARCHAR;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to import records into this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;

  -- Transaction-local: it dies with this statement, so nothing outside a
  -- migration import can ever be stamped as migrated.
  PERFORM set_config('app.migration_import', 'on', true);

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;

    IF COALESCE(v_row ->> 'dedupe_decision', '') = 'ignore' THEN
      CONTINUE;
    END IF;

    BEGIN
      v_type := v_row ->> 'user_type';
      v_mlid := NULL;

      IF v_type = 'Customer' THEN
        v_location := NULL;
        v_pin := regexp_replace(COALESCE(v_row ->> 'pin_code', ''), '[^0-9]', '', 'g');
        v_village := NULLIF(btrim(COALESCE(v_row ->> 'village', '')), '');

        IF v_pin <> '' AND v_village IS NOT NULL THEN
          SELECT location_id INTO v_location
            FROM locations
           WHERE pin_code = v_pin AND lower(village_town_name) = lower(v_village);
          IF v_location IS NULL THEN
            RAISE EXCEPTION 'Village "%" (PIN %) has not been added yet - add it on the Areas & Villages step first.',
              v_village, v_pin USING ERRCODE = 'P0002';
          END IF;
        ELSIF v_pin <> '' THEN
          v_location := app.find_or_create_location(v_pin::varchar);
        END IF;

        v_customer_id := app.register_new_customer(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', ''),
          NULLIF(v_row ->> 'door_no', ''),
          NULLIF(v_pin, '')::varchar,
          v_location
        );
        SELECT p.mlid INTO v_mlid FROM customers c JOIN persons p ON p.person_id = c.person_id
          WHERE c.customer_id = v_customer_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Customer', 'customer_id', v_customer_id, 'mlid', v_mlid
        );

      ELSIF v_type = 'Agent' THEN
        v_agent_id := app.register_new_agent(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', '')
        );

        UPDATE business_members bm
           SET membership_status = 'Active', verification_status = 'Not Required'
          FROM agents a
         WHERE a.agent_id = v_agent_id AND bm.membership_id = a.membership_id;

        SELECT p.mlid INTO v_mlid FROM agents a JOIN persons p ON p.person_id = a.person_id
          WHERE a.agent_id = v_agent_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Agent', 'agent_id', v_agent_id, 'mlid', v_mlid
        );

      ELSIF v_type = 'Investor' THEN
        v_investor_id := app.register_new_investor(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', '')
        );
        SELECT p.mlid INTO v_mlid FROM investors i JOIN persons p ON p.person_id = i.person_id
          WHERE i.investor_id = v_investor_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Investor', 'investor_id', v_investor_id, 'mlid', v_mlid
        );

      ELSE
        RAISE EXCEPTION 'Unknown User Type "%": must be Agent, Customer or Investor', v_type;
      END IF;

      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index, 'full_name', v_row ->> 'full_name', 'error', v_msg
      );
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0, 'failed', array_length(v_errors, 1), 'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object('imported', v_ok, 'total', v_index, 'created', array_to_json(v_created));
END;
$$;

-- ---------------------------------------------------------------------------
-- migrate_loan: the "no collecting agent" error named the wrong thing. Agents
-- are not assigned to customers; they are assigned to operating AREAS, and an
-- area holds villages. Telling the Owner to assign an agent to the customer
-- sends them looking for a control that does not exist.
-- ---------------------------------------------------------------------------
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

  v_left := v_remain;
  v_due := CURRENT_DATE;
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

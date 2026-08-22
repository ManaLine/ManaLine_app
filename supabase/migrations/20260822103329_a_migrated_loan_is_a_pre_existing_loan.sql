-- A migrated loan IS a pre-existing loan, and must say so.
--
-- migrate_loan never set is_pre_existing, so all 54 loans the wizard imported
-- for sri satyanarayana defaulted to false. recompute_agent_bf excludes
-- pre-existing loans on purpose -- "that cash never passed through this float"
-- -- so with the flag false it charged the collecting agent Rs 30,71,360 of an
-- old book as cash paid out of their pocket, and derived their BF at
-- MINUS Rs 21,73,960. The business BF then read that back through
-- recompute_business_bf, which nets agent holdings off the ledger closing.
--
-- The function already knew what it was writing: it stamps live_photo_url
-- 'migrated:pre-existing-loan:no-live-photo' three lines above. Only the
-- column was missing.
--
-- Signature unchanged, so CREATE OR REPLACE is safe -- a changed parameter
-- list would leave a second overload and PostgREST would answer 300.
CREATE OR REPLACE FUNCTION app.migrate_loan(
  p_customer_id uuid, p_business_id uuid, p_amount_given numeric,
  p_repayment_amount numeric, p_remaining_balance numeric, p_effective_date date,
  p_repayment_type repayment_frequency_enum, p_installment_amount numeric,
  p_grace_period_days integer DEFAULT 0, p_processing_fee numeric DEFAULT 0,
  p_collection_agent_membership_id uuid DEFAULT NULL::uuid
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    loan_status, issue_business_date, live_photo_url, is_pre_existing
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, v_repay, v_interest,
    v_fee, p_repayment_type, v_n, v_inst,
    COALESCE(p_grace_period_days, 0), v_remain, v_agent_membership, p_effective_date,
    v_status,
    p_effective_date,
    'migrated:pre-existing-loan:no-live-photo',
    -- The whole point of this function. Without it the agent's float is
    -- charged for money that was lent before the app existed.
    TRUE
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
$function$;

-- The rows already imported under the old behaviour. Identified by what
-- migrate_loan stamps on every row it writes, not by business, so any book
-- migrated before today is corrected too.
UPDATE loans SET is_pre_existing = true, updated_at = now()
 WHERE deleted_at IS NULL
   AND is_pre_existing = false
   AND (loan_number LIKE 'LN-MIG-%'
        OR live_photo_url = 'migrated:pre-existing-loan:no-live-photo');

-- BF is derived from those rows, so it has to be recomposed once they change.
DO $$
DECLARE b uuid;
BEGIN
  FOR b IN SELECT DISTINCT business_id FROM loans
            WHERE deleted_at IS NULL AND is_pre_existing
  LOOP
    PERFORM app.recompute_ledger_chain(b);
  END LOOP;
END $$;

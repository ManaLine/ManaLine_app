-- A penalty is an amount. Nothing else is asked.
--
-- apply_loan_penalty required p_penalty_option -- Flat Amount, % of Overdue
-- Installment, % of Remaining Balance -- before it would take a figure. The
-- Owner does not think in those terms at a doorstep: they decide the customer
-- owes another two hundred rupees, and that is the whole of it. Every one of
-- the three options ends in a rupee figure anyway, and the function already
-- CEILs whatever arrives.
--
-- The column stays, defaulted to 'Flat Amount', because penalty_entries has
-- history to keep readable and dropping an enum a live table records would be
-- a migration on a type for a field nobody fills in. What changes is that
-- nobody is asked.
--
-- DROP then CREATE, not CREATE OR REPLACE: p_penalty_option gains a default,
-- which is a changed parameter list. CREATE OR REPLACE would leave a second
-- function behind and PostgREST would answer HTTP 300 (PGRST203) because it
-- could not choose. Overload count is asserted at the end.
DROP FUNCTION IF EXISTS app.apply_loan_penalty(uuid, penalty_option_enum, numeric, date, numeric);

CREATE FUNCTION app.apply_loan_penalty(
  p_loan_id uuid,
  p_penalty_amount numeric,
  p_penalty_option penalty_option_enum DEFAULT 'Flat Amount',
  p_business_date date DEFAULT NULL,
  p_penalty_value numeric DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE
  v_loan_status loan_status_enum;
  v_balance DECIMAL(14,0);
  v_business_date DATE := COALESCE(p_business_date, CURRENT_DATE);
  v_eligible_from DATE;
  v_penalty_id UUID;
  v_business_id UUID;
  v_person_id BIGINT;
  v_loan_number VARCHAR(50);
  v_amount DECIMAL(14,0);
BEGIN
  IF NOT app.can_apply_penalty_on_loan(p_loan_id) THEN
    RAISE EXCEPTION 'Not authorized to apply a penalty on this loan' USING ERRCODE = '42501';
  END IF;
  IF p_penalty_amount IS NULL OR p_penalty_amount <= 0 THEN
    RAISE EXCEPTION 'Penalty amount must be greater than zero' USING ERRCODE = '23514';
  END IF;

  -- Ceiling to whole rupees, per the section 3 ROUNDING RULE. Every money
  -- column here is numeric(_,0); paise cannot be stored.
  v_amount := CEIL(p_penalty_amount);

  SELECT l.loan_status, l.remaining_balance, l.business_id, l.loan_number, c.person_id
  INTO v_loan_status, v_balance, v_business_id, v_loan_number, v_person_id
  FROM loans l
  JOIN customers c ON c.customer_id = l.customer_id
  WHERE l.loan_id = p_loan_id
  FOR UPDATE OF l;

  IF v_loan_status IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan_status IN ('Closed', 'Cancelled') THEN
    RAISE EXCEPTION 'Cannot apply a penalty to a % loan', v_loan_status USING ERRCODE = '23514';
  END IF;
  IF v_balance <= 0 THEN
    RAISE EXCEPTION 'Loan is fully repaid - no penalty can be applied' USING ERRCODE = '23514';
  END IF;

  v_eligible_from := app.loan_penalty_eligible_from(p_loan_id);
  IF v_eligible_from IS NULL THEN
    RAISE EXCEPTION 'Cannot assess overdue status: this loan has no repayment schedule'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_business_date < v_eligible_from THEN
    RAISE EXCEPTION 'Loan is not yet past its due date plus grace period - a penalty may be applied from % onwards', v_eligible_from
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO penalty_entries (
    loan_id, penalty_option, penalty_value, penalty_amount_applied,
    applied_by_person_id, business_date
  ) VALUES (
    p_loan_id, p_penalty_option, COALESCE(p_penalty_value, v_amount), v_amount,
    app.current_person_id(), v_business_date
  ) RETURNING penalty_id INTO v_penalty_id;

  -- The penalty is real money owed: it joins the balance, which is why a
  -- collection measured against remaining_balance already accounts for it.
  -- BR-206: the penalty is the only thing the customer is ever shown; the
  -- grace period itself stays internal.
  UPDATE loans
  SET remaining_balance = remaining_balance + v_amount,
      loan_status = 'Penalty',
      updated_at = now()
  WHERE loan_id = p_loan_id;

  INSERT INTO notifications (
    recipient_person_id, business_id, notification_type, message,
    related_entity_type, related_entity_uuid, is_read
  ) VALUES (
    v_person_id, v_business_id, 'Penalty Applied',
    'A penalty of ' || v_amount || ' has been applied to loan ' ||
      COALESCE(v_loan_number, '') || '. Your outstanding balance is now ' ||
      (v_balance + v_amount) || '.',
    'loan', p_loan_id, FALSE
  );

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, old_value, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event', 'loan_penalty', 0,
    p_loan_id,
    json_build_object('loan_status', v_loan_status, 'remaining_balance', v_balance),
    json_build_object('loan_status', 'Penalty', 'remaining_balance', v_balance + v_amount,
                      'penalty_option', p_penalty_option, 'penalty_amount', v_amount),
    v_business_date
  );

  RETURN v_penalty_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.apply_loan_penalty(uuid, numeric, penalty_option_enum, date, numeric)
  TO authenticated, service_role;

DO $$
DECLARE n INT;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
   WHERE s.nspname = 'app' AND p.proname = 'apply_loan_penalty';
  IF n <> 1 THEN
    RAISE EXCEPTION 'apply_loan_penalty has % overloads; PostgREST will answer HTTP 300', n;
  END IF;
END $$;

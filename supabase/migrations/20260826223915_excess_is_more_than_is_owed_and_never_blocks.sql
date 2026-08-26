-- Excess is paying more than is OWED, and it never blocks.
--
-- record_collection measured every payment against ONE instalment:
--
--     v_difference := p_collected_amount - v_installment;
--     IF v_difference > 0 THEN v_result_type := 'Excess';
--     IF Excess AND p_excess_disposition IS NULL THEN RAISE 23514
--
-- So a customer seventeen weeks behind, handing over two instalments, was an
-- "excess payment" -- and the app refused to record it until somebody said
-- where the extra should go. The form meanwhile classified against the
-- ARREARS, so it never showed that question, and the Agent got
-- "Something went wrong" for every amount above one instalment. That is the
-- collect failure reported today; it has been there since the function was
-- written.
--
-- A penalty joins remaining_balance when it is applied, so what is owed
-- already includes it. The threshold is therefore simply the balance:
--
--   * below it   -> Partial. Money off a loan that still runs.
--   * exactly    -> Full. The loan is settled.
--   * above it   -> Excess, and only then.
--
-- And it does not block. A customer standing there with cash is not a
-- validation error: the surplus is carried as an Advance unless the caller
-- says otherwise, which is what an Owner does with it in practice anyway.
-- Refusing the record does not make the money go away -- it just means the
-- book does not know about it.
DO $$
DECLARE
  v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'record_collection';

  -- 1. a variable to hold what is owed
  v_src := replace(v_src,
    '  v_installment DECIMAL(14,0);',
    '  v_installment DECIMAL(14,0);
  v_owed DECIMAL(14,0);');

  -- 2. read the balance alongside the rest of the loan, under the same lock
  v_src := replace(v_src,
    'SELECT business_id, customer_id, installment_amount, effective_date
    INTO v_business_id, v_loan_customer, v_installment, v_effective_date',
    'SELECT business_id, customer_id, installment_amount, effective_date, remaining_balance
    INTO v_business_id, v_loan_customer, v_installment, v_effective_date, v_owed');

  -- 3. classify against what is owed, and never refuse
  v_src := replace(v_src,
    '    v_difference := p_collected_amount - v_installment;
    IF v_difference > 0 THEN
      v_result_type := ''Excess'';
    ELSIF v_difference < 0 THEN
      v_result_type := ''Partial'';
    ELSE
      v_result_type := ''Full'';
    END IF;
  END IF;
  IF v_difference IS NULL THEN v_difference := 0; END IF;
  IF v_result_type = ''Excess'' AND p_excess_disposition IS NULL THEN
    RAISE EXCEPTION ''An excess payment needs a disposition (how the extra was returned or carried)'' USING ERRCODE = ''23514'';
  END IF;',
    '    -- Measured against what is OWED, not against one instalment. The
    -- balance already carries any penalty, because apply_loan_penalty adds
    -- it there.
    v_difference := p_collected_amount - COALESCE(v_owed, 0);
    IF v_difference > 0 THEN
      v_result_type := ''Excess'';
    ELSIF p_collected_amount < COALESCE(v_owed, 0) THEN
      v_result_type := ''Partial'';
    ELSE
      v_result_type := ''Full'';
    END IF;
  END IF;
  IF v_difference IS NULL THEN v_difference := 0; END IF;
  -- Carried, not refused. Somebody handed over more than they owed; the book
  -- records it and holds the surplus as an advance unless told otherwise.
  IF v_result_type = ''Excess'' AND p_excess_disposition IS NULL THEN
    p_excess_disposition := ''Advance'';
  END IF;');

  IF position('v_owed' in v_src) = 0
     OR position('p_excess_disposition := ''Advance''' in v_src) = 0 THEN
    RAISE EXCEPTION 'The patch did not apply: record_collection no longer contains the text it matched on.';
  END IF;

  EXECUTE v_src;
END $$;

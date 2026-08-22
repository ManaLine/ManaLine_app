-- Re-uploading a step 4 sheet must not import its loans again.
--
-- The idempotency key protects a RETRY of one tap. It does nothing for a
-- deliberate second upload, which is the normal way to finish a partly-failed
-- import: the Owner picks the same file, a fresh key is minted, and 54 loans
-- land on top of the 54 already there. That is the 22 Aug defect returning
-- through the door left open for fixing it.
--
-- So the sheet is read as the TARGET STATE, exactly as the instalment replay
-- now is: a row whose loan is already on the book is skipped, not imported.
--
-- IDENTITY: same customer, same issue date, same repayment amount, not
-- soft-deleted. Not customer alone — a customer can hold two live loans, and
-- this business has one who does (Garikipati Kamala Reddy, two loans on
-- identical terms). Not the amount alone either. Two loans to one customer on
-- one day for the same amount is the one case this cannot tell from a repeat;
-- it is not present in any real book seen so far, and silently importing a
-- second copy of a whole sheet is by far the worse failure.
--
-- Skipped rows are counted and returned so the screen can say so. A run that
-- reports "0 imported" with no explanation reads as a failure.
CREATE OR REPLACE FUNCTION app.import_migrated_loans(
  p_business_id uuid,
  p_rows json,
  p_idempotency_key text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_locked   BOOLEAN;
  v_row      json;
  v_index    INT := 0;
  v_ok       INT := 0;
  v_skipped  INT := 0;
  v_errors   json[] := '{}';
  v_msg      TEXT;
  v_repay    NUMERIC;
  v_typed    NUMERIC;
  v_emi      NUMERIC;
  v_derived  NUMERIC;
  v_opening  NUMERIC;
  v_replay   json;
  v_result   json;
  v_exists   BOOLEAN;
BEGIN
  -- Before any authorisation or writing: if this exact import already ran,
  -- hand back what it returned.
  v_replay := app.idempotent_replay(p_idempotency_key, 'import_migrated_loans');
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;

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

      SELECT EXISTS (
        SELECT 1 FROM loans
         WHERE business_id    = p_business_id
           AND customer_id    = (v_row ->> 'customer_id')::UUID
           AND effective_date = (v_row ->> 'effective_date')::DATE
           AND repayment_amount = v_repay
           AND deleted_at IS NULL
      ) INTO v_exists;

      IF v_exists THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

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
    -- Not stored against the key: nothing was kept, so a corrected re-upload
    -- must be allowed to run.
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0,
      'failed', array_length(v_errors, 1),
      'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  v_result := json_build_object(
    'imported', v_ok, 'skipped', v_skipped, 'failed', 0, 'total', v_index);
  PERFORM app.idempotent_store(
    p_idempotency_key, 'import_migrated_loans', v_result, p_business_id);
  RETURN v_result;
END;
$$;

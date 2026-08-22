-- Importing a book twice must be impossible, not merely unlikely.
--
-- WHAT HAPPENED, 22 Aug 2026, live: step 4 of the onboarding wizard sent 54
-- loans (5,391 schedule rows behind them). The app's per-tap deadline is 20
-- seconds; the server needed longer. The Owner saw "The server did not
-- respond" and pressed Retry — while the first import was still completing.
-- Result: 108 loans, 612 collections, a line balance of 57,90,300 against a
-- true 30,04,900, and a day ledger cascaded to minus 8,20,320. Nothing on
-- screen ever said anything was wrong.
--
-- The deadline was raised for bulk work (kManaBulkTimeout), but a longer wait
-- is not a guarantee — a retry is always possible and always will be. This is
-- the guarantee: the same key replays the first call's result instead of
-- writing again.
--
-- A REJECTED import is deliberately NOT stored against the key. Nothing was
-- kept, so the Owner must be able to fix the sheet and upload again under the
-- same key.
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
  v_errors   json[] := '{}';
  v_msg      TEXT;
  v_repay    NUMERIC;
  v_typed    NUMERIC;
  v_emi      NUMERIC;
  v_derived  NUMERIC;
  v_opening  NUMERIC;
  v_replay   json;
  v_result   json;
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

  v_result := json_build_object('imported', v_ok, 'failed', 0, 'total', v_index);
  PERFORM app.idempotent_store(
    p_idempotency_key, 'import_migrated_loans', v_result, p_business_id);
  RETURN v_result;
END;
$$;

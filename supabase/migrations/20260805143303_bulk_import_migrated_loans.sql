-- P3: bulk import of pre-existing loans, for onboarding a business that
-- already has a book.
--
-- This is a FEEDER for app.migrate_loan, not a second way to enter a loan.
-- OW-018 already enters pre-existing loans one at a time through that
-- function, and it is the function that knows the rules -- amount_given vs
-- repayment vs remaining_balance, the generated column, the effective date.
-- A bulk path with its own validation would be a second set of rules for
-- entering the same historical loan, and two implementations of a money rule
-- drift. So every row here goes through migrate_loan exactly as if the Owner
-- had typed it.
--
-- ALL-OR-NOTHING, AND ALL ERRORS AT ONCE. Those pull in opposite directions:
-- stopping at the first bad row is atomic but tells the Owner about mistake 1
-- of 40, so they fix one, re-upload, and discover mistake 2. The loop below
-- wraps each row in its own BEGIN/EXCEPTION block -- an implicit subtransaction
-- -- so a failing row is captured and the loop continues collecting. If ANY row
-- failed, the function raises at the end, which rolls back every row that did
-- succeed, and hands back the complete list of problems. Nothing is imported
-- until the whole sheet is clean.
CREATE OR REPLACE FUNCTION app.import_migrated_loans(
  p_business_id uuid,
  p_rows        json
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_locked   BOOLEAN;
  v_row      json;
  v_index    INT := 0;
  v_ok       INT := 0;
  v_errors   json[] := '{}';
  v_msg      TEXT;
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
      PERFORM app.migrate_loan(
        (v_row ->> 'customer_id')::UUID,
        p_business_id,
        (v_row ->> 'amount_given')::NUMERIC,
        (v_row ->> 'repayment_amount')::NUMERIC,
        (v_row ->> 'remaining_balance')::NUMERIC,
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
    -- Rolls back every successful row above. The payload is JSON so the client
    -- can render a per-row list instead of one opaque string.
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
$function$;

REVOKE ALL ON FUNCTION app.import_migrated_loans(uuid, json) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.import_migrated_loans(uuid, json) TO authenticated;

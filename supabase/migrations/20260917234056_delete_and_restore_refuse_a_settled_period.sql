-- The refusal itself, on both directions.
--
-- app.soft_delete_record and app.restore_record move the same money opposite
-- ways and then call the same app.recompute_ledger_chain, so a guard on one
-- alone would leave the identical hole facing the other way: delete while the
-- period is open, wait for it to be settled, restore.
--
-- The check sits immediately after the authorization and before anything is
-- written, so a refusal changes nothing at all -- no deleted_at, no balance,
-- no audit row. The earlier position mattered: the recompute is at the END of
-- both functions, and a guard placed there would have already rewritten the
-- loan's balance before refusing. The DO block below asserts the ordering.
--
-- Both signatures are unchanged, so these are true CREATE OR REPLACEs.

CREATE OR REPLACE FUNCTION app.soft_delete_record(
  p_entity    text,
  p_record_id uuid,
  p_reason    text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID;
  v_membership_id UUID;
  v_already TIMESTAMP;
  v_loan_id UUID;
  v_amount NUMERIC(14,0);
  v_agent UUID;
  v_locked TEXT;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to delete records in this business'
      USING ERRCODE = '42501';
  END IF;

  -- A signed-off period does not change behind somebody's back.
  v_locked := app.locked_period_reason(
                v_business_id,
                app.deletable_business_date(p_entity, p_record_id));
  IF v_locked IS NOT NULL THEN
    RAISE EXCEPTION 'This entry cannot be deleted. %', v_locked
      USING ERRCODE = '23514';
  END IF;

  SELECT membership_id INTO v_membership_id
  FROM business_members
  WHERE business_id = v_business_id
    AND person_id = app.current_person_id()
    AND membership_status = 'Active'
  ORDER BY CASE role WHEN 'Owner' THEN 0 ELSE 1 END
  LIMIT 1;

  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_already USING p_record_id;
  IF v_already IS NOT NULL THEN
    RAISE EXCEPTION 'This record is already deleted' USING ERRCODE = '23514';
  END IF;

  EXECUTE format(
    'UPDATE %I SET deleted_at = now(), deleted_by_membership_id = $2, delete_reason = $3 WHERE %I = $1',
    v_table, v_pk)
    USING p_record_id, v_membership_id, p_reason;

  -- The money goes back to the loan it came off.
  IF p_entity = 'collection' THEN
    SELECT c.loan_id, c.collected_amount INTO v_loan_id, v_amount
      FROM collections c WHERE c.collection_id = p_record_id;
    UPDATE loans
       SET remaining_balance = LEAST(remaining_balance + v_amount, repayment_amount),
           updated_at = now()
     WHERE loan_id = v_loan_id;
  END IF;

  PERFORM app.recompute_ledger_chain(v_business_id);

  -- Every agent in the business, because BF is derived and the deleted row is
  -- no longer one of the rows it derives from.
  FOR v_agent IN
    SELECT bm.membership_id FROM business_members bm
     WHERE bm.business_id = v_business_id AND bm.role = 'Agent'
  LOOP
    PERFORM app.recompute_agent_bf(v_agent);
  END LOOP;

  PERFORM app.recompute_business_bf(v_business_id);

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_soft_deleted', 0, p_record_id,
    json_build_object('reason', p_reason, 'table', v_table), CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'deleted',
    'entity', p_entity,
    'record_id', p_record_id,
    'recoverable_until', (now() + INTERVAL '30 days')::date
  );
END;
$function$;

CREATE OR REPLACE FUNCTION app.restore_record(
  p_entity    text,
  p_record_id uuid
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID; v_deleted_at TIMESTAMP;
  v_loan_id UUID;
  v_amount NUMERIC(14,0);
  v_agent UUID;
  v_locked TEXT;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to restore records in this business'
      USING ERRCODE = '42501';
  END IF;

  -- Putting a row back moves the same money the other way, into the same
  -- settled period. Guarding only the delete would leave the hole open in
  -- reverse: delete while open, restore after it is signed.
  v_locked := app.locked_period_reason(
                v_business_id,
                app.deletable_business_date(p_entity, p_record_id));
  IF v_locked IS NOT NULL THEN
    RAISE EXCEPTION 'This entry cannot be restored. %', v_locked
      USING ERRCODE = '23514';
  END IF;

  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_deleted_at USING p_record_id;
  IF v_deleted_at IS NULL THEN
    RAISE EXCEPTION 'This record is not deleted' USING ERRCODE = '23514';
  END IF;

  EXECUTE format(
    'UPDATE %I SET deleted_at = NULL, deleted_by_membership_id = NULL, delete_reason = NULL WHERE %I = $1',
    v_table, v_pk)
    USING p_record_id;

  -- The mirror of the delete: a restored receipt takes its money back off the
  -- loan.
  IF p_entity = 'collection' THEN
    SELECT c.loan_id, c.collected_amount INTO v_loan_id, v_amount
      FROM collections c WHERE c.collection_id = p_record_id;
    UPDATE loans
       SET remaining_balance = GREATEST(remaining_balance - v_amount, 0),
           updated_at = now()
     WHERE loan_id = v_loan_id;
  END IF;

  PERFORM app.recompute_ledger_chain(v_business_id);

  FOR v_agent IN
    SELECT bm.membership_id FROM business_members bm
     WHERE bm.business_id = v_business_id AND bm.role = 'Agent'
  LOOP
    PERFORM app.recompute_agent_bf(v_agent);
  END LOOP;

  PERFORM app.recompute_business_bf(v_business_id);

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_restored', 0, p_record_id,
    json_build_object('table', v_table), CURRENT_DATE
  );

  RETURN json_build_object('status', 'restored', 'entity', p_entity, 'record_id', p_record_id);
END;
$function$;

DO $$
DECLARE v_n INT; v_src TEXT;
BEGIN
  FOR v_n IN
    SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='app' AND p.proname IN ('soft_delete_record','restore_record')
     GROUP BY p.proname
  LOOP
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'a delete RPC gained an overload (%)', v_n;
    END IF;
  END LOOP;

  -- The guard must come BEFORE the recompute in both, or a refusal would
  -- already have rewritten the chain.
  FOR v_src IN
    SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='app' AND p.proname IN ('soft_delete_record','restore_record')
  LOOP
    IF position('locked_period_reason' in v_src) = 0 THEN
      RAISE EXCEPTION 'a delete RPC no longer checks for a settled period';
    END IF;
    IF position('locked_period_reason' in v_src)
       > position('recompute_ledger_chain' in v_src) THEN
      RAISE EXCEPTION 'the settled-period check runs after the recompute';
    END IF;
  END LOOP;
END $$;

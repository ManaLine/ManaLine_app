-- Soft-deleting a collection took the receipt away and left the credit.
--
-- app.record_collection subtracts the amount from loans.remaining_balance;
-- nothing anywhere adds it back. soft_delete_record set deleted_at, recomputed
-- day_ledger and the business BF, and left the loan exactly as it was -- so a
-- customer whose payment was deleted went on being shown as having paid it,
-- while the day's ledger said the money was never taken. The two halves of the
-- book disagreed, quietly, which is the failure this project treats as worse
-- than a crash. restore_record had the mirror image of the same gap.
--
-- The loan's balance is the one money figure in this schema that is NOT
-- derived -- there is no recompute_loan_balance, by design, because one
-- remaining_balance per loan with no payment waterfall is the whole model. So
-- it has to be moved explicitly, and this is the only place a delete can do
-- it.
--
-- Capped both ways: back up to the repayment amount and no further, down to
-- zero and no further, so a double-applied delete cannot invent a balance
-- larger than the loan or smaller than nothing.
--
-- Agent BF is recomposed rather than adjusted. It is derived from live rows
-- (app.recompute_agent_bf), and the deleted collection is no longer one --
-- but nothing was calling it here, so an Agent's cash in hand still counted a
-- collection that had been deleted underneath them.
--
-- p_reason keeps its DEFAULT NULL: dropping the default is a signature change,
-- and this codebase has had PostgREST answer HTTP 300 over one four times.
CREATE OR REPLACE FUNCTION app.soft_delete_record(
  p_entity TEXT, p_record_id UUID, p_reason TEXT DEFAULT NULL::text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID;
  v_membership_id UUID;
  v_already TIMESTAMP;
  v_loan_id UUID;
  v_amount NUMERIC(14,0);
  v_agent UUID;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to delete records in this business'
      USING ERRCODE = '42501';
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
$$;

CREATE OR REPLACE FUNCTION app.restore_record(p_entity TEXT, p_record_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID; v_deleted_at TIMESTAMP;
  v_loan_id UUID;
  v_amount NUMERIC(14,0);
  v_agent UUID;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to restore records in this business'
      USING ERRCODE = '42501';
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
$$;

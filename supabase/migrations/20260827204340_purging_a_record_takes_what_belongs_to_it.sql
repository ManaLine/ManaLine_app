-- A hard delete could not actually run.
--
-- purge_record refused with a foreign key violation the first time it was
-- pointed at a real collection: collection_payment_splits references it, and
-- 19 of the 20 foreign keys into the eleven purge-able tables are NO ACTION
-- rather than CASCADE.
--
-- That is not only this function's problem. purge_expired_deletes -- the
-- nightly job that clears anything binned longer than 30 days -- deletes from
-- the same tables in one loop inside one transaction, so the first collection
-- with a payment split raises and the whole sweep aborts. Nothing has aged 30
-- days yet, so it has never fired; 612 collections and 108 loans are sitting
-- in the bin waiting for it to.
--
-- Children are removed explicitly rather than by switching the constraints to
-- CASCADE. On a lending book what a delete destroys should be readable in the
-- source, not inferred from twenty constraint definitions -- and a CASCADE
-- added for the bin would also apply to every other delete path forever.
create or replace function app.purge_dependents(p_entity text, p_record_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
BEGIN
  CASE p_entity
    WHEN 'collection' THEN
      DELETE FROM collection_payment_splits WHERE collection_id = p_record_id;
      -- The online payment is a separate record that merely POINTS at this
      -- collection. It is not part of it, so it is unlinked, not destroyed.
      UPDATE customer_online_payments SET resulting_collection_id = NULL
       WHERE resulting_collection_id = p_record_id;

    WHEN 'loan' THEN
      -- A loan's collections go with it: they cannot mean anything once the
      -- loan they were paid against is gone.
      DELETE FROM collection_payment_splits
       WHERE collection_id IN (SELECT collection_id FROM collections
                                WHERE loan_id = p_record_id);
      UPDATE customer_online_payments SET resulting_collection_id = NULL
       WHERE resulting_collection_id IN (SELECT collection_id FROM collections
                                          WHERE loan_id = p_record_id);
      DELETE FROM collections            WHERE loan_id = p_record_id;
      DELETE FROM loan_schedule          WHERE loan_id = p_record_id;
      DELETE FROM loan_remarks           WHERE loan_id = p_record_id;
      DELETE FROM penalty_entries        WHERE loan_id = p_record_id;
      DELETE FROM guarantors             WHERE loan_id = p_record_id;
      DELETE FROM loan_cancellations     WHERE loan_id = p_record_id;
      DELETE FROM loan_group_members     WHERE loan_id = p_record_id;
      DELETE FROM no_collection_visits   WHERE loan_id = p_record_id;
      DELETE FROM collection_drafts      WHERE loan_id = p_record_id;
      DELETE FROM extension_requests     WHERE loan_id = p_record_id;
      DELETE FROM customer_online_payments WHERE loan_id = p_record_id;
      -- The REQUEST survives its loan: somebody asked, and that happened.
      UPDATE loan_requests SET resulting_loan_id = NULL
       WHERE resulting_loan_id = p_record_id;

    WHEN 'investment' THEN
      DELETE FROM investment_withdrawal_requests
       WHERE investment_id = p_record_id;
      DELETE FROM investment_withdrawals   WHERE investment_id = p_record_id;
      DELETE FROM investment_interest_ledger WHERE investment_id = p_record_id;
      DELETE FROM distribution_declarations  WHERE investment_id = p_record_id;

    WHEN 'investment_withdrawal' THEN
      UPDATE investment_withdrawal_requests SET resulting_withdrawal_id = NULL
       WHERE resulting_withdrawal_id = p_record_id;

    -- cheti_payments already cascades from chetis, and the remaining
    -- entities (expense, settlement_adjustment, cash_transfer,
    -- customer_remark, customer_document, cheti_payment) are referenced by
    -- nothing.
    ELSE
      NULL;
  END CASE;
END;
$$;

create or replace function app.purge_record(p_entity text, p_record_id uuid)
returns json
language plpgsql
security definer
set search_path = public, app
as $$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID;
  v_deleted_at TIMESTAMP;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to delete records in this business'
      USING ERRCODE = '42501';
  END IF;

  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_deleted_at USING p_record_id;

  IF v_deleted_at IS NULL THEN
    -- Not in the bin. Refusing rather than deleting is the whole safety
    -- property: this function must never be a one-step destroy.
    RAISE EXCEPTION 'This record is not deleted, so it cannot be purged'
      USING ERRCODE = '23514';
  END IF;

  -- Audited BEFORE the row goes, because afterwards there is nothing left to
  -- describe it.
  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_purged', 0, p_record_id,
    json_build_object('table', v_table, 'deleted_at', v_deleted_at),
    CURRENT_DATE
  );

  PERFORM app.purge_dependents(p_entity, p_record_id);

  EXECUTE format('DELETE FROM %I WHERE %I = $1', v_table, v_pk)
    USING p_record_id;

  PERFORM app.recompute_ledger_chain(v_business_id);
  PERFORM app.recompute_business_bf(v_business_id);

  RETURN json_build_object(
    'status', 'purged', 'entity', p_entity, 'record_id', p_record_id
  );
END;
$$;

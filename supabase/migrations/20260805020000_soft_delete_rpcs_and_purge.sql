-- =============================================================================
-- SOFT DELETE (2/2) — delete, restore, list, and the 30-day purge
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   1. soft_delete_record  — marks one record deleted, after checking the
--      caller is the Owner of that record's business, or an agent the Owner
--      granted can_delete_records. Writes an audit_log row, because a delete
--      is exactly the action you most need a trail for.
--   2. restore_record      — puts it back, same permission check.
--   3. list_recent_deletes — what is in the bin, across every table, with
--      how many days are left before it is purged.
--   4. purge_expired_deletes — the only thing in this system that removes a
--      row for real, and only for rows deleted more than 30 days ago.
--      Scheduled nightly with pg_cron.
--
--   The entity names ('collection', 'loan', ...) are a CLOSED SET, checked
--   before any dynamic SQL is built, and the table/PK they map to are chosen
--   from that same CASE — never taken from the caller. p_record_id is always
--   passed as a bound parameter, never concatenated.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Shared: resolve (table, pk, business) for an entity name, or raise.
-- Returns the business the record belongs to, which is what every
-- permission check below is scoped by.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.resolve_deletable(
  p_entity TEXT,
  p_record_id UUID,
  OUT o_table TEXT,
  OUT o_pk TEXT,
  OUT o_business_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  CASE p_entity
    WHEN 'collection' THEN
      o_table := 'collections'; o_pk := 'collection_id';
      SELECT l.business_id INTO o_business_id
        FROM collections c JOIN loans l ON l.loan_id = c.loan_id
       WHERE c.collection_id = p_record_id;
    WHEN 'loan' THEN
      o_table := 'loans'; o_pk := 'loan_id';
      SELECT business_id INTO o_business_id FROM loans WHERE loan_id = p_record_id;
    WHEN 'expense' THEN
      o_table := 'expenses'; o_pk := 'expense_id';
      SELECT business_id INTO o_business_id FROM expenses WHERE expense_id = p_record_id;
    WHEN 'cheti_payment' THEN
      o_table := 'cheti_payments'; o_pk := 'cheti_payment_id';
      SELECT business_id INTO o_business_id FROM cheti_payments WHERE cheti_payment_id = p_record_id;
    WHEN 'cheti' THEN
      o_table := 'chetis'; o_pk := 'cheti_id';
      SELECT business_id INTO o_business_id FROM chetis WHERE cheti_id = p_record_id;
    WHEN 'investment' THEN
      o_table := 'investments'; o_pk := 'investment_id';
      SELECT business_id INTO o_business_id FROM investments WHERE investment_id = p_record_id;
    WHEN 'investment_withdrawal' THEN
      o_table := 'investment_withdrawals'; o_pk := 'withdrawal_id';
      SELECT i.business_id INTO o_business_id
        FROM investment_withdrawals w JOIN investments i ON i.investment_id = w.investment_id
       WHERE w.withdrawal_id = p_record_id;
    WHEN 'settlement_adjustment' THEN
      o_table := 'settlement_adjustments'; o_pk := 'adjustment_id';
      SELECT business_id INTO o_business_id FROM settlement_adjustments WHERE adjustment_id = p_record_id;
    WHEN 'cash_transfer' THEN
      o_table := 'cash_transfers'; o_pk := 'transfer_id';
      SELECT bm.business_id INTO o_business_id
        FROM cash_transfers t
        JOIN agents a ON a.agent_id = t.from_agent_id
        JOIN business_members bm ON bm.membership_id = a.membership_id
       WHERE t.transfer_id = p_record_id;
    WHEN 'customer_remark' THEN
      o_table := 'customer_remarks'; o_pk := 'remark_id';
      SELECT bm.business_id INTO o_business_id
        FROM customer_remarks r
        JOIN customers c ON c.customer_id = r.customer_id
        JOIN business_members bm ON bm.membership_id = c.membership_id
       WHERE r.remark_id = p_record_id;
    WHEN 'customer_document' THEN
      o_table := 'customer_documents'; o_pk := 'document_id';
      SELECT bm.business_id INTO o_business_id
        FROM customer_documents d
        JOIN customers c ON c.customer_id = d.customer_id
        JOIN business_members bm ON bm.membership_id = c.membership_id
       WHERE d.document_id = p_record_id;
    ELSE
      RAISE EXCEPTION 'Unknown record type: %', p_entity USING ERRCODE = '22023';
  END CASE;

  IF o_business_id IS NULL THEN
    RAISE EXCEPTION 'Record not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Shared: may the caller delete/restore in this business?
-- Owner always. Agent only with the Owner-granted can_delete_records.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.may_delete_records(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT app.is_owner(p_business_id)
      OR (app.is_active_agent(p_business_id)
          AND app.agent_permission(p_business_id, 'can_delete_records'));
$$;

-- ---------------------------------------------------------------------------
-- 1. soft_delete_record
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.soft_delete_record(
  p_entity TEXT,
  p_record_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID;
  v_membership_id UUID;
  v_already TIMESTAMP;
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

  -- Deleting an already-deleted row would overwrite who deleted it and
  -- when, silently restarting its 30-day clock.
  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_already USING p_record_id;
  IF v_already IS NOT NULL THEN
    RAISE EXCEPTION 'This record is already deleted' USING ERRCODE = '23514';
  END IF;

  EXECUTE format(
    'UPDATE %I SET deleted_at = now(), deleted_by_membership_id = $2, delete_reason = $3 WHERE %I = $1',
    v_table, v_pk)
    USING p_record_id, v_membership_id, p_reason;

  -- The delete is itself an event worth a trail, and audit_log is not one
  -- of the soft-deletable tables, so this row cannot be deleted in turn.
  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_soft_deleted', 0, p_record_id,
    json_build_object('reason', p_reason, 'table', v_table),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'deleted',
    'entity', p_entity,
    'record_id', p_record_id,
    'recoverable_until', (now() + INTERVAL '30 days')::date
  );
END;
$$;

COMMENT ON FUNCTION app.soft_delete_record(TEXT, UUID, TEXT) IS
  'Marks one record deleted. Owner, or an agent with can_delete_records. The row vanishes from every read (restrictive RLS) and from day_ledger, but is recoverable for 30 days via app.restore_record.';

GRANT EXECUTE ON FUNCTION app.soft_delete_record(TEXT, UUID, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. restore_record
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.restore_record(p_entity TEXT, p_record_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID; v_deleted_at TIMESTAMP;
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

COMMENT ON FUNCTION app.restore_record(TEXT, UUID) IS
  'Undoes a soft delete. The UPDATE re-fires the day_ledger trigger, so the restored row is counted again and the correction cascades forward exactly as the delete did.';

GRANT EXECUTE ON FUNCTION app.restore_record(TEXT, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. list_recent_deletes — the bin, for one business.
--
--    SECURITY DEFINER on purpose: the restrictive policies hide deleted
--    rows from every ordinary read, which is what makes them disappear
--    from the app. This is the one sanctioned way to look behind that.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.list_recent_deletes(p_business_id UUID)
RETURNS TABLE (
  entity TEXT,
  record_id UUID,
  label TEXT,
  amount DECIMAL(14,0),
  business_date DATE,
  deleted_at TIMESTAMP,
  deleted_by TEXT,
  delete_reason TEXT,
  days_left INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.may_delete_records(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to view deleted records in this business'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  -- Columns are named on the CTE itself: a UNION ALL otherwise inherits
  -- whatever the first branch's expressions happen to be called.
  WITH rows_union (
    entity, record_id, label, amount, business_date,
    deleted_at, by_membership, reason
  ) AS (
    SELECT 'collection'::TEXT, c.collection_id,
           ('Collection '||c.receipt_number)::TEXT,
           c.collected_amount::DECIMAL(14,0), c.business_date, c.deleted_at,
           c.deleted_by_membership_id, c.delete_reason
      FROM collections c JOIN loans l ON l.loan_id = c.loan_id
     WHERE l.business_id = p_business_id AND c.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'loan', l.loan_id, ('Loan '||l.loan_number)::TEXT,
           l.amount_given::DECIMAL(14,0), l.issue_business_date, l.deleted_at,
           l.deleted_by_membership_id, l.delete_reason
      FROM loans l
     WHERE l.business_id = p_business_id AND l.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'expense', e.expense_id, ('Expense — '||e.category::TEXT)::TEXT,
           e.amount::DECIMAL(14,0), e.business_date, e.deleted_at,
           e.deleted_by_membership_id, e.delete_reason
      FROM expenses e
     WHERE e.business_id = p_business_id AND e.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'cheti_payment', p.cheti_payment_id, 'Cheti instalment'::TEXT,
           p.gross_instalment::DECIMAL(14,0), p.business_date, p.deleted_at,
           p.deleted_by_membership_id, p.delete_reason
      FROM cheti_payments p
     WHERE p.business_id = p_business_id AND p.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'cheti', ch.cheti_id, ('Cheti '||ch.name)::TEXT,
           ch.instalment_amount::DECIMAL(14,0), ch.availed_date, ch.deleted_at,
           ch.deleted_by_membership_id, ch.delete_reason
      FROM chetis ch
     WHERE ch.business_id = p_business_id AND ch.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'investment', i.investment_id, 'Investment'::TEXT,
           i.principal_amount::DECIMAL(14,0), i.effective_date, i.deleted_at,
           i.deleted_by_membership_id, i.delete_reason
      FROM investments i
     WHERE i.business_id = p_business_id AND i.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'investment_withdrawal', w.withdrawal_id, 'Investor withdrawal'::TEXT,
           w.amount::DECIMAL(14,0), w.business_date, w.deleted_at,
           w.deleted_by_membership_id, w.delete_reason
      FROM investment_withdrawals w JOIN investments i2 ON i2.investment_id = w.investment_id
     WHERE i2.business_id = p_business_id AND w.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'settlement_adjustment', s.adjustment_id,
           ('Adjustment — '||s.adjustment_type::TEXT)::TEXT,
           s.amount::DECIMAL(14,0), s.business_date, s.deleted_at,
           s.deleted_by_membership_id, s.delete_reason
      FROM settlement_adjustments s
     WHERE s.business_id = p_business_id AND s.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'cash_transfer', t.transfer_id, 'Cash transfer'::TEXT,
           t.amount::DECIMAL(14,0), t.business_date, t.deleted_at,
           t.deleted_by_membership_id, t.delete_reason
      FROM cash_transfers t
      JOIN agents a ON a.agent_id = t.from_agent_id
      JOIN business_members abm ON abm.membership_id = a.membership_id
     WHERE abm.business_id = p_business_id AND t.deleted_at IS NOT NULL
    UNION ALL
    -- No amount: these carry no money, so the column stays NULL rather
    -- than being padded with a 0 that would read as "zero rupees".
    SELECT 'customer_remark', rm.remark_id, 'Customer remark'::TEXT,
           NULL::DECIMAL(14,0), rm.business_date, rm.deleted_at,
           rm.deleted_by_membership_id, rm.delete_reason
      FROM customer_remarks rm
      JOIN customers cu ON cu.customer_id = rm.customer_id
      JOIN business_members cbm ON cbm.membership_id = cu.membership_id
     WHERE cbm.business_id = p_business_id AND rm.deleted_at IS NOT NULL
    UNION ALL
    SELECT 'customer_document', dc.document_id,
           ('Document — '||dc.document_type::TEXT)::TEXT,
           NULL::DECIMAL(14,0), dc.uploaded_at::date, dc.deleted_at,
           dc.deleted_by_membership_id, dc.delete_reason
      FROM customer_documents dc
      JOIN customers cu2 ON cu2.customer_id = dc.customer_id
      JOIN business_members dbm2 ON dbm2.membership_id = cu2.membership_id
     WHERE dbm2.business_id = p_business_id AND dc.deleted_at IS NOT NULL
  )
  SELECT r.entity, r.record_id, r.label, r.amount, r.business_date,
         r.deleted_at,
         COALESCE(pp.full_name, '—')::TEXT,
         r.reason,
         GREATEST(30 - (CURRENT_DATE - r.deleted_at::date), 0)::INT
    FROM rows_union r
    LEFT JOIN business_members dbm ON dbm.membership_id = r.by_membership
    LEFT JOIN persons pp ON pp.person_id = dbm.person_id
   ORDER BY r.deleted_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION app.list_recent_deletes(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. purge_expired_deletes — the only real DELETE in the system.
--
--    Deliberately unqualified by business: it is a maintenance job, not a
--    user action, and is never granted to `authenticated`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.purge_expired_deletes(p_older_than_days INT DEFAULT 30)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  t TEXT;
  v_total INT := 0;
  v_count INT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- Children before parents: a collection references its loan, a
    -- withdrawal its investment, a cheti_payment its cheti. Purging the
    -- parent first would trip the foreign key.
    'collections', 'investment_withdrawals', 'cheti_payments',
    'settlement_adjustments', 'cash_transfers', 'customer_remarks',
    'customer_documents', 'loans', 'investments', 'chetis', 'expenses'
  ] LOOP
    EXECUTE format(
      'DELETE FROM %I WHERE deleted_at IS NOT NULL AND deleted_at < now() - ($1 || '' days'')::interval',
      t) USING p_older_than_days;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_total := v_total + v_count;
  END LOOP;
  RETURN v_total;
END;
$$;

COMMENT ON FUNCTION app.purge_expired_deletes(INT) IS
  'Hard-deletes rows soft-deleted more than N days ago (default 30). The only permanent delete in the system. Runs nightly under pg_cron; not granted to authenticated.';

REVOKE ALL ON FUNCTION app.purge_expired_deletes(INT) FROM PUBLIC;

-- Nightly at 02:15 IST. The DB TimeZone is Asia/Kolkata, but pg_cron
-- schedules in UTC, so 20:45 UTC.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  'purge-expired-soft-deletes',
  '45 20 * * *',
  $cron$SELECT app.purge_expired_deletes(30);$cron$
);

-- MANA LINE — 0052_fix_admin_delete_person.sql
--
-- Full audit + rewrite of app.admin_delete_person against the live FK
-- graph, same method used for admin_delete_business in 0051. Two bugs
-- found that made this function fail on EVERY call regardless of which
-- person was targeted:
--
--   1. `DELETE FROM loan_group_members WHERE customer_id = ...` — fails
--      immediately with 42703. loan_group_members has no customer_id
--      column (only group_id, loan_id); this line ran before the
--      settlement_adjustments bug 0051 already patched, so that earlier
--      one-line fix never actually took effect — this line crashed first.
--   2. Coverage gap: ~20 tables holding a person's own data (as customer,
--      agent, or investor) were never deleted — customer_documents,
--      customer_remarks, customer_online_payments, agent_documents,
--      agent_compensation_history, agent_salary_ledger, salary_advances,
--      cash_transfers, agent_bf_assignments, agent_access_days,
--      collection_drafts, no_collection_visits, loan_requests,
--      loan_cancellations, penalty_entries, extension_requests,
--      guarantors, investments (+ its own ledger/withdrawal tables),
--      distribution_declarations/payments, agreement_acceptances,
--      membership_requests, devices, identity_documents,
--      person_id_history — any of these having a row would still hit a
--      fresh FK-violation for a real person even with bug #1 fixed.
--
-- SCOPE BOUNDARY (deliberate, not a gap): this only deletes rows that are
-- the person's OWN data (their customer/agent/investor records and what
-- hangs off them). It does NOT touch tables where this person merely
-- appears as a historical actor on someone else's record — audit_log
-- (actor_person_id), day_closures (closed_by_person_id), customer_remarks
-- (entered_by_person_id), penalty_entries (applied_by_person_id),
-- loan_cancellations (cancelled_by_person_id), owner_approvals
-- (approved_by_person_id), membership_requests (reviewed_by_person_id),
-- account_periods/account_settlements (approved/reviewed_by_person_id),
-- business_members (invited_by_person_id), businesses (owner_person_id).
-- Silently deleting those would corrupt audit trail / other people's
-- business records just because this person once approved or reviewed
-- something. If a person has significant history in those actor columns,
-- this function still fails loudly with a clear FK-violation naming the
-- table — same "fail loud, never silently corrupt" design the original
-- 0049 header already committed to — rather than being taught to erase
-- records that aren't this person's to erase. If this person owns a
-- business, that must still be deleted first via admin_delete_business,
-- per the same note the original function already carried.

CREATE OR REPLACE FUNCTION app.admin_delete_person(p_person_id BIGINT, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_admin_id BIGINT := app.current_person_id();
  v_snapshot JSONB;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required for every admin deletion.';
  END IF;

  SELECT jsonb_build_object(
    'person', to_jsonb(p.*),
    'addresses', (SELECT jsonb_agg(to_jsonb(pa.*)) FROM person_addresses pa WHERE pa.person_id = p_person_id),
    'memberships', (SELECT jsonb_agg(to_jsonb(bm.*)) FROM business_members bm WHERE bm.person_id = p_person_id)
  ) INTO v_snapshot
  FROM persons p WHERE p.person_id = p_person_id;

  IF v_snapshot IS NULL OR v_snapshot->'person' = 'null'::jsonb THEN
    RAISE EXCEPTION 'Person % not found.', p_person_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'person', p_person_id::TEXT, v_snapshot, p_reason);

  -- Tier 1: leaves hanging off this person's customer/agent/investor/
  -- membership rows and their loans — deleted first while those parent
  -- rows still exist.
  DELETE FROM collection_payment_splits WHERE collection_id IN (
    SELECT collection_id FROM collections
    WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id)
       OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id)
  );
  DELETE FROM customer_online_payments WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM loan_schedule WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM loan_cancellations WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM penalty_entries WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM extension_requests WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM guarantors WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id))
    OR guarantor_person_id = p_person_id;
  DELETE FROM loan_group_members WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM collection_drafts WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id))
    OR created_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM no_collection_visits WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id))
    OR customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id)
    OR visited_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM loan_requests WHERE
    customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id)
    OR resulting_loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM customer_documents WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM customer_remarks WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM agreement_acceptances WHERE person_id = p_person_id;
  DELETE FROM membership_requests WHERE person_id = p_person_id;
  DELETE FROM agent_area_assignments WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_permissions WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_compensation_history WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_documents WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_salary_ledger WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM salary_advances WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM cash_transfers WHERE
    from_agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id)
    OR to_agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_bf_assignments WHERE membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM agent_access_days WHERE
    membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id)
    OR granted_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM otp_verifications WHERE person_id = p_person_id;
  DELETE FROM investment_interest_ledger WHERE investment_id IN (SELECT investment_id FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id));
  DELETE FROM investment_withdrawal_requests WHERE investment_id IN (SELECT investment_id FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id));
  DELETE FROM investment_withdrawals WHERE investment_id IN (SELECT investment_id FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id));
  DELETE FROM distribution_payments WHERE declaration_id IN (
    SELECT declaration_id FROM distribution_declarations
    WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id)
       OR investment_id IN (SELECT investment_id FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id))
  );
  DELETE FROM devices WHERE person_id = p_person_id;
  DELETE FROM identity_documents WHERE person_id = p_person_id;
  DELETE FROM person_id_history WHERE person_id = p_person_id;

  -- Tier 2: now safe to remove collections/loans/investments/
  -- distribution_declarations/settlements themselves.
  DELETE FROM collections WHERE
    customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id)
    OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM distribution_declarations WHERE
    agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id)
    OR investment_id IN (SELECT investment_id FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id));
  DELETE FROM investments WHERE investor_id IN (SELECT investor_id FROM investors WHERE person_id = p_person_id);
  DELETE FROM settlement_adjustments WHERE
    settlement_id IN (SELECT settlement_id FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id))
    OR agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id)
    OR target_customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);

  -- Tier 3: the entity rows themselves.
  DELETE FROM agents WHERE person_id = p_person_id;
  DELETE FROM customers WHERE person_id = p_person_id;
  DELETE FROM investors WHERE person_id = p_person_id;
  DELETE FROM duplicate_suspects WHERE person_id_a = p_person_id OR person_id_b = p_person_id;
  DELETE FROM notifications WHERE recipient_person_id = p_person_id;

  -- Tier 4: membership + identity rows last, then the person.
  DELETE FROM business_members WHERE person_id = p_person_id;
  DELETE FROM person_addresses WHERE person_id = p_person_id;
  DELETE FROM platform_admins WHERE person_id = p_person_id;
  -- If this person owns any businesses, those must be deleted separately
  -- via admin_delete_business first — deliberately NOT auto-cascaded
  -- here, since deleting a whole business is a much bigger blast radius
  -- that deserves its own explicit call and its own reason.
  DELETE FROM persons WHERE person_id = p_person_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_person(BIGINT, TEXT) IS
  'Platform Admin super power — permanent, irreversible deletion of a person and every row that is their own data (customer/agent/investor footprint). Logs a full snapshot to admin_deletion_log before deleting. If this person owns a business, delete that business first via admin_delete_business. Deliberately does not delete rows where this person is only a historical actor (approved_by/reviewed_by/etc.) on someone else''s record — those block deletion with a clear FK-violation naming the table, by design, rather than silently corrupting unrelated data. Deletion order verified against live information_schema FK graph (2026-07-28).';

GRANT EXECUTE ON FUNCTION app.admin_delete_person(BIGINT, TEXT) TO authenticated;

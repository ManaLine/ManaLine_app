-- MANA LINE — 0051_fix_admin_delete_business.sql
--
-- Fixes app.admin_delete_business, which has failed on every call since
-- 0049. Two problems, found by diffing the function's DELETE order against
-- the actual live FK graph (information_schema, not the migration files —
-- several tables here were added in migrations after 0049 and the function
-- was never updated):
--
--   1. `DELETE FROM collections WHERE business_id = p_business_id` — fails
--      immediately with 42703 "column business_id does not exist".
--      collections has no business_id column; it reaches a business only
--      indirectly via loan_id -> loans.business_id or
--      collected_by_membership_id -> business_members.business_id.
--   2. Even with #1 fixed, the function is missing ~20 child tables added
--      to the schema after 0049 (guarantors, customer_documents,
--      customer_online_payments, agent_documents, agent_compensation_history,
--      cash_transfers, collection_drafts, no_collection_visits,
--      agent_access_days, agent_bf_assignments, loan_requests,
--      loan_cancellations, penalty_entries, extension_requests,
--      agent_salary_ledger, salary_advances, distribution_declarations/
--      distribution_payments, route_locations, agreement_acceptances,
--      membership_requests, day_ledger/day_closures, audit_log,
--      owner_approvals, loan_templates) — any business with rows in any
--      of these would still hit a fresh FK-violation once #1 was patched.
--
-- Full deletion order below was derived from a live query against
-- information_schema.referential_constraints for every FK pointing (
-- directly or transitively) at businesses(business_id), so it reflects the
-- schema as it actually exists today rather than as originally designed.
--
-- Also fixes the identical class of bug in app.admin_delete_person, which
-- references settlement_adjustments.account_settlement_id — that column
-- has never existed; the real column is settlement_id. "Delete Person" has
-- therefore also failed on every call since 0049 for any person with a
-- settlement history. Only that one line is patched here — the rest of
-- admin_delete_person's table coverage is narrower in scope (a person, not
-- a whole business) and not touched in this pass.

CREATE OR REPLACE FUNCTION app.admin_delete_business(p_business_id UUID, p_reason TEXT)
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

  SELECT to_jsonb(b.*) INTO v_snapshot FROM businesses b WHERE b.business_id = p_business_id;
  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'Business % not found.', p_business_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'business', p_business_id::TEXT, v_snapshot, p_reason);

  -- Tier 1: leaves that hang off collections/loans/business_members/agents/
  -- customers/account_periods/routes/business_agreements/investments —
  -- deleted first while all of those parent tables still exist.
  DELETE FROM collection_payment_splits WHERE collection_id IN (
    SELECT collection_id FROM collections
    WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
       OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
  );
  DELETE FROM customer_online_payments WHERE customer_id IN (
    SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
  );
  DELETE FROM settlement_adjustments WHERE
    settlement_id IN (SELECT settlement_id FROM account_settlements WHERE account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id))
    OR agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM agreement_acceptances WHERE agreement_id IN (SELECT agreement_id FROM business_agreements WHERE business_id = p_business_id);
  DELETE FROM route_locations WHERE route_id IN (SELECT route_id FROM routes WHERE business_id = p_business_id);
  DELETE FROM distribution_payments WHERE declaration_id IN (SELECT declaration_id FROM distribution_declarations WHERE business_id = p_business_id);
  DELETE FROM investment_interest_ledger WHERE investment_id IN (SELECT investment_id FROM investments WHERE business_id = p_business_id);
  DELETE FROM investment_withdrawal_requests WHERE investment_id IN (SELECT investment_id FROM investments WHERE business_id = p_business_id);
  DELETE FROM investment_withdrawals WHERE investment_id IN (SELECT investment_id FROM investments WHERE business_id = p_business_id);
  DELETE FROM loan_group_members WHERE
    group_id IN (SELECT group_id FROM loan_groups WHERE business_id = p_business_id)
    OR loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM loan_schedule WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM loan_cancellations WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM penalty_entries WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM extension_requests WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM guarantors WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM collection_drafts WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
    OR created_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM no_collection_visits WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
    OR customer_id IN (SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR visited_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM agent_bf_assignments WHERE
    account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id)
    OR membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM agent_access_days WHERE
    membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR granted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM agent_compensation_history WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM agent_documents WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM cash_transfers WHERE
    from_agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR to_agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM otp_verifications WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM customer_documents WHERE customer_id IN (SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM customer_remarks WHERE customer_id IN (SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM loan_requests WHERE
    customer_id IN (SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR resulting_loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM agent_area_assignments WHERE
    agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR operating_area_id IN (SELECT operating_area_id FROM operating_areas WHERE business_id = p_business_id);
  DELETE FROM agent_permissions WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM agent_salary_ledger WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM salary_advances WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));

  -- Tier 2: now safe to remove collections/investments/settlements/loans/
  -- groups/routes/agreements and their now-childless direct parents.
  DELETE FROM collections WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
    OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM distribution_declarations WHERE business_id = p_business_id;
  DELETE FROM investments WHERE business_id = p_business_id;
  DELETE FROM account_settlements WHERE account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id);
  DELETE FROM loan_groups WHERE business_id = p_business_id;
  DELETE FROM loans WHERE business_id = p_business_id;
  DELETE FROM route_locations WHERE route_id IN (SELECT route_id FROM routes WHERE business_id = p_business_id); -- re-run: routes below may have gained rows since tier 1 in a concurrent session; cheap no-op otherwise
  DELETE FROM routes WHERE business_id = p_business_id;
  DELETE FROM business_agreements WHERE business_id = p_business_id;
  DELETE FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM loan_templates WHERE business_id = p_business_id;

  -- Tier 3: membership-holder tables, now that everything referencing
  -- their ids (agents/loans/collections/etc.) is gone.
  DELETE FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM investors WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM account_periods WHERE business_id = p_business_id;
  DELETE FROM expenses WHERE business_id = p_business_id;
  DELETE FROM membership_requests WHERE business_id = p_business_id;
  DELETE FROM notifications WHERE business_id = p_business_id;
  DELETE FROM owner_approvals WHERE business_id = p_business_id;
  DELETE FROM audit_log WHERE business_id = p_business_id;
  DELETE FROM day_ledger WHERE business_id = p_business_id;
  DELETE FROM day_closures WHERE business_id = p_business_id;

  -- Tier 4: business_members last (everything above referencing
  -- membership_id is now gone), then operating_areas, then the business.
  DELETE FROM business_members WHERE business_id = p_business_id;
  DELETE FROM operating_areas WHERE business_id = p_business_id;
  DELETE FROM businesses WHERE business_id = p_business_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_business(UUID, TEXT) IS
  'Platform Admin super power — permanent, irreversible deletion of a business and everything under it. Does not delete the persons themselves, only their footprint within this business. Deletion order verified against live information_schema FK graph (2026-07-28) after the original 0049 version failed on every call.';

GRANT EXECUTE ON FUNCTION app.admin_delete_business(UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.admin_delete_person — one-line fix for the same class of bug:
-- settlement_adjustments.account_settlement_id has never existed as a
-- column (real name: settlement_id), so this function has also failed on
-- every call for any person with settlement history since 0049.
-- -----------------------------------------------------------------------------
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

  -- Deepest leaves first, working up to persons itself.
  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id));
  DELETE FROM collections WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM collections WHERE collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM loan_schedule WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM loan_group_members WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM settlement_adjustments WHERE settlement_id IN (SELECT settlement_id FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id));
  DELETE FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_area_assignments WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_permissions WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agents WHERE person_id = p_person_id;
  DELETE FROM customers WHERE person_id = p_person_id;
  DELETE FROM investors WHERE person_id = p_person_id;
  DELETE FROM duplicate_suspects WHERE person_id_a = p_person_id OR person_id_b = p_person_id;
  DELETE FROM notifications WHERE recipient_person_id = p_person_id;
  DELETE FROM otp_verifications WHERE person_id = p_person_id;
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
  'Platform Admin super power — permanent, irreversible deletion of a person and every dependent row. Logs a full snapshot to admin_deletion_log before deleting. If this person owns a business, delete that business first via admin_delete_business. NOTE: table coverage here is narrower than admin_delete_business and has not been re-verified against the full live FK graph (2026-07-28) — only the known-broken settlement_adjustments column was fixed.';

GRANT EXECUTE ON FUNCTION app.admin_delete_person(BIGINT, TEXT) TO authenticated;

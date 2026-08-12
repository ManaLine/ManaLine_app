-- =============================================================================
-- Admin delete RPCs, part 3 of 3 — AUTHORITATIVE DEFINITION
-- =============================================================================
-- Both admin delete RPCs failed on their first ever call, so test data on prod
-- could not be removed. Root cause: every FK in this schema is ON DELETE NO
-- ACTION, so one missed child row aborts the whole delete — and both functions
-- predate the soft-delete (2026-08-05), cheti, and agent-BF-grant migrations
-- and were never updated for the tables and columns those added.
--
-- Three distinct classes of defect, the last two found only by INVOKING the
-- functions inside a rolled-back transaction. A plpgsql body that compiles
-- proves nothing here (CLAUDE.md), and reading the FK graph was not enough
-- either: it showed what points AT the parents, not the cycle below.
--
--   1. MISSING TABLES. admin_delete_business never touched agent_bf_grants,
--      business_transfers, chetis, cheti_payments or operating_area_locations,
--      and deleted settlement_adjustments by settlement/agent but not by its
--      own business_id. purge_person_hard missed person_phone_history — a pure
--      child sitting beside person_addresses and person_id_history, which it
--      does delete.
--
--   2. AN FK CYCLE. business_members.permission_profile_id references
--      agent_permissions, while agent_permissions.agent_id -> agents ->
--      business_members. No delete order satisfies all three. The column is
--      nullable, so both functions now clear it first (Tier 0). This is the
--      error the previous attempt died on:
--        "update or delete on table agent_permissions violates foreign key
--         constraint fk_business_members_permission_profile"
--
--   3. WRONG ORDER. collections.guarantor_id references guarantors, but
--      guarantors was deleted in Tier 1 and collections in Tier 2 — backwards.
--      Now collections, then guarantors, then loans.
--
-- What is deliberately NOT deleted, and why: roughly 20 FKs to persons are
-- ACTOR references (audit_log.actor_person_id, day_closures.closed_by_person_id,
-- penalty_entries.applied_by_person_id, businesses.owner_person_id, ...). Those
-- are not the person's own data — they are other people's records naming who
-- acted. Cascading through them would destroy one business's history to satisfy
-- an admin action against a different person. admin_delete_person therefore
-- REFUSES, naming exactly what is in the way. Decision confirmed with the Owner
-- 2026-08-12.
--
-- Verified against prod inside DO blocks that raise at the end to roll back:
--   admin_delete_business  -> businesses 2->1, business_members 41->2
--   admin_delete_person(3) -> persons 37->36        (unblocked person)
--   admin_delete_person(2) -> refused, listing 4 blockers (business owner)

-- -----------------------------------------------------------------------------
-- 1. What still points at a person that a purge is not entitled to remove.
-- -----------------------------------------------------------------------------
-- Deliberately DYNAMIC over pg_constraint rather than a hand-written list. The
-- original defect was precisely that new migrations added FKs and a
-- hand-written list was never updated; enumerating live constraints means a
-- future table cannot silently reintroduce it. The exclusion array is the set
-- purge_person_hard genuinely owns and deletes.
CREATE OR REPLACE FUNCTION app.person_delete_blockers(p_person_id BIGINT)
RETURNS TABLE(ref_table TEXT, ref_column TEXT, blocking_rows BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  r RECORD;
  v_count BIGINT;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col
    FROM pg_constraint c
    JOIN unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    WHERE c.contype = 'f'
      AND c.confrelid = 'public.persons'::regclass
      AND (c.conrelid::regclass::text || '.' || a.attname) <> ALL (ARRAY[
        'agents.person_id',
        'customers.person_id',
        'investors.person_id',
        'business_members.person_id',
        'person_addresses.person_id',
        'person_id_history.person_id',
        'person_phone_history.person_id',
        'platform_admins.person_id',
        'devices.person_id',
        'identity_documents.person_id',
        'otp_verifications.person_id',
        'agreement_acceptances.person_id',
        'membership_requests.person_id',
        'notifications.recipient_person_id',
        'guarantors.guarantor_person_id',
        'duplicate_suspects.person_id_a',
        'duplicate_suspects.person_id_b'
      ])
    ORDER BY 1, 2
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col)
      INTO v_count USING p_person_id;
    IF v_count > 0 THEN
      ref_table := r.tbl;
      ref_column := r.col;
      blocking_rows := v_count;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION app.person_delete_blockers(BIGINT) IS
  'Rows that reference a person but are not the person''s own data (actor/owner references). Non-empty means admin_delete_person will refuse.';

-- -----------------------------------------------------------------------------
-- 2. purge_person_hard
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.purge_person_hard(p_person_id BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- Tier 0: break the business_members <-> agent_permissions cycle.
  UPDATE business_members SET permission_profile_id = NULL WHERE person_id = p_person_id;

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
  DELETE FROM agent_bf_grants WHERE membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
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
  -- ADDED: was missing entirely, so any person whose phone had ever changed
  -- could not be purged.
  DELETE FROM person_phone_history WHERE person_id = p_person_id;

  -- collections BEFORE guarantors (collections.guarantor_id), then loans.
  DELETE FROM collections WHERE
    customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id)
    OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM guarantors WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id))
    OR guarantor_person_id = p_person_id;
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

  DELETE FROM agents WHERE person_id = p_person_id;
  DELETE FROM customers WHERE person_id = p_person_id;
  DELETE FROM investors WHERE person_id = p_person_id;
  DELETE FROM duplicate_suspects WHERE person_id_a = p_person_id OR person_id_b = p_person_id;
  DELETE FROM notifications WHERE recipient_person_id = p_person_id;

  DELETE FROM business_members WHERE person_id = p_person_id;
  DELETE FROM person_addresses WHERE person_id = p_person_id;
  DELETE FROM platform_admins WHERE person_id = p_person_id;
  DELETE FROM persons WHERE person_id = p_person_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. admin_delete_person — refuse with reasons instead of an opaque FK error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.admin_delete_person(p_person_id BIGINT, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_admin_id UUID := app.current_admin_id();
  v_snapshot JSONB;
  v_blockers TEXT;
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

  -- Checked BEFORE the log insert so a refused attempt leaves no trace of a
  -- deletion that never happened.
  SELECT string_agg(format('%s.%s (%s)', b.ref_table, b.ref_column, b.blocking_rows), ', ' ORDER BY b.ref_table, b.ref_column)
    INTO v_blockers
  FROM app.person_delete_blockers(p_person_id) b;

  IF v_blockers IS NOT NULL THEN
    RAISE EXCEPTION
      'Cannot delete person %: still referenced by % . These are other records naming this person as the actor or owner, not their own data — deleting them would destroy history belonging to someone else. Delete the owned business first, or reassign, then retry.',
      p_person_id, v_blockers
      USING ERRCODE = '23503';
  END IF;

  INSERT INTO admin_deletion_log (deleted_by_admin_id, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'person', p_person_id::TEXT, v_snapshot, p_reason);

  PERFORM app.purge_person_hard(p_person_id);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. admin_delete_business
-- -----------------------------------------------------------------------------
-- NOT handled on purpose: a row in ANOTHER business whose
-- deleted_by_membership_id points at a membership in THIS business. A member
-- can only soft-delete inside their own business, so that row should not
-- exist; if one ever does, this raises a named FK violation, which is
-- diagnosable. Silently NULLing audit columns to force the delete through
-- would be worse.
CREATE OR REPLACE FUNCTION app.admin_delete_business(p_business_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_admin_id UUID := app.current_admin_id();
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

  INSERT INTO admin_deletion_log (deleted_by_admin_id, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'business', p_business_id::TEXT, v_snapshot, p_reason);

  -- Tier 0: break the business_members <-> agent_permissions cycle.
  UPDATE business_members SET permission_profile_id = NULL WHERE business_id = p_business_id;

  -- Tier 1: leaves.
  DELETE FROM collection_payment_splits WHERE collection_id IN (
    SELECT collection_id FROM collections
    WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
       OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
  );
  DELETE FROM customer_online_payments WHERE customer_id IN (
    SELECT customer_id FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
  );
  DELETE FROM settlement_adjustments WHERE
    business_id = p_business_id
    OR settlement_id IN (SELECT settlement_id FROM account_settlements WHERE account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id))
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
  -- ADDED (agent BF grants migration).
  DELETE FROM agent_bf_grants WHERE
    business_id = p_business_id
    OR membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR granted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR deleted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM agent_access_days WHERE
    membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR granted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM agent_compensation_history WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM agent_documents WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM cash_transfers WHERE
    from_agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR to_agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id))
    OR deleted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
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
  -- ADDED (cheti migration): payments first, they FK to chetis.
  DELETE FROM cheti_payments WHERE
    business_id = p_business_id
    OR recorded_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR deleted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  -- ADDED (operating-area locations).
  DELETE FROM operating_area_locations WHERE
    business_id = p_business_id
    OR operating_area_id IN (SELECT operating_area_id FROM operating_areas WHERE business_id = p_business_id);

  -- Tier 2: collections BEFORE guarantors (collections.guarantor_id), then loans.
  DELETE FROM collections WHERE
    loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id)
    OR collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id)
    OR deleted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM guarantors WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM distribution_declarations WHERE business_id = p_business_id;
  DELETE FROM investments WHERE business_id = p_business_id;
  DELETE FROM account_settlements WHERE account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id);
  DELETE FROM loan_groups WHERE business_id = p_business_id;
  DELETE FROM loans WHERE business_id = p_business_id;
  DELETE FROM routes WHERE business_id = p_business_id;
  DELETE FROM business_agreements WHERE business_id = p_business_id;
  DELETE FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM loan_templates WHERE business_id = p_business_id;
  -- ADDED (cheti migration).
  DELETE FROM chetis WHERE
    business_id = p_business_id
    OR deleted_by_membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);

  -- Tier 3.
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
  -- ADDED (business transfer migration).
  DELETE FROM business_transfers WHERE business_id = p_business_id;

  -- Tier 4.
  DELETE FROM business_members WHERE business_id = p_business_id;
  DELETE FROM operating_areas WHERE business_id = p_business_id;
  DELETE FROM businesses WHERE business_id = p_business_id;
END;
$function$;

-- The delete cascade, extracted from app.admin_delete_person so the automatic
-- 90-day purge and an admin deletion share ONE implementation.
--
-- Two copies of a 60-statement, order-dependent cascade would drift the first
-- time a table is added, and the failure mode is a foreign-key error in a
-- nightly cron job nobody is watching.
--
-- No authorization check inside: this is the mechanism, not the policy.
-- admin_delete_person keeps the platform-admin gate, and purge_due_accounts is
-- only reachable from pg_cron. Neither is granted to `authenticated`.
CREATE OR REPLACE FUNCTION app.purge_person_hard(p_person_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
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
  DELETE FROM persons WHERE person_id = p_person_id;
END;
$function$;

-- admin_delete_person keeps the policy -- who may do it, why, and the audit
-- snapshot -- and delegates the mechanism.
CREATE OR REPLACE FUNCTION app.admin_delete_person(p_person_id bigint, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
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

  PERFORM app.purge_person_hard(p_person_id);
END;
$function$;

REVOKE ALL ON FUNCTION app.purge_person_hard(bigint) FROM PUBLIC;

-- Platform Admin gets its own identity system, fully separate from
-- `persons`. Previously "admin" was just a person with a row in
-- `platform_admins`, surfaced as a menu item buried inside the Owner's own
-- dashboard header — reached through the SAME login as every regular
-- business user. That's now removed entirely (see the Dart changes in the
-- same commit): a platform admin is a different trust domain from
-- Owner/Agent/Investor/Customer and gets its own login screen, its own
-- credentials table, and its own JWT claim.
--
-- The one existing person who held admin (person_id 2, mobile 9493509919)
-- had their `platform_admins` row deleted directly via the SQL Editor
-- before this migration — that table is left in place (still referenced by
-- app.admin_delete_person's cleanup DELETE) but nothing populates it going
-- forward; app.is_platform_admin() no longer reads it at all.

-- ---------------------------------------------------------------------
-- admin_accounts — isolated credential store. No FK to persons anywhere:
-- an admin is not a person in this system. RLS is deny-all, same pattern
-- as platform_admins before it — only SECURITY DEFINER Edge Functions
-- (via the service-role key) ever touch this table; no client policy
-- exists for it at all.
-- ---------------------------------------------------------------------
CREATE TABLE admin_accounts (
  admin_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username                VARCHAR(50) NOT NULL UNIQUE,
  password_hash           VARCHAR(255) NOT NULL,
  recovery_mobile_number  VARCHAR(15) NOT NULL,
  created_at              TIMESTAMP NOT NULL DEFAULT now(),
  updated_at              TIMESTAMP NOT NULL DEFAULT now()
);

ALTER TABLE admin_accounts ENABLE ROW LEVEL SECURITY;
-- No CREATE POLICY for any role — deny-all, exactly like platform_admins.

COMMENT ON TABLE admin_accounts IS
  'Platform Admin login credentials. Deliberately isolated from persons — an admin is not a business user. Populated only via admin-login/admin-password-reset Edge Functions using the service role; no client write path exists.';

-- ---------------------------------------------------------------------
-- admin_otp_verifications — a SEPARATE OTP table from `otp_verifications`,
-- because that table's person_id column is NOT NULL and admin accounts
-- have no person_id to put there. Same shape, same intent, just scoped to
-- admin_accounts instead of persons.
-- ---------------------------------------------------------------------
CREATE TABLE admin_otp_verifications (
  otp_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id       UUID NOT NULL REFERENCES admin_accounts(admin_id),
  purpose        VARCHAR(30) NOT NULL DEFAULT 'Password Reset',
  otp_code_hash  VARCHAR(255) NOT NULL,
  sent_at        TIMESTAMP NOT NULL DEFAULT now(),
  verified_at    TIMESTAMP NULL,
  status         VARCHAR(20) NOT NULL DEFAULT 'Sent'
);

ALTER TABLE admin_otp_verifications ENABLE ROW LEVEL SECURITY;
-- Deny-all — same reasoning as admin_accounts.

COMMENT ON TABLE admin_otp_verifications IS
  'OTP codes for Admin password reset, sent to admin_accounts.recovery_mobile_number. Isolated from otp_verifications (that table requires a person_id, which an admin account does not have).';

-- ---------------------------------------------------------------------
-- app.current_admin_id() — mirrors app.current_person_id()'s pattern
-- exactly (0012_rls_module0_identity.sql), reading an `admin_id` JWT
-- claim instead of `person_id`. A single caller never carries both claims
-- — a token is minted as either a person session or an admin session,
-- never both.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_admin_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json ->> 'admin_id', '')::UUID;
$$;

COMMENT ON FUNCTION app.current_admin_id() IS
  'Current admin_id from JWT custom claim "admin_id", minted only by the admin-login Edge Function.';

GRANT EXECUTE ON FUNCTION app.current_admin_id() TO authenticated;

-- ---------------------------------------------------------------------
-- app.is_platform_admin() — REPLACED. Used to check the platform_admins
-- table by person_id; now just checks whether the caller's JWT carries an
-- admin_id claim at all. Every existing admin-gated RPC (admin_delete_*,
-- the SP-001 support-lookup functions, admin_lookup_rpcs) calls this by
-- name and needed no other change — the gate itself moved, the callers
-- didn't.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT app.current_admin_id() IS NOT NULL;
$$;

COMMENT ON FUNCTION app.is_platform_admin() IS
  'TRUE only if the caller authenticated via admin-login (JWT carries an admin_id claim). No longer reads platform_admins.';

-- ---------------------------------------------------------------------
-- admin_deletion_log.deleted_by was NOT NULL REFERENCES persons(person_id)
-- — that breaks the instant an admin caller has no person_id at all.
-- Relaxed to nullable, with a new deleted_by_admin_id column for the
-- identity that actually did the deleting from here on. Historical rows
-- keep their old deleted_by value untouched; nothing is backfilled or
-- guessed.
-- ---------------------------------------------------------------------
ALTER TABLE admin_deletion_log ALTER COLUMN deleted_by DROP NOT NULL;
ALTER TABLE admin_deletion_log ADD COLUMN deleted_by_admin_id UUID NULL REFERENCES admin_accounts(admin_id);

COMMENT ON COLUMN admin_deletion_log.deleted_by IS
  'Historical: person_id of the admin, back when Platform Admin was a flagged person. NULL for every deletion made after admin_accounts existed.';
COMMENT ON COLUMN admin_deletion_log.deleted_by_admin_id IS
  'admin_accounts.admin_id of whoever performed this deletion. NULL for deletions made before admin_accounts existed.';

-- ---------------------------------------------------------------------
-- The four admin_delete_* functions — CREATE OR REPLACE against their
-- exact live bodies (confirmed via pg_proc, since this project's own
-- migration ledger is known to drift from what's actually deployed), with
-- ONLY the admin-identity lines changed: v_admin_id is now
-- app.current_admin_id() (UUID, not BIGINT), and the log INSERT writes
-- deleted_by_admin_id instead of deleted_by. Every DELETE statement below
-- is unchanged from what is live today.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.admin_delete_person(p_person_id BIGINT, p_reason TEXT)
RETURNS VOID
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

  SELECT jsonb_build_object(
    'person', to_jsonb(p.*),
    'addresses', (SELECT jsonb_agg(to_jsonb(pa.*)) FROM person_addresses pa WHERE pa.person_id = p_person_id),
    'memberships', (SELECT jsonb_agg(to_jsonb(bm.*)) FROM business_members bm WHERE bm.person_id = p_person_id)
  ) INTO v_snapshot
  FROM persons p WHERE p.person_id = p_person_id;

  IF v_snapshot IS NULL OR v_snapshot->'person' = 'null'::jsonb THEN
    RAISE EXCEPTION 'Person % not found.', p_person_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by_admin_id, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'person', p_person_id::TEXT, v_snapshot, p_reason);

  PERFORM app.purge_person_hard(p_person_id);
END;
$function$;

CREATE OR REPLACE FUNCTION app.admin_delete_business(p_business_id UUID, p_reason TEXT)
RETURNS VOID
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
$function$;

CREATE OR REPLACE FUNCTION app.admin_delete_loan(p_loan_id UUID, p_reason TEXT)
RETURNS VOID
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

  SELECT jsonb_build_object(
    'loan', to_jsonb(l.*),
    'collections', (SELECT jsonb_agg(to_jsonb(c.*)) FROM collections c WHERE c.loan_id = p_loan_id),
    'schedule', (SELECT jsonb_agg(to_jsonb(s.*)) FROM loan_schedule s WHERE s.loan_id = p_loan_id)
  ) INTO v_snapshot
  FROM loans l WHERE l.loan_id = p_loan_id;

  IF v_snapshot IS NULL OR v_snapshot->'loan' = 'null'::jsonb THEN
    RAISE EXCEPTION 'Loan % not found.', p_loan_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by_admin_id, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'loan', p_loan_id::TEXT, v_snapshot, p_reason);

  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE loan_id = p_loan_id);
  DELETE FROM collections WHERE loan_id = p_loan_id;
  DELETE FROM loan_schedule WHERE loan_id = p_loan_id;
  DELETE FROM loan_group_members WHERE loan_id = p_loan_id;
  DELETE FROM loans WHERE loan_id = p_loan_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.admin_delete_collection(p_collection_id UUID, p_reason TEXT)
RETURNS VOID
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

  SELECT to_jsonb(c.*) INTO v_snapshot FROM collections c WHERE c.collection_id = p_collection_id;
  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'Collection % not found.', p_collection_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by_admin_id, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'collection', p_collection_id::TEXT, v_snapshot, p_reason);

  DELETE FROM collection_payment_splits WHERE collection_id = p_collection_id;
  DELETE FROM collections WHERE collection_id = p_collection_id;
END;
$function$;

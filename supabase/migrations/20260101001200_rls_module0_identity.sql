-- ============================================================================
-- 0012_rls_module0_identity.sql
-- MANA LINE — RLS: helper functions (app.*) + Module 0 (Identity Network)
--
-- ASSUMPTION / INTEGRATION GAP (flag for master chat — see END RESULT of the
-- RLS session): the schema doc (03_Database_Schema.md) does not define how a
-- Supabase `auth.uid()` session maps to `persons.person_id`. There is no
-- `persons.auth_user_id` (or similar) column in the locked schema, and the
-- API spec only says "Bearer JWT issued at login". Two ways this could work:
--   (a) persons.person_id is embedded as a custom claim in the JWT
--       (`auth.jwt() ->> 'person_id'`), with Supabase Auth issuing custom
--       claims at login, OR
--   (b) a `persons.auth_user_id UUID` column 1:1 with `auth.users.id` is
--       added, and app.current_person_id() looks it up by `auth.uid()`.
-- This migration implements app.current_person_id() using (a) — a JWT claim
-- called 'person_id' — because it requires no schema change (this session is
-- forbidden from touching schema migrations 0001-0011). If the auth
-- integration actually issues plain Supabase Auth sessions without a custom
-- person_id claim, master chat MUST either configure a custom-claims hook
-- that injects person_id, or ask the schema chat to add
-- persons.auth_user_id and swap the body of app.current_person_id() below
-- for a lookup query. Every policy in this entire RLS body of work depends
-- on this function being correct — it is the single highest-leverage
-- integration point in the whole deliverable.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS app;

-- CRITICAL: unlike the `public` schema (which Supabase's platform setup
-- grants USAGE on to anon/authenticated/service_role automatically), a
-- custom schema like `app` gets NO implicit grants. Every single RLS policy
-- in this entire project calls into app.* helper functions, so without
-- these two grants, PostgREST's authenticated/anon roles get "permission
-- denied for schema app" on every single request — a full outage, not a
-- partial one. This must run before any app.* function is created below so
-- future functions are covered by the default-privileges grant too.
GRANT USAGE ON SCHEMA app TO authenticated, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT EXECUTE ON FUNCTIONS TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- app.current_person_id()
-- Resolves the calling user's persons.person_id from the JWT 'person_id'
-- custom claim. Returns NULL if not present (e.g. service_role calls, which
-- bypass RLS anyway, or an unauthenticated/anon request).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_person_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json ->> 'person_id', '')::BIGINT;
$$;

COMMENT ON FUNCTION app.current_person_id() IS
  'Current person_id from JWT custom claim "person_id". ASSUMPTION flagged in 0012 header — confirm auth integration actually sets this claim.';

-- ----------------------------------------------------------------------------
-- app.active_membership_id(p_business_id, p_role)
-- Returns the membership_id for the current person as an ACTIVE holder of
-- p_role in p_business_id, or NULL if none. "Active" here means
-- membership_status = 'Active' — Pending/Suspended/Removed/Disabled all
-- correctly return NULL, per BR-203 (owner-side lock is fully independent
-- per tenancy).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.active_membership_id(p_business_id UUID, p_role TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT bm.membership_id
  FROM business_members bm
  WHERE bm.business_id = p_business_id
    AND bm.person_id = app.current_person_id()
    AND bm.role::text = p_role
    AND bm.membership_status = 'Active'
  LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- app.is_owner(p_business_id)
-- TRUE only if the current person is the Owner of that specific business.
-- Checked two ways (businesses.owner_person_id is the source of truth;
-- business_members role='Owner' is the membership-table mirror) — both must
-- agree in a healthy dataset, but we accept either so an Owner never gets
-- locked out by a membership-row bookkeeping gap. NEVER "is Owner anywhere".
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.is_owner(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM businesses b
    WHERE b.business_id = p_business_id
      AND b.owner_person_id = app.current_person_id()
  )
  OR app.active_membership_id(p_business_id, 'Owner') IS NOT NULL;
$$;

-- ----------------------------------------------------------------------------
-- app.is_active_agent(p_business_id) / app.is_active_investor / app.is_active_customer
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.is_active_agent(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT app.active_membership_id(p_business_id, 'Agent') IS NOT NULL; $$;

CREATE OR REPLACE FUNCTION app.is_active_investor(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT app.active_membership_id(p_business_id, 'Investor') IS NOT NULL; $$;

CREATE OR REPLACE FUNCTION app.is_active_customer(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$ SELECT app.active_membership_id(p_business_id, 'Customer') IS NOT NULL; $$;

-- ----------------------------------------------------------------------------
-- app.agent_permission(p_business_id, p_column)
-- Looks up a single boolean column on agent_permissions for the current
-- person's ACTIVE Agent membership in p_business_id. Returns FALSE (never
-- NULL) if the person is not an active Agent there, or if no permission
-- profile row exists yet (fail-closed default, matches "default to no
-- access when ambiguous" instruction).
-- NOTE: dynamic column lookup via to_jsonb is used because there are ~18
-- permission flags (BR-073-080) and a policy-per-flag switch would be
-- unreadable; this is read-only introspection of our own row, not
-- user-supplied SQL, so it is not an injection risk.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.agent_permission(p_business_id UUID, p_column TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_membership_id UUID;
  v_agent_id UUID;
  v_result BOOLEAN;
BEGIN
  v_membership_id := app.active_membership_id(p_business_id, 'Agent');
  IF v_membership_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT a.agent_id INTO v_agent_id FROM agents a WHERE a.membership_id = v_membership_id;
  IF v_agent_id IS NULL THEN
    RETURN FALSE;
  END IF;

  EXECUTE format(
    'SELECT (to_jsonb(ap.*) ->> %L)::BOOLEAN FROM agent_permissions ap WHERE ap.agent_id = $1 ORDER BY ap.updated_at DESC LIMIT 1',
    p_column
  ) INTO v_result USING v_agent_id;

  RETURN COALESCE(v_result, FALSE);
END;
$$;

COMMENT ON FUNCTION app.agent_permission(UUID, TEXT) IS
  'Fail-closed lookup of a single agent_permissions boolean flag for the current person''s active Agent membership in a business. FALSE if not an active agent, no profile row, or the flag is off/null.';

-- ----------------------------------------------------------------------------
-- app.agent_covers_customer(p_customer_id)
-- TRUE if the current person is the ACTIVE assigned agent for that customer
-- (customers.assigned_agent_membership_id), per AG-004's PERMISSION section
-- scoping Customer visibility to assigned customers, not the whole business.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.agent_covers_customer(p_customer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM customers c
    JOIN business_members bm ON bm.membership_id = c.assigned_agent_membership_id
    WHERE c.customer_id = p_customer_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
      AND bm.role = 'Agent'
  );
$$;

-- ----------------------------------------------------------------------------
-- app.is_own_customer_row(p_customer_id) — the Customer viewing their own row
-- app.is_own_investment_row(p_investment_id) — the Investor viewing their own
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.is_own_customer_row(p_customer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM customers c
    JOIN business_members bm ON bm.membership_id = c.membership_id
    WHERE c.customer_id = p_customer_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
  );
$$;

CREATE OR REPLACE FUNCTION app.is_own_investment_row(p_investment_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM investments inv
    JOIN investors i ON i.investor_id = inv.investor_id
    JOIN business_members bm ON bm.membership_id = i.membership_id
    WHERE inv.investment_id = p_investment_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
  );
$$;

-- ============================================================================
-- MODULE 0 — IDENTITY NETWORK (Global, Cross-Business)
--
-- These tables are NOT business-scoped (persons is the cross-tenant global
-- identity spine, BR-178). RLS here is deliberately narrower than
-- "any business member can see": a person may only read/edit their OWN
-- identity data, full stop — no Owner/Agent gets blanket read access to
-- another person's global identity row just by sharing a business, because
-- that would leak identity data across tenancies (violates BR-202/203's
-- "no cross-tenancy leakage" invariant even though these rows aren't
-- themselves business-scoped).
--
-- The one deliberate exception: Owners/Agents need to see the identity
-- fields (name, photo, etc.) of customers/agents/investors who are ACTUALLY
-- members of their business, in order to render customer/agent/investor
-- lists and profiles. That access is granted, narrowly, via the
-- business_members join — never a blanket "all persons" policy.
-- ============================================================================

ALTER TABLE persons ENABLE ROW LEVEL SECURITY;

-- Self access: every person can always read/update their own identity row.
CREATE POLICY persons_self_select ON persons
  FOR SELECT
  USING (person_id = app.current_person_id());

CREATE POLICY persons_self_update ON persons
  FOR UPDATE
  USING (person_id = app.current_person_id())
  WITH CHECK (person_id = app.current_person_id());

-- Business-partner visibility: an Owner/Agent may read the identity row of
-- any person who holds an ACTIVE membership (any role) in a business where
-- the requester is an active Owner, OR an active Agent with
-- can_view_customers (scoped further to assigned customers is enforced at
-- the `customers` table level in 0014 — this policy only covers the
-- `persons` identity fields themselves, which are less sensitive than
-- financial data and needed for basic list rendering).
-- Negative case this prevents: a person with NO shared active business
-- membership with the target can never read the target's persons row —
-- prevents using `persons` as a global people-search/enumeration surface.
-- ----------------------------------------------------------------------------
-- app.shares_active_business(p_target_person_id)
-- TRUE if the current person is an active Owner, or an active Agent with
-- can_view_customers, in ANY business where p_target_person_id also holds
-- an active membership (any role). SECURITY DEFINER so it bypasses RLS on
-- business_members internally — this is required, not optional: the
-- persons_business_partner_select policy below queries business_members,
-- and business_members has its own RLS policies; without routing through a
-- SECURITY DEFINER function (owned by the table owner, which bypasses RLS),
-- Postgres detects the resulting evaluation as "infinite recursion detected
-- in policy for relation business_members" and refuses to run the query at
-- all. Every other policy in this project already goes through app.*
-- helpers for exactly this reason — this function closes the one place
-- that pattern was missed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.shares_active_business(p_target_person_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM business_members target_bm
    JOIN business_members requester_bm
      ON requester_bm.business_id = target_bm.business_id
    WHERE target_bm.person_id = p_target_person_id
      AND target_bm.membership_status = 'Active'
      AND requester_bm.person_id = app.current_person_id()
      AND requester_bm.membership_status = 'Active'
      AND (
        requester_bm.role = 'Owner'
        OR (requester_bm.role = 'Agent' AND app.agent_permission(requester_bm.business_id, 'can_view_customers'))
      )
  );
$$;

CREATE OR REPLACE FUNCTION app.is_owner_of_any_shared_business(p_target_person_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM business_members target_bm
    JOIN business_members requester_bm ON requester_bm.business_id = target_bm.business_id
    WHERE target_bm.person_id = p_target_person_id
      AND target_bm.membership_status = 'Active'
      AND requester_bm.person_id = app.current_person_id()
      AND requester_bm.membership_status = 'Active'
      AND requester_bm.role = 'Owner'
  );
$$;

CREATE POLICY persons_business_partner_select ON persons
  FOR SELECT
  USING (app.shares_active_business(persons.person_id));

-- No INSERT/DELETE policy for any role: person rows are created exclusively
-- by registration/onboarding server-side flows (service_role), never
-- directly by an authenticated client. No hard-delete exists in this schema
-- at all (BR-002/127).

-- person_id_history: append-only audit of MLID upgrades. Read-scoped like
-- persons; NEVER client-writable (populated by the MLTI->MLPI upgrade
-- function under service_role).
ALTER TABLE person_id_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY person_id_history_self_select ON person_id_history
  FOR SELECT
  USING (person_id = app.current_person_id());

CREATE POLICY person_id_history_business_partner_select ON person_id_history
  FOR SELECT
  USING (app.is_owner_of_any_shared_business(person_id_history.person_id));
-- No INSERT policy for any authenticated role (Owner included) — write-once,
-- system/trigger-populated only, per the briefing's explicit instruction.

-- person_addresses: self + Owner-of-shared-business (Owners need address for
-- collection routing, cross-lender alert per Addendum #6). Agents get it too
-- since routes/collection depend on address — gated by can_view_customers,
-- mirroring persons above.
ALTER TABLE person_addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY person_addresses_self_all ON person_addresses
  FOR ALL
  USING (person_id = app.current_person_id())
  WITH CHECK (person_id = app.current_person_id());

CREATE POLICY person_addresses_business_partner_select ON person_addresses
  FOR SELECT
  USING (app.shares_active_business(person_addresses.person_id));

-- devices: strictly self-only. No business partner ever needs to see another
-- person's device fingerprint/registration — this is a security control
-- surface (Single Device Policy, BR-152/197), not a business data surface.
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY devices_self_all ON devices
  FOR ALL
  USING (person_id = app.current_person_id())
  WITH CHECK (person_id = app.current_person_id());

-- otp_verifications: strictly self-only, and even self should arguably not
-- see otp_code_hash — but column-level security is out of scope for RLS
-- (row-level only); flagged in END RESULT as a candidate for a view that
-- excludes otp_code_hash if the client ever queries this table directly
-- rather than only through a server-side OTP-verify endpoint.
ALTER TABLE otp_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY otp_verifications_self_select ON otp_verifications
  FOR SELECT
  USING (person_id = app.current_person_id());
-- No client INSERT/UPDATE policy: OTP issuance/verification must go through
-- a server-side function (service_role) that can actually check the code,
-- rate-limit, and mark Expired — never a direct client write to this table.

-- identity_documents: self + Owner/Agent(can_view_customers) of a shared
-- active business, same pattern as person_addresses. Customers uploading
-- their own Aadhaar/photo need self-INSERT.
ALTER TABLE identity_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY identity_documents_self_all ON identity_documents
  FOR ALL
  USING (person_id = app.current_person_id())
  WITH CHECK (person_id = app.current_person_id());

CREATE POLICY identity_documents_business_partner_select ON identity_documents
  FOR SELECT
  USING (app.shares_active_business(identity_documents.person_id));

-- duplicate_suspects: judgment call — flagged as ambiguous in the screen
-- specs (this is primarily a Support/back-office concern, SP-001-adjacent).
-- Erring restrictive: no authenticated-client role gets a policy here at
-- all. RLS is enabled (deny-all for anon/authenticated), and all reads/
-- writes happen via service_role from the (out-of-scope, future) Support
-- tool. Flagged explicitly in END RESULT.
ALTER TABLE duplicate_suspects ENABLE ROW LEVEL SECURITY;
-- (No CREATE POLICY here — intentional deny-all for client roles.)

-- ----------------------------------------------------------------------------
-- app.business_id_for_membership(p_membership_id) / app.business_id_for_customer(p_customer_id)
-- Generic SECURITY DEFINER resolvers used throughout Modules 2-8's RLS
-- (0014-0017): dozens of policies there need "which business does this
-- membership/customer row belong to" as an input to app.is_owner(),
-- app.agent_permission(), etc. Every one of those was originally written as
-- an inline `(SELECT business_id FROM business_members WHERE ...)`
-- subquery directly in the policy — which, combined with business_members'
-- own RLS policies, is exactly the same infinite-recursion trap fixed above
-- for persons/person_addresses/identity_documents. These two functions are
-- the single fix point for that entire class of bug across every later
-- module; 0014-0017 have been rewritten to call these instead of inlining
-- the subquery themselves.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.business_id_for_membership(p_membership_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT business_id FROM business_members WHERE membership_id = p_membership_id;
$$;

CREATE OR REPLACE FUNCTION app.business_id_for_customer(p_customer_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT bm.business_id
  FROM business_members bm
  JOIN customers c ON c.membership_id = bm.membership_id
  WHERE c.customer_id = p_customer_id;
$$;

CREATE OR REPLACE FUNCTION app.membership_belongs_to_current_person(p_membership_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members bm
    WHERE bm.membership_id = p_membership_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
  );
$$;

CREATE OR REPLACE FUNCTION app.own_active_agent_membership_permits(p_membership_id UUID, p_permission_column TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members bm
    WHERE bm.membership_id = p_membership_id
      AND bm.person_id = app.current_person_id()
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
      AND app.agent_permission(bm.business_id, p_permission_column)
  );
$$;

-- Belt-and-suspenders: explicit blanket grant on every app.* function
-- created above, in case ALTER DEFAULT PRIVILEGES semantics don't retroactively
-- cover objects created earlier in this same transaction/session in every
-- Postgres version this runs against. Cheap and idempotent to repeat.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO authenticated, anon;

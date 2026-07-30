-- ============================================================================
-- 0013_rls_module1_tenancy.sql
-- MANA LINE — RLS: Module 1 (Tenancy / Business)
-- Depends on: 0012 (app.* helper functions)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- businesses
-- Owner: full access to their own business row.
-- Agent/Investor/Customer: read-only, only while their membership is Active.
-- Prevents: any role reading a business they hold no active membership in
-- (no public/anon browse of arbitrary businesses via this table — CW-002/
-- IW-002 "Find A Business" browse is a distinct, deliberately public search
-- surface and is handled by a SECURITY DEFINER function, not by exposing
-- `businesses` broadly; flagged in END RESULT for master chat to confirm
-- CW-002/IW-002 are implemented via RPC, not a direct table SELECT).
-- ----------------------------------------------------------------------------
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;

CREATE POLICY businesses_owner_all ON businesses
  FOR ALL
  USING (owner_person_id = app.current_person_id())
  WITH CHECK (owner_person_id = app.current_person_id());

CREATE POLICY businesses_member_select ON businesses
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    OR app.is_active_investor(business_id)
    OR app.is_active_customer(business_id)
  );

-- ----------------------------------------------------------------------------
-- locations — permanent, geography-wide MASTER DATA shared across ALL
-- businesses (BR-126/127/130), not tenant-scoped. Read access is safe for
-- any authenticated person (it's just village/pin-code/district reference
-- data, needed for address entry everywhere). Writes: judgment call — no
-- screen spec grants any role direct write access to master locations; this
-- looks like a platform/service_role-managed reference table. Erring
-- restrictive: no client INSERT/UPDATE policy at all.
-- ----------------------------------------------------------------------------
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY locations_authenticated_select ON locations
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- ----------------------------------------------------------------------------
-- operating_areas — business-scoped. Owner: full. Agent: read-only, and only
-- if assigned to that area (agent_area_assignments) OR generally
-- can_view_dashboard (areas feed AG-001 dashboard) — erring toward the
-- narrower assigned-area read plus a dashboard-level read, both granted.
-- Investor/Customer: no direct need per any screen spec — no policy.
-- ----------------------------------------------------------------------------
ALTER TABLE operating_areas ENABLE ROW LEVEL SECURITY;

CREATE POLICY operating_areas_owner_all ON operating_areas
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY operating_areas_agent_select ON operating_areas
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    AND (
      app.agent_permission(business_id, 'can_view_dashboard')
      OR EXISTS (
        SELECT 1 FROM agents a
        JOIN agent_area_assignments aaa ON aaa.agent_id = a.agent_id
        WHERE a.membership_id = app.active_membership_id(operating_areas.business_id, 'Agent')
          AND aaa.operating_area_id = operating_areas.operating_area_id
          AND aaa.removed_at IS NULL
      )
    )
  );

-- ----------------------------------------------------------------------------
-- routes / route_locations — Owner-managed (BR-027/131-138). Agent needs
-- read access to routes they're the default_agent_id on, or more broadly to
-- run AG-003 Today's Route — scoping to "assigned to this agent's route" per
-- default_agent_id, matching AG-003's own route ownership model.
-- ----------------------------------------------------------------------------
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY routes_owner_all ON routes
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY routes_agent_select ON routes
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    AND default_agent_id = app.active_membership_id(business_id, 'Agent')
  );

ALTER TABLE route_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY route_locations_owner_all ON route_locations
  FOR ALL
  USING (EXISTS (SELECT 1 FROM routes r WHERE r.route_id = route_locations.route_id AND app.is_owner(r.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM routes r WHERE r.route_id = route_locations.route_id AND app.is_owner(r.business_id)));

CREATE POLICY route_locations_agent_select ON route_locations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM routes r
      WHERE r.route_id = route_locations.route_id
        AND app.is_active_agent(r.business_id)
        AND r.default_agent_id = app.active_membership_id(r.business_id, 'Agent')
    )
  );

-- ----------------------------------------------------------------------------
-- business_agreements — the legal text/PDF templates. Owner: full manage.
-- Everyone with an active membership needs to be able to READ the current
-- agreement for their own role type, in order to accept it (LR/onboarding
-- flows, agreement_acceptances below). Scoped to agreement_type matching the
-- viewer's own role — an Investor should not need to read the Agent
-- agreement text, but this is low-sensitivity legal template content, so
-- erring toward allowing any active member to read any agreement template
-- for their own business (simpler, and the spec doesn't suggest
-- role-siloing of the legal text itself, only of financial figures).
-- ----------------------------------------------------------------------------
ALTER TABLE business_agreements ENABLE ROW LEVEL SECURITY;

CREATE POLICY business_agreements_owner_all ON business_agreements
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY business_agreements_member_select ON business_agreements
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    OR app.is_active_investor(business_id)
    OR app.is_active_customer(business_id)
  );

-- ----------------------------------------------------------------------------
-- agreement_acceptances — permanent per-person audit trail. Self-insert (the
-- person accepting, at OTP-confirmed acceptance time) + self-select. Owner
-- of the relevant business can read (needs to confirm acceptance happened,
-- OW-013). No UPDATE/DELETE policy for anyone — permanent record, BR pattern
-- ("never an UPDATE that erases the prior value").
-- ----------------------------------------------------------------------------
ALTER TABLE agreement_acceptances ENABLE ROW LEVEL SECURITY;

CREATE POLICY agreement_acceptances_self_select ON agreement_acceptances
  FOR SELECT
  USING (person_id = app.current_person_id());

CREATE POLICY agreement_acceptances_self_insert ON agreement_acceptances
  FOR INSERT
  WITH CHECK (person_id = app.current_person_id());

CREATE POLICY agreement_acceptances_owner_select ON agreement_acceptances
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM business_agreements ba
      WHERE ba.agreement_id = agreement_acceptances.agreement_id
        AND app.is_owner(ba.business_id)
    )
  );

-- ----------------------------------------------------------------------------
-- business_members — THE central polymorphic table. This is the most
-- security-critical table in the whole schema: every other policy in this
-- entire project ultimately calls back to it via the app.* helper functions.
-- Owner: full manage of every membership row in their own business.
-- A person can always read their OWN membership rows (any business, any
-- role) — needed for BR-208 Select-Business / role-switcher navigation.
-- Agent (can_view_customers): read-only on Customer-role rows for THEIR
-- assigned customers only — not the whole business's member list. Explicitly
-- does NOT get read on other Agent/Investor/Owner membership rows (that's
-- workforce/investor-management data, Owner-only per OW-002/OW-003).
-- Negative case: a Customer never sees any other person's business_members
-- row, in this or any other business, and an Agent never sees Owner/other-
-- Agent/Investor rows via this table.
-- ----------------------------------------------------------------------------
ALTER TABLE business_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY business_members_owner_all ON business_members
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY business_members_self_select ON business_members
  FOR SELECT
  USING (person_id = app.current_person_id());

CREATE POLICY business_members_agent_select_assigned_customers ON business_members
  FOR SELECT
  USING (
    role = 'Customer'
    AND app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_view_customers')
    AND EXISTS (
      SELECT 1 FROM customers c
      WHERE c.membership_id = business_members.membership_id
        AND c.assigned_agent_membership_id = app.active_membership_id(business_members.business_id, 'Agent')
    )
  );

-- ----------------------------------------------------------------------------
-- membership_requests — self-service join requests (CW-002/IW-002).
-- Requester: self-insert + self-select. Owner: full manage (approve/reject)
-- for requests targeting their business.
-- ----------------------------------------------------------------------------
ALTER TABLE membership_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY membership_requests_self_select ON membership_requests
  FOR SELECT
  USING (person_id = app.current_person_id());

CREATE POLICY membership_requests_self_insert ON membership_requests
  FOR INSERT
  WITH CHECK (person_id = app.current_person_id());

CREATE POLICY membership_requests_owner_all ON membership_requests
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

-- ----------------------------------------------------------------------------
-- account_periods — Business Date Engine. Owner: full manage. Agent: read
-- (and needs to see it's assigned to them for OW-011-adjacent workflows) +
-- UPDATE limited to submitting (status -> 'Submitted') their own assigned
-- period, since AG-workflows submit day/period closure. Approval
-- (status -> 'Approved') stays Owner-only (approved_by_person_id column
-- makes this explicit in the schema, and OW-013/OW-011 gate approval to
-- Owner).
-- Judgment call: I did NOT give Agent a blanket UPDATE policy, only allow it
-- via WITH CHECK that the row stays assigned to them and doesn't set
-- approved_by_person_id/approved_at — Postgres RLS can't diff old vs new
-- column-by-column in a simple USING/CHECK, so the safer approach is to
-- deny Agent UPDATE at the RLS layer entirely and require submission to go
-- through a SECURITY DEFINER function that enforces the status transition
-- rules precisely. Flagged in END RESULT: Agent submission of account
-- periods should be done via an RPC, not a raw client UPDATE.
-- ----------------------------------------------------------------------------
ALTER TABLE account_periods ENABLE ROW LEVEL SECURITY;

CREATE POLICY account_periods_owner_all ON account_periods
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY account_periods_agent_select ON account_periods
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    AND agent_membership_id = app.active_membership_id(business_id, 'Agent')
  );
-- No client-side Agent INSERT/UPDATE policy — see note above; submission
-- must go through a SECURITY DEFINER RPC that validates the transition.

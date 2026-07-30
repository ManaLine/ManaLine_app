-- =============================================================================
-- 0035 — Module 23: Workforce Onboarding RPCs, Pending-Agent Visibility Fix,
-- Group Loan Agent Rename/Delete Policies
-- =============================================================================
-- Closes three confirmed gaps found during independent review of OW-002 and
-- OW-015 (never previously cross-checked against live RLS):
--
-- 1. owner_api_service.dart's registerNewAgent() does a raw client-side
--    INSERT into `persons` — persons has no INSERT policy for any
--    authenticated role (0012, "created exclusively by registration/
--    onboarding server-side flows"). Every real call fails.
--
-- 2. owner_api_service.dart's searchByMlid() queries `persons` directly to
--    find a candidate Agent to add — but persons_business_partner_select
--    (0012) requires the TARGET to already hold an Active membership in a
--    business the requester owns/agents. The whole point of this search is
--    finding someone who does NOT share a business yet, so this always
--    returns zero rows against real data.
--
-- 3. fetchAgents()/fetchAgentProfile() embed `persons!inner(...)` under
--    business_members/agents. Because persons_business_partner_select also
--    requires the target's `membership_status = 'Active'`, any Agent still
--    Pending Invitation/Pending Acceptance is invisible via that embed —
--    the INNER JOIN drops the whole row. OW-002's own C2 dashboard shows
--    "Pending Invitations"/"Pending Acceptance" counts that its own C3 list
--    can never actually display.
--
-- FIX for (1)/(2): two new SECURITY DEFINER RPCs, same pattern as every
-- other Owner-side gap already fixed this way (0021 owner_update_customer_*,
-- 0034 create_business_with_owner).
--
-- FIX for (3): an ADDITIVE persons SELECT policy — does not touch the
-- existing persons_business_partner_select policy, only adds a second,
-- narrower one: an Owner may see the identity fields of anyone holding ANY
-- (not just Active) business_members row in a business that Owner owns.
-- This is strictly narrower than a global people-search (still gated on a
-- real business_members row existing, just not gated on its status) so it
-- does not reopen the "no global people-search via this table" guarantee
-- persons_business_partner_select was written to protect.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.owner_owns_pending_or_active_member(p_target_person_id)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_owns_pending_or_active_member(p_target_person_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.person_id = p_target_person_id
      AND b.owner_person_id = app.current_person_id()
  );
$$;

COMMENT ON FUNCTION app.owner_owns_pending_or_active_member(BIGINT) IS
  'Closes the OW-002 pending-agent visibility gap: TRUE if the target person holds ANY (not just Active) business_members row in a business owned by the caller. Deliberately narrower than a global search — still requires a real, already-created membership row to exist, unlike a bare persons lookup.';

CREATE POLICY persons_owner_pending_member_select ON persons
  FOR SELECT
  USING (app.owner_owns_pending_or_active_member(persons.person_id));

-- -----------------------------------------------------------------------------
-- app.register_new_agent — atomic persons + business_members + agents +
-- agent_permissions creation, mirrors owner_api_service.dart's original
-- (broken) client-side sequence exactly, just moved server-side.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.register_new_agent(
  p_business_id UUID,
  p_full_name VARCHAR,
  p_father_husband_name VARCHAR,
  p_gender_digit CHAR(1),
  p_mobile_number VARCHAR,
  p_aadhaar_number VARCHAR
)
RETURNS UUID -- returns the new agent_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_last8 VARCHAR(8);
  v_mlid VARCHAR(13);
  v_person_id BIGINT;
  v_membership_id UUID;
  v_agent_id UUID;
  v_permission_profile_id UUID;
  v_existing_person_id BIGINT;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  v_last8 := RIGHT(p_aadhaar_number, 8);
  v_mlid := 'MLPI' || p_gender_digit || v_last8;

  -- COLLISION HANDLING — not a regenerate-and-retry loop. MLID here is a
  -- fixed 13-char, fully deterministic derivation (BR-181/182: 'MLPI' +
  -- gender_digit + last-8-of-Aadhaar) with no room to append a
  -- distinguishing suffix — the same inputs always produce the same
  -- output, so blindly retrying the same INSERT would just hit the same
  -- collision again. Two real cases instead:
  --   (a) persons.aadhaar_number already has its own UNIQUE constraint,
  --       so a genuinely duplicate Aadhaar is already blocked before this
  --       even runs — that's the common case and gives a clear error on
  --       its own.
  --   (b) A DIFFERENT Aadhaar number can coincidentally share the same
  --       last-8-digits + gender_digit as an existing person — rare, but
  --       possible, and not a duplicate-identity situation at all. This
  --       still can't be "retried" (no alternate value to try), so it
  --       fails with a specific, actionable message instead of a raw
  --       Postgres constraint-violation error.
  SELECT person_id INTO v_existing_person_id FROM persons WHERE mlid = v_mlid;
  IF v_existing_person_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM persons WHERE person_id = v_existing_person_id AND aadhaar_number = p_aadhaar_number) THEN
      RAISE EXCEPTION 'This Aadhaar number is already registered under an existing account.' USING ERRCODE = '23505';
    ELSE
      RAISE EXCEPTION 'MLID collision: the last 8 digits of this Aadhaar number, combined with gender, already match a different existing person. This is a rare coincidence, not a duplicate — please contact support to resolve manually.' USING ERRCODE = '23505';
    END IF;
  END IF;

  INSERT INTO persons (
    mlid, mlid_type, gender_digit, full_name, father_husband_name,
    mobile_number, aadhaar_number, registration_source, customer_type
  ) VALUES (
    v_mlid, 'MLPI', p_gender_digit, p_full_name, p_father_husband_name,
    p_mobile_number, p_aadhaar_number, 'Owner', 'New'
  ) RETURNING person_id INTO v_person_id;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Agent', 'Pending Invitation',
    'Pending Verification', 'Direct Registration', app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO agents (membership_id, person_id, joined_date)
  VALUES (v_membership_id, v_person_id, CURRENT_DATE)
  RETURNING agent_id INTO v_agent_id;

  INSERT INTO agent_permissions (agent_id)
  VALUES (v_agent_id)
  RETURNING permission_profile_id INTO v_permission_profile_id;

  UPDATE business_members SET permission_profile_id = v_permission_profile_id
  WHERE membership_id = v_membership_id;

  RETURN v_agent_id;
END;
$$;

COMMENT ON FUNCTION app.register_new_agent(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR) IS
  'Fixes the confirmed gap: persons has no client INSERT policy, so owner_api_service.dart''s original raw insert always failed under real RLS. Same 4-table sequence as before, just server-side.';

GRANT EXECUTE ON FUNCTION app.register_new_agent(UUID, VARCHAR, VARCHAR, CHAR, VARCHAR, VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.owner_search_person_by_mlid — replaces searchByMlid's direct `persons`
-- SELECT. Only usable by an authenticated Owner (any business); does NOT
-- require the target to already share a business, since finding such a
-- person is the entire point of "Add Existing Agent." Returns only the
-- minimal identity fields the C5 sheet needs, matching the caller's
-- existing AgentSummary shape.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_search_person_by_mlid(p_mlid VARCHAR)
RETURNS TABLE (person_id BIGINT, full_name VARCHAR, mlid VARCHAR, mobile_number VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.person_id, p.full_name, p.mlid, p.mobile_number
  FROM persons p
  WHERE p.mlid = p_mlid
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION app.owner_search_person_by_mlid(VARCHAR) IS
  'Fixes the confirmed gap: persons_business_partner_select requires the target to already share an active business with the caller, which is never true for a genuine "add existing agent by MLID" candidate. Gated on caller being SOME business''s Owner (not narrowed to one specific business, matching the screen''s own "search then decide" flow), not on the target sharing anything.';

GRANT EXECUTE ON FUNCTION app.owner_search_person_by_mlid(VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- loan_groups — Agent rename/delete (confirmed gap: only owner_all covers
-- ALL verbs; agent policies were SELECT/INSERT only, per OW-015's own spec
-- explicitly granting Agents both actions).
-- -----------------------------------------------------------------------------
CREATE POLICY loan_groups_agent_update_own ON loan_groups
  FOR UPDATE
  USING (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_issue_loans')
    AND created_by_membership_id = app.active_membership_id(business_id, 'Agent')
  )
  WITH CHECK (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_issue_loans')
    AND created_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

CREATE POLICY loan_groups_agent_delete_own ON loan_groups
  FOR DELETE
  USING (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_issue_loans')
    AND created_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

COMMENT ON POLICY loan_groups_agent_delete_own ON loan_groups IS
  'Group Balance = ₹0 gating (per OW-015 spec) is enforced app-side (screen checks detail.eligibleForDeletion before showing the action), consistent with how other financial thresholds in this schema are gated at the app layer rather than in RLS.';

-- -----------------------------------------------------------------------------
-- agent_permissions.can_record_expenses — CONFIRMED in
-- 07_API_Specification_ADDENDUM_v7_Agent_Expense_Permission.md item 13,
-- but never actually applied to the live schema. The independent review
-- flagged ow_002_workforce_management.dart's `can_record_expenses` label
-- as referencing a nonexistent column — that diagnosis was WRONG: it's a
-- locked, confirmed addendum decision (OFF by default, same pattern as
-- can_apply_penalty/BR-236) whose migration simply never ran. Applying it
-- now closes the actual gap rather than removing a legitimate feature.
-- -----------------------------------------------------------------------------
ALTER TABLE agent_permissions ADD COLUMN can_record_expenses BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN agent_permissions.can_record_expenses IS
  'ADDENDUM v7 item 13 — gates Agent-side expense entry (FIN-002). OFF by default; Owner must explicitly grant, same UX pattern as every other agent_permissions toggle.';

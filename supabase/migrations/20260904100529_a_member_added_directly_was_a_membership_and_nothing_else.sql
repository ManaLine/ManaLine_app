-- OW-014's direct add wrote a business_members row with membership_status
-- 'Active' and NOTHING ELSE. No agents row, no customers row, no investors row,
-- no agent_permissions.
--
-- global_workflow_state.attachNewPersonToBusiness did one insert and returned
-- the membership_id. Every other path that makes somebody Active --
-- create_business_with_owner, decide_membership_request, register_new_agent,
-- owner_api_service.addExistingAgent -- also creates the role-side entity,
-- because that is what the workspaces read:
--
--     .from('agents').select('agent_id').eq('membership_id', ...).single()
--
-- and .single() throws on zero rows. An Agent added this way opened a
-- workspace that crashed; a Customer added this way was invisible to every
-- customer list, since those join through customers.
--
-- Found while walking the invitation-accept path in the same batch. It matters
-- more now than it did last week: OW-014 has just become the ONLY way to add an
-- agent from Workforce Management and the assign-agent step of setup, so this
-- path went from rarely used to the main road.
--
-- agent_permissions comes with it. Every column but agent_id defaults true, and
-- without the row fetchPermissions returns AgentPermissions() with everything
-- false -- the agent gets a workspace that loads and refuses every action,
-- which reads as broken rather than as unpermitted.
--
-- SUPERSEDED IMMEDIATELY by 20260904100614: the verification_status CASE
-- expression resolves to text and threw 42804 on first call. This file is the
-- record of what was applied, not of what works. See the next migration.
--
-- An RPC because it is four writes that must all happen or none, which is the
-- multi-step write this project reserves for Postgres. Every enum literal was
-- read out of enum_range first -- including occupation 'Other-Custom', which is
-- the one that had been wrong in decide_membership_request for months.
CREATE OR REPLACE FUNCTION app.attach_person_to_business(
  p_business_id uuid,
  p_person_id   bigint,
  p_role        text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_role          business_member_role_enum;
  v_membership_id uuid;
  v_agent_id      uuid;
  v_perm_id       uuid;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may add a member to this business.'
      USING ERRCODE = '42501';
  END IF;

  IF p_role NOT IN ('Agent', 'Investor', 'Customer') THEN
    RAISE EXCEPTION 'Invalid role — must be Agent, Investor or Customer.'
      USING ERRCODE = '22023';
  END IF;
  v_role := p_role::business_member_role_enum;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE person_id = p_person_id AND business_id = p_business_id AND role = v_role
   FOR UPDATE;

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      p_person_id, p_business_id, v_role, 'Active',
      CASE WHEN v_role = 'Customer' THEN 'Not Required' ELSE 'Pending Verification' END,
      'Migration/Pre-Existing', app.current_person_id(), now()
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now())
     WHERE membership_id = v_membership_id;
  END IF;

  IF v_role = 'Agent' THEN
    SELECT agent_id INTO v_agent_id FROM agents WHERE membership_id = v_membership_id;
    IF v_agent_id IS NULL THEN
      INSERT INTO agents (membership_id, person_id, joined_date, current_status)
      VALUES (v_membership_id, p_person_id, CURRENT_DATE, 'Active')
      RETURNING agent_id INTO v_agent_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM agent_permissions WHERE agent_id = v_agent_id) THEN
      INSERT INTO agent_permissions (agent_id) VALUES (v_agent_id)
      RETURNING permission_profile_id INTO v_perm_id;
      UPDATE business_members SET permission_profile_id = v_perm_id
       WHERE membership_id = v_membership_id;
    END IF;
  ELSIF v_role = 'Customer' AND NOT EXISTS (
      SELECT 1 FROM customers WHERE membership_id = v_membership_id) THEN
    INSERT INTO customers (membership_id, person_id, occupation,
                           customer_status, customer_since)
    VALUES (v_membership_id, p_person_id, 'Other-Custom', 'Active', CURRENT_DATE);
  ELSIF v_role = 'Investor' AND NOT EXISTS (
      SELECT 1 FROM investors WHERE membership_id = v_membership_id) THEN
    INSERT INTO investors (membership_id, person_id)
    VALUES (v_membership_id, p_person_id);
  END IF;

  RETURN json_build_object('membership_id', v_membership_id, 'role', v_role::text);
END;
$function$;

GRANT EXECUTE ON FUNCTION app.attach_person_to_business(uuid, bigint, text) TO anon, authenticated;

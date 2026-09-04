-- Accepting an invitation left an Agent with no `agents` row -- or would have.
--
-- The previous migration made accept WORK. Walking what was behind it -- a door
-- that had never once opened -- I went looking for what else an accepted
-- membership needs. Three functions create the role-side entity:
-- create_business_with_owner, decide_membership_request and register_new_agent.
-- None of them is the invitation path.
--
-- It matters because agent_customer_state.dart does
--
--     .from('agents').select('agent_id').eq('membership_id', ...).single()
--
-- and `.single()` throws on zero rows. The agent dashboard and agent profile
-- read it the same way, so a missing row is a workspace that crashes on open.
--
-- MEASURED BEFORE BELIEVED: every Agent membership on this database, the two
-- Pending Invitation ones included, already has exactly one agents row and one
-- agent_permissions row. owner_api_service.addExistingAgent writes them at
-- INVITE time, not at accept. So for today's invite path the block below never
-- fires, and I am not claiming it fixes a live break.
--
-- It stays for two reasons. It is the sibling of the identical block in
-- decide_membership_request, so the two ways a membership reaches Active now
-- agree. And global_workflow_state.attachNewPersonToBusiness -- OW-014's direct
-- add -- creates an ACTIVE membership with no role entity at all, which is the
-- same defect in a path this function does not cover. That one is flagged for
-- the OW-014 tranche rather than fixed from here.
--
-- joined_at is NOT defensive: updateMembershipStatus stamps it on the Owner's
-- path and this did not, so a membership going Active down one route carried a
-- joined_at and down the other did not.
--
-- CREATE OR REPLACE is correct and not a breach of the DROP-then-CREATE rule:
-- the parameter list is unchanged, so no second overload can appear. Counted
-- after applying -- 1.

CREATE OR REPLACE FUNCTION app.respond_to_invitation(
  p_membership_id uuid,
  p_accept boolean
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person  bigint := app.current_person_id();
  v_row     business_members%ROWTYPE;
  v_new     membership_status_enum;
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM business_members
   WHERE membership_id = p_membership_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That invitation no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  -- SECURITY DEFINER bypasses RLS, so ownership is checked here by hand. This
  -- is the line that stops somebody answering another person's invitation.
  IF v_row.person_id <> v_person THEN
    RAISE EXCEPTION 'That invitation belongs to somebody else.' USING ERRCODE = '42501';
  END IF;

  IF v_row.membership_status NOT IN ('Pending Invitation', 'Pending Acceptance') THEN
    RAISE EXCEPTION 'This invitation was already answered (%).', v_row.membership_status
      USING ERRCODE = '23514';
  END IF;

  v_new := CASE WHEN p_accept THEN 'Active' ELSE 'Removed' END::membership_status_enum;

  UPDATE business_members
     SET membership_status = v_new,
         joined_at = CASE WHEN p_accept THEN COALESCE(joined_at, now()) ELSE joined_at END
   WHERE membership_id = p_membership_id;

  -- The role-side entity every workspace reads with .single().
  IF p_accept THEN
    IF v_row.role = 'Agent' AND NOT EXISTS (
         SELECT 1 FROM agents WHERE membership_id = p_membership_id) THEN
      INSERT INTO agents (membership_id, person_id, joined_date, current_status)
      VALUES (p_membership_id, v_row.person_id, CURRENT_DATE, 'Active');
    ELSIF v_row.role = 'Customer' AND NOT EXISTS (
         SELECT 1 FROM customers WHERE membership_id = p_membership_id) THEN
      INSERT INTO customers (membership_id, person_id, occupation,
                             customer_status, customer_since)
      VALUES (p_membership_id, v_row.person_id, 'Other', 'Active', CURRENT_DATE);
    ELSIF v_row.role = 'Investor' AND NOT EXISTS (
         SELECT 1 FROM investors WHERE membership_id = p_membership_id) THEN
      INSERT INTO investors (membership_id, person_id)
      VALUES (p_membership_id, v_row.person_id);
    END IF;
  END IF;

  -- verification_status is deliberately untouched. An accepted Agent or
  -- Investor stays 'Pending Verification', which is what sends LR-013 into the
  -- Role Escalation OTP (BR-191); auth-otp-verify sets it to 'Verified' there,
  -- as service_role. Marking it verified here would skip that step entirely.
  RETURN json_build_object(
    'membership_id',       p_membership_id,
    'business_id',         v_row.business_id,
    'role',                v_row.role,
    'membership_status',   v_new,
    'verification_status', v_row.verification_status
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION app.respond_to_invitation(uuid, boolean) TO anon, authenticated;

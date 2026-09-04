-- attach_person_to_business threw on first call:
--
--   42804  column "verification_status" is of type membership_verification_status_enum
--          but expression is of type text
--
-- A CASE WHEN ... THEN 'a' ELSE 'b' END resolves to text; a bare literal in the
-- same position would have been coerced to the enum, but the CASE is not. The
-- cast is explicit now.
--
-- Same shape as the RETURN QUERY varchar/text mismatch already recorded in
-- CLAUDE.md, and the same lesson: CREATE said yes, the first invocation said
-- no. The migration before this one is the record of what was applied; this is
-- the record of what works.

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
      (CASE WHEN v_role = 'Customer' THEN 'Not Required'
            ELSE 'Pending Verification' END)::membership_verification_status_enum,
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

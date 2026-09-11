-- The Owner's rule: adding an Agent or an Investor ASKS them; adding a
-- Customer just adds them.
--
-- attach_person_to_business wrote membership_status 'Active' for all three
-- roles, so nobody was ever asked anything -- the Owner added K Bhaskara
-- Reddy as an Investor and he was simply in, with no request to accept and
-- nothing for the Owner to watch for.
--
-- An Agent and an Investor both get reach into somebody else's book, so both
-- are asked. A Customer is being recorded, not granted anything, and making
-- a borrower accept an invitation before they can be lent to would put a
-- login between a field agent and a collection.
--
-- THE PRECONDITION NOBODY WOULD HAVE SEEN. Sending Agents down the
-- acceptance path means respond_to_invitation, not attach_person_to_business,
-- becomes the function that makes an agent real -- and it creates the agents
-- row WITHOUT the agent_permissions row that attach_person_to_business
-- creates alongside it. Every column of agent_permissions but agent_id
-- defaults true, so a missing row is not "no permissions yet", it is
-- fetchPermissions returning AgentPermissions() with everything FALSE: a
-- workspace that loads and then refuses every action, which reads as broken
-- rather than as unpermitted. That was already true for one live agent
-- before this migration; it would have become true for every new one.
-- Fixed in the function and backfilled below.

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
  v_status        membership_status_enum;
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

  -- Read out of enum_range, not guessed: membership_status_enum is
  -- ('Pending Invitation','Pending Acceptance','Active','Temporarily
  -- Disabled','Suspended','Removed','Pending Approval').
  v_status := CASE WHEN v_role = 'Customer'
                   THEN 'Active'
                   ELSE 'Pending Invitation'
              END::membership_status_enum;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE person_id = p_person_id AND business_id = p_business_id AND role = v_role
   FOR UPDATE;

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      p_person_id, p_business_id, v_role, v_status,
      (CASE WHEN v_role = 'Customer' THEN 'Not Required'
            ELSE 'Pending Verification' END)::membership_verification_status_enum,
      'Migration/Pre-Existing', app.current_person_id(),
      -- Nobody has joined anything until they say yes.
      CASE WHEN v_role = 'Customer' THEN now() ELSE NULL END
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    -- Re-adding somebody who was removed asks again, for the same reason.
    UPDATE business_members
       SET membership_status = v_status, removed_at = NULL,
           joined_at = CASE WHEN v_role = 'Customer'
                            THEN COALESCE(joined_at, now()) ELSE joined_at END
     WHERE membership_id = v_membership_id;
  END IF;

  -- The role-side row is created here ONLY for the role that is active
  -- immediately. An Agent or Investor who has not accepted yet gets theirs
  -- from respond_to_invitation, which is the moment they become real.
  IF v_role = 'Customer' AND NOT EXISTS (
      SELECT 1 FROM customers WHERE membership_id = v_membership_id) THEN
    INSERT INTO customers (membership_id, person_id, occupation,
                           customer_status, customer_since)
    VALUES (v_membership_id, p_person_id, 'Other-Custom', 'Active', CURRENT_DATE);
  END IF;

  RETURN json_build_object(
    'membership_id',     v_membership_id,
    'role',              v_role::text,
    'membership_status', v_status::text
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION app.attach_person_to_business(uuid, bigint, text) TO anon, authenticated;


CREATE OR REPLACE FUNCTION app.respond_to_invitation(p_membership_id uuid, p_accept boolean)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person  bigint := app.current_person_id();
  v_row     business_members%ROWTYPE;
  v_new     membership_status_enum;
  v_agent_id uuid;
  v_perm_id  uuid;
  v_name    text;
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

  IF p_accept THEN
    IF v_row.role = 'Agent' THEN
      SELECT agent_id INTO v_agent_id FROM agents WHERE membership_id = p_membership_id;
      IF v_agent_id IS NULL THEN
        INSERT INTO agents (membership_id, person_id, joined_date, current_status)
        VALUES (p_membership_id, v_row.person_id, CURRENT_DATE, 'Active')
        RETURNING agent_id INTO v_agent_id;
      END IF;
      -- THE MISSING HALF. Without this row every permission reads false and
      -- the Agent gets a workspace that refuses everything.
      IF NOT EXISTS (SELECT 1 FROM agent_permissions WHERE agent_id = v_agent_id) THEN
        INSERT INTO agent_permissions (agent_id) VALUES (v_agent_id)
        RETURNING permission_profile_id INTO v_perm_id;
        UPDATE business_members SET permission_profile_id = v_perm_id
         WHERE membership_id = p_membership_id;
      END IF;
    ELSIF v_row.role = 'Customer' AND NOT EXISTS (
         SELECT 1 FROM customers WHERE membership_id = p_membership_id) THEN
      -- 'Other-Custom', not 'Other'. Copied wrong from the function above.
      INSERT INTO customers (membership_id, person_id, occupation,
                             customer_status, customer_since)
      VALUES (p_membership_id, v_row.person_id, 'Other-Custom', 'Active', CURRENT_DATE);
    ELSIF v_row.role = 'Investor' AND NOT EXISTS (
         SELECT 1 FROM investors WHERE membership_id = p_membership_id) THEN
      INSERT INTO investors (membership_id, person_id)
      VALUES (p_membership_id, v_row.person_id);
    END IF;

    -- Tell the Owner their request was answered.
    --
    -- The Owner sends a request and then has no way to know it landed; the
    -- bell is where everything else that is waiting on them already lives.
    -- notification_type 'Other' is deliberate: notification_type_enum has no
    -- value for somebody joining, and ALTER TYPE ADD VALUE cannot be used in
    -- the same transaction that adds it, so a dedicated type is its own
    -- migration if it is ever wanted. The message carries the meaning.
    SELECT full_name INTO v_name FROM persons WHERE person_id = v_row.person_id;

    INSERT INTO notifications (recipient_person_id, business_id, notification_type,
                               message, related_entity_type, related_entity_uuid)
    SELECT o.person_id, v_row.business_id, 'Other'::notification_type_enum,
           format('%s (%s) has been added to your business.',
                  COALESCE(v_name, 'A member'), v_row.role),
           'business_members', p_membership_id
      FROM business_members o
     WHERE o.business_id = v_row.business_id
       AND o.role = 'Owner'
       AND o.membership_status = 'Active'
       AND o.person_id <> v_row.person_id;
  END IF;

  RETURN json_build_object(
    'membership_id',       p_membership_id,
    'business_id',         v_row.business_id,
    'role',                v_row.role,
    'membership_status',   v_new,
    'verification_status', v_row.verification_status
  );
END;
$function$;


-- The one live agent already in the broken state, from before the function
-- learned to make this row. Backfilled rather than left, because the person
-- holding it has a workspace that refuses every action today.
WITH missing AS (
  SELECT a.agent_id, a.membership_id
    FROM agents a
    LEFT JOIN agent_permissions p ON p.agent_id = a.agent_id
   WHERE p.agent_id IS NULL
), made AS (
  INSERT INTO agent_permissions (agent_id)
  SELECT agent_id FROM missing
  RETURNING agent_id, permission_profile_id
)
UPDATE business_members bm
   SET permission_profile_id = made.permission_profile_id
  FROM made
  JOIN missing ON missing.agent_id = made.agent_id
 WHERE bm.membership_id = missing.membership_id
   AND bm.permission_profile_id IS NULL;

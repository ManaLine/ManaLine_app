-- Accepting a handover made somebody an Owner and nothing else.
--
-- app.create_business_with_owner has always written TWO memberships for the
-- person who registers a business -- Owner and Agent -- because the Owner of a
-- village book works the round themselves. Every one of the five live Owner
-- memberships has an Active Agent membership beside it, and the app is built
-- on that being true.
--
-- respond_business_transfer inserted 'Owner' alone. So the one path that hands
-- an existing book to a new person produced the single state nothing else in
-- the app produces: an owner who cannot collect, has no agents row, no
-- agent_permissions, and does not appear in their own Workforce roster. It was
-- found while checking whether owner-only was reachable at all -- the claim
-- was that it was not, and registration bears that out. This did not.
--
-- The new owner now gets the Agent membership too, mirroring
-- create_business_with_owner exactly: Active, Not Required, with the agents
-- row and the agent_permissions row that must come with it. Every column of
-- agent_permissions but agent_id defaults true, so a MISSING row is not "no
-- permissions yet" -- it is every permission reading false, a workspace that
-- loads and then refuses every action.
--
-- An incoming owner who was ALREADY an agent of this business -- which is the
-- ordinary case for a handover to the person who has been running it -- is
-- reactivated rather than duplicated. uq_business_members_person_business_role
-- would reject a second row anyway; reusing it also keeps their history.
--
-- The OUTGOING owner's Agent membership is still left exactly as it is, along
-- with their Investor and Customer ones. That was deliberate before this
-- change and remains so: handing over the book does not end their work in it.

CREATE OR REPLACE FUNCTION app.respond_business_transfer(p_transfer_id uuid, p_accept boolean, p_reason text DEFAULT NULL::text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_me BIGINT := app.current_person_id();
  t RECORD;
  v_existing UUID;
  v_removed INT;
  v_agent_member UUID;
  v_agent_id UUID;
  v_perm_id UUID;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO t FROM business_transfers
   WHERE transfer_id = p_transfer_id FOR UPDATE;
  IF t IS NULL THEN
    RAISE EXCEPTION 'Transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF t.to_person_id <> v_me THEN
    RAISE EXCEPTION 'This offer was not made to you' USING ERRCODE = '42501';
  END IF;
  IF t.status <> 'Pending' THEN
    RAISE EXCEPTION 'This offer has already been answered' USING ERRCODE = '23514';
  END IF;

  IF NOT p_accept THEN
    UPDATE business_transfers
       SET status = 'Declined', responded_at = now(), decline_reason = p_reason
     WHERE transfer_id = p_transfer_id;
    RETURN json_build_object('status', 'Declined');
  END IF;

  -- Re-checked at accept time, not just at offer time. The offer may have sat
  -- for days while the outgoing owner took an agent float or a settlement
  -- landed in their queue.
  PERFORM app.assert_business_transferable(t.business_id, t.from_person_id, v_me);

  UPDATE businesses SET owner_person_id = v_me, updated_at = now()
   WHERE business_id = t.business_id;

  -- ONLY the Owner role. Their Investor, Customer and Agent memberships are
  -- left exactly as they are.
  UPDATE business_members
     SET membership_status = 'Removed', removed_at = now(), updated_at = now()
   WHERE business_id = t.business_id
     AND person_id = t.from_person_id
     AND role = 'Owner'
     AND membership_status <> 'Removed';
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  -- Incoming owner: reuse an existing Owner row if one is lying around from a
  -- previous transfer, rather than accumulating a second one.
  SELECT membership_id INTO v_existing
    FROM business_members
   WHERE business_id = t.business_id AND person_id = v_me AND role = 'Owner'
   LIMIT 1;

  IF v_existing IS NOT NULL THEN
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now()), updated_at = now()
     WHERE membership_id = v_existing;
  ELSE
    INSERT INTO business_members (person_id, business_id, role, membership_status,
                                  verification_status, onboarding_method,
                                  invited_by_person_id, joined_at)
    VALUES (v_me, t.business_id, 'Owner', 'Active', 'Not Required',
            'ID Lookup', t.from_person_id, now());
  END IF;

  -- AND an Agent membership, because an Owner works their own round.
  SELECT membership_id INTO v_agent_member
    FROM business_members
   WHERE business_id = t.business_id AND person_id = v_me AND role = 'Agent'
   LIMIT 1;

  IF v_agent_member IS NOT NULL THEN
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now()), updated_at = now()
     WHERE membership_id = v_agent_member;
  ELSE
    INSERT INTO business_members (person_id, business_id, role, membership_status,
                                  verification_status, onboarding_method,
                                  invited_by_person_id, joined_at)
    VALUES (v_me, t.business_id, 'Agent', 'Active', 'Not Required',
            'ID Lookup', t.from_person_id, now())
    RETURNING membership_id INTO v_agent_member;
  END IF;

  SELECT agent_id INTO v_agent_id FROM agents WHERE membership_id = v_agent_member;
  IF v_agent_id IS NULL THEN
    INSERT INTO agents (membership_id, person_id, joined_date, current_status)
    VALUES (v_agent_member, v_me, CURRENT_DATE, 'Active')
    RETURNING agent_id INTO v_agent_id;
  END IF;

  -- Without this row every permission reads false: a workspace that loads and
  -- refuses every action, which reads as broken rather than as unpermitted.
  IF NOT EXISTS (SELECT 1 FROM agent_permissions WHERE agent_id = v_agent_id) THEN
    INSERT INTO agent_permissions (agent_id) VALUES (v_agent_id)
    RETURNING permission_profile_id INTO v_perm_id;
    UPDATE business_members SET permission_profile_id = v_perm_id
     WHERE membership_id = v_agent_member;
  END IF;

  UPDATE business_transfers
     SET status = 'Accepted', responded_at = now()
   WHERE transfer_id = p_transfer_id;

  -- The outgoing owner is told the handover happened. They initiated it, but
  -- the moment it completes is the other person's to choose, and it ends their
  -- control of the business.
  INSERT INTO notifications (recipient_person_id, business_id, notification_type,
                             message, related_entity_type, related_entity_uuid)
  SELECT t.from_person_id, t.business_id, 'Owner Approval Confirmation',
         COALESCE(p.full_name, 'The new owner') || ' accepted the handover of '
           || COALESCE(b.business_name, 'your business') || '.',
         'business_transfer', p_transfer_id
    FROM persons p, businesses b
   WHERE p.person_id = v_me AND b.business_id = t.business_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (t.business_id, v_me, 'Other Admin Event', 'business_transfer_accepted', 0,
          p_transfer_id,
          json_build_object('from_person_id', t.from_person_id, 'to_person_id', v_me,
                            'owner_memberships_removed', v_removed,
                            'agent_membership', v_agent_member,
                            'other_roles', 'left untouched'),
          CURRENT_DATE);

  RETURN json_build_object('status', 'Accepted', 'business_id', t.business_id,
                           'memberships_removed', v_removed,
                           'agent_membership_id', v_agent_member);
END;
$function$;

-- A transfer swaps the Owner role. It touches nothing else.
--
-- BEFORE: accepting removed EVERY membership the outgoing owner held in the
-- business — no role filter — while assert_business_transferable guarded only
-- their agent float and pending settlements, not their money.
--
-- On the live book that bites at once: the current owner holds 3 investments
-- worth 15,26,000 of principal in his own business. Transferring it marked his
-- INVESTOR membership Removed while the business still owed him every rupee.
-- The investments rows survive, but the person they are owed to stops being a
-- member of the business that owes them — and disappears from the investor
-- lists that would have shown the liability. A borrower who was also the owner
-- lost their Customer row the same way, hiding a debt owed TO the business.
--
-- The rule now, per the Owner's own spec: the old owner prepares the business
-- before offering it, the transfer alters no business data, and the ONLY thing
-- that changes hands is the Owner role. Whatever else the outgoing person is
-- to this business — investor, customer, agent — is a separate relationship a
-- sale does not extinguish, and the new owner can end any of them afterwards
-- exactly as they would for any other member.
--
-- The pre-conditions in assert_business_transferable stay as they are. They
-- are hygiene the outgoing owner clears BEFORE offering, not data this
-- function rewrites.
--
-- Both sides are also told: the offer reaches the person it is made to, and
-- the outgoing owner learns the moment the handover completes. Previously
-- each wrote an audit row and nothing else, so a business could be handed to
-- someone who never found out unless they opened Settings.

CREATE OR REPLACE FUNCTION app.respond_business_transfer(p_transfer_id uuid, p_accept boolean, p_reason text DEFAULT NULL::text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_me BIGINT := app.current_person_id();
  t RECORD;
  v_existing UUID;
  v_removed INT;
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
                            'other_roles', 'left untouched'),
          CURRENT_DATE);

  RETURN json_build_object('status', 'Accepted', 'business_id', t.business_id,
                           'memberships_removed', v_removed);
END;
$$;

CREATE OR REPLACE FUNCTION app.request_business_transfer(p_business_id uuid, p_to_person_id bigint, p_note text DEFAULT NULL::text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_me BIGINT := app.current_person_id();
  v_id UUID;
  v_open UUID;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;
  IF p_to_person_id = v_me THEN
    RAISE EXCEPTION 'You cannot transfer a business to yourself' USING ERRCODE = '23514';
  END IF;

  PERFORM app.assert_business_transferable(p_business_id, v_me, p_to_person_id);

  SELECT transfer_id INTO v_open
    FROM business_transfers
   WHERE business_id = p_business_id AND status = 'Pending'
   LIMIT 1;
  IF v_open IS NOT NULL THEN
    RAISE EXCEPTION 'This business is already offered to someone. Cancel that offer first.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO business_transfers (business_id, from_person_id, to_person_id, note)
  VALUES (p_business_id, v_me, p_to_person_id, p_note)
  RETURNING transfer_id INTO v_id;

  INSERT INTO notifications (recipient_person_id, business_id, notification_type,
                             message, related_entity_type, related_entity_uuid)
  SELECT p_to_person_id, p_business_id, 'Pending Approval',
         COALESCE(p.full_name, 'An owner') || ' wants to hand you '
           || COALESCE(b.business_name, 'their business') || '.'
           || COALESCE(' ' || NULLIF(btrim(p_note), ''), ''),
         'business_transfer', v_id
    FROM persons p, businesses b
   WHERE p.person_id = v_me AND b.business_id = p_business_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (p_business_id, v_me, 'Other Admin Event', 'business_transfer_offered', 0,
          v_id, json_build_object('to_person_id', p_to_person_id), CURRENT_DATE);

  RETURN json_build_object('transfer_id', v_id, 'status', 'Pending');
END;
$$;

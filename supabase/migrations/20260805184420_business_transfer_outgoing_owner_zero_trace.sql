-- Correction to 20260805183317: the outgoing owner keeps NO trace of a
-- transferred business.
--
-- The previous version removed only their Owner role and deliberately left
-- their Agent membership Active so they could keep collecting. That was the
-- wrong call: an Active Agent membership still resolves through
-- app.is_active_agent(), so the former owner would go on seeing that
-- business's customers, routes and collections after handing it over. "Zero
-- trace in the old owner's account", as the roadmap always said, means every
-- role goes.
--
-- ALL roles, not just Owner and Agent. If the outgoing owner also held a
-- Customer or Investor membership in their own business, leaving it behind
-- would put the transferred business back in their workspace switcher -- the
-- exact trace this is meant to remove.
--
-- STILL NOT DELETED, for the same reason as before: membership_id is what
-- collections.collected_by_membership_id, expenses.recorded_by_membership_id
-- and agent_bf_assignments key to, so the rows have to survive for the new
-- owner's books to stay whole. 'Removed' is what makes them invisible to the
-- person while keeping the history intact.
--
-- WORTH KNOWING, not guarded against here: if the outgoing owner had borrowed
-- from their own business, removing their Customer membership hides a loan
-- they still owe from their own view. The loan itself is untouched and stays
-- on the new owner's book, so no money is lost -- but the borrower stops
-- seeing it. Raise it as a separate rule if that case is real.
CREATE OR REPLACE FUNCTION app.respond_business_transfer(
  p_transfer_id uuid,
  p_accept boolean,
  p_reason text DEFAULT NULL
)
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

  -- Every role the outgoing owner held in this business, not just Owner.
  UPDATE business_members
     SET membership_status = 'Removed', removed_at = now(), updated_at = now()
   WHERE business_id = t.business_id
     AND person_id = t.from_person_id
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

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (t.business_id, v_me, 'Other Admin Event', 'business_transfer_accepted', 0,
          p_transfer_id,
          json_build_object('from_person_id', t.from_person_id, 'to_person_id', v_me,
                            'memberships_removed', v_removed),
          CURRENT_DATE);

  RETURN json_build_object('status', 'Accepted', 'business_id', t.business_id,
                           'memberships_removed', v_removed);
END;
$function$;

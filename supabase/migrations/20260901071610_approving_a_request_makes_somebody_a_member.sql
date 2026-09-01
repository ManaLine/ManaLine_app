-- Approving a membership request did nothing except mark it approved.
--
-- The client ran `update membership_requests set status = 'Approved'` and
-- stopped. There is no trigger on that table and no RPC behind it, so no
-- business_members row was created and no agents/customers/investors row
-- either. The Owner pressed Approve, the request left the queue, and the
-- person was still not a member of anything. Nothing on either screen said
-- so.
--
-- It had never actually run on this book -- every request on it is still
-- Pending -- which is why it went unnoticed while the request side was
-- broken for Agents by the enum. Fixing that would have delivered people to
-- this.
--
-- Rejecting sets the 24-hour cooldown that app.request_join_business already
-- reads. It was reading a column nothing ever wrote, so a rejected person
-- could reapply immediately and the cooldown was decorative.
--
-- NOTE: this version writes onboarding_method 'Self Request', which is not a
-- member of onboarding_method_enum, so it applied cleanly and threw on its
-- first call. Repaired in the next migration; kept as applied because the
-- ledger records it.
CREATE OR REPLACE FUNCTION app.decide_membership_request(
  p_request_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_person_id BIGINT;
  v_business_id UUID;
  v_role business_member_role_enum;
  v_status membership_request_status_enum;
  v_membership_id UUID;
BEGIN
  SELECT mr.person_id, mr.business_id, mr.requested_role::text::business_member_role_enum,
         mr.status
    INTO v_person_id, v_business_id, v_role, v_status
    FROM membership_requests mr
   WHERE mr.request_id = p_request_id
   FOR UPDATE;

  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No such request' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may decide a membership request'
      USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'Pending' THEN
    RAISE EXCEPTION 'This request has already been decided' USING ERRCODE = '23514';
  END IF;

  IF NOT p_approve THEN
    UPDATE membership_requests
       SET status = 'Rejected',
           rejection_reason = p_rejection_reason,
           reviewed_by_person_id = app.current_person_id(),
           reviewed_at = now(),
           -- The window request_join_business already checks for.
           cooldown_until = (now() AT TIME ZONE 'Asia/Kolkata') + INTERVAL '24 hours'
     WHERE request_id = p_request_id;

    INSERT INTO notifications (recipient_person_id, business_id,
                               notification_type, message,
                               related_entity_type, related_entity_uuid)
    VALUES (v_person_id, v_business_id, 'Owner Approval Confirmation',
            'Your request to join was not accepted. You can apply again after 24 hours.',
            'membership_request', p_request_id);

    RETURN json_build_object('status', 'rejected');
  END IF;

  -- Reactivate rather than duplicate: somebody who left and came back is the
  -- same membership, and business_members carries the history.
  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE person_id = v_person_id AND business_id = v_business_id AND role = v_role;

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      v_person_id, v_business_id, v_role, 'Active', 'Not Required',
      'Self Request', app.current_person_id(), now()
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now())
     WHERE membership_id = v_membership_id;
  END IF;

  -- The role-specific row. Without it the membership exists and every screen
  -- that needs an agent_id / customer_id / investor_id finds nothing.
  IF v_role = 'Agent' AND NOT EXISTS (
       SELECT 1 FROM agents WHERE membership_id = v_membership_id) THEN
    INSERT INTO agents (membership_id, person_id, joined_date, current_status)
    VALUES (v_membership_id, v_person_id, CURRENT_DATE, 'Active');
  ELSIF v_role = 'Customer' AND NOT EXISTS (
       SELECT 1 FROM customers WHERE membership_id = v_membership_id) THEN
    INSERT INTO customers (membership_id, person_id, occupation,
                           customer_status, customer_since)
    VALUES (v_membership_id, v_person_id, 'Other', 'Active', CURRENT_DATE);
  ELSIF v_role = 'Investor' AND NOT EXISTS (
       SELECT 1 FROM investors WHERE membership_id = v_membership_id) THEN
    INSERT INTO investors (membership_id, person_id)
    VALUES (v_membership_id, v_person_id);
  END IF;

  UPDATE membership_requests
     SET status = 'Approved',
         reviewed_by_person_id = app.current_person_id(),
         reviewed_at = now()
   WHERE request_id = p_request_id;

  INSERT INTO notifications (recipient_person_id, business_id,
                             notification_type, message,
                             related_entity_type, related_entity_uuid)
  VALUES (v_person_id, v_business_id, 'Owner Approval Confirmation',
          'Your request to join was approved. Open the app to start.',
          'membership_request', p_request_id);

  RETURN json_build_object(
    'status', 'approved',
    'membership_id', v_membership_id,
    'role', v_role::text);
END;
$function$;

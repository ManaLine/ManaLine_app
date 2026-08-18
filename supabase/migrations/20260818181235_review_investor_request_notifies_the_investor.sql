-- Approving an investor was three separate client writes - update the
-- request, insert business_members, insert investors - with no transaction
-- around them. A failure after the first left a request marked Approved with
-- no membership behind it, and nothing told the investor either way.
--
-- The missing note was not an oversight in the screen: `notifications` has
-- SELECT, UPDATE and DELETE policies and NO INSERT policy, so no client can
-- write one at all. It has to come from a definer function, which is this.
CREATE OR REPLACE FUNCTION app.review_investor_request(
  p_request_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_req RECORD;
  v_business_name text;
  v_membership_id uuid;
  v_investor_id uuid;
  v_reviewer bigint := app.current_person_id();
BEGIN
  SELECT * INTO v_req
    FROM membership_requests
   WHERE request_id = p_request_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That request no longer exists.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_req.business_id) THEN
    RAISE EXCEPTION 'Not authorized to review requests for this business' USING ERRCODE = '42501';
  END IF;
  IF v_req.requested_role <> 'Investor' THEN
    RAISE EXCEPTION 'This request is not an investor request.' USING ERRCODE = '23514';
  END IF;
  -- Answering an already-answered request would create a second membership.
  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'This request was already %.', lower(v_req.status::text) USING ERRCODE = '23505';
  END IF;

  SELECT business_name INTO v_business_name FROM businesses WHERE business_id = v_req.business_id;

  IF p_approve THEN
    UPDATE membership_requests
       SET status = 'Approved', reviewed_by_person_id = v_reviewer, reviewed_at = now()
     WHERE request_id = p_request_id;

    -- Reuse an existing membership rather than adding a second one: a person
    -- who was removed and re-approved must not end up with two rows.
    SELECT membership_id INTO v_membership_id
      FROM business_members
     WHERE business_id = v_req.business_id AND person_id = v_req.person_id AND role = 'Investor';

    IF v_membership_id IS NULL THEN
      INSERT INTO business_members (
        person_id, business_id, role, membership_status, verification_status,
        onboarding_method, joined_at
      ) VALUES (
        v_req.person_id, v_req.business_id, 'Investor', 'Active', 'Not Required',
        'Direct Registration', now()
      ) RETURNING membership_id INTO v_membership_id;
    ELSE
      UPDATE business_members
         SET membership_status = 'Active', removed_at = NULL, joined_at = COALESCE(joined_at, now())
       WHERE membership_id = v_membership_id;
    END IF;

    SELECT investor_id INTO v_investor_id FROM investors WHERE membership_id = v_membership_id;
    IF v_investor_id IS NULL THEN
      INSERT INTO investors (membership_id, person_id)
      VALUES (v_membership_id, v_req.person_id)
      RETURNING investor_id INTO v_investor_id;
    END IF;

    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    ) VALUES (
      v_req.person_id, v_req.business_id, 'Owner Approval Confirmation',
      format('%s accepted your request to invest. You can now see your investments in this business.',
             COALESCE(v_business_name, 'The business')),
      'membership_request', p_request_id
    );
  ELSE
    UPDATE membership_requests
       SET status = 'Rejected', reviewed_by_person_id = v_reviewer, reviewed_at = now(),
           rejection_reason = NULLIF(btrim(COALESCE(p_rejection_reason, '')), ''),
           cooldown_until = now() + INTERVAL '24 hours'
     WHERE request_id = p_request_id;

    -- Told either way. Silence after a request reads as the app losing it.
    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    ) VALUES (
      v_req.person_id, v_req.business_id, 'Owner Approval Confirmation',
      format('%s could not accept your request to invest%s You can ask again after 24 hours.',
             COALESCE(v_business_name, 'The business'),
             CASE WHEN NULLIF(btrim(COALESCE(p_rejection_reason, '')), '') IS NULL
                  THEN '.' ELSE ': ' || btrim(p_rejection_reason) || '.' END),
      'membership_request', p_request_id
    );
  END IF;

  RETURN json_build_object(
    'request_id', p_request_id,
    'approved', p_approve,
    'membership_id', v_membership_id,
    'investor_id', v_investor_id,
    'notified_person_id', v_req.person_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.review_investor_request(uuid, boolean, text) TO authenticated, service_role;

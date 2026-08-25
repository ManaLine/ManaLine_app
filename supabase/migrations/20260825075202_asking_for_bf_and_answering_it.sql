-- Asking for BF, and answering it.
--
-- Two halves of one conversation. request_agent_bf is called from the Agent's
-- side of the "Insufficient agent BF" refusal; decide_agent_bf_request is what
-- the Owner's approve/reject buttons call.
--
-- NOTE: the notification block below names enum values that do not exist, and
-- the next migration corrects it. Kept as it was applied, because a plpgsql
-- body is not type-checked at CREATE -- this created cleanly and failed on its
-- first call, which is exactly the trap CLAUDE.md warns about, and rewriting
-- history here would hide that it happened.
CREATE OR REPLACE FUNCTION app.request_agent_bf(
  p_membership_id uuid,
  p_amount numeric,
  p_reason text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE
  v_business_id uuid;
  v_agent_name  text;
  v_request_id  uuid;
  v_owner       bigint;
  v_existing    uuid;
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Ask for an amount greater than zero.' USING ERRCODE = '23514';
  END IF;

  SELECT bm.business_id, p.full_name INTO v_business_id, v_agent_name
    FROM business_members bm
    JOIN persons p ON p.person_id = bm.person_id
   WHERE bm.membership_id = p_membership_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Membership not found' USING ERRCODE = 'P0002';
  END IF;

  -- A second ask while one is open is the same conversation. Raise the amount
  -- on the open one rather than refusing the Agent, who is standing in front
  -- of a customer and does not care which row it lands on.
  SELECT request_id INTO v_existing
    FROM agent_bf_requests
   WHERE membership_id = p_membership_id AND status = 'Pending';

  IF v_existing IS NOT NULL THEN
    UPDATE agent_bf_requests
       SET requested_amount = ROUND(p_amount),
           reason = COALESCE(NULLIF(btrim(p_reason), ''), reason)
     WHERE request_id = v_existing;
    v_request_id := v_existing;
  ELSE
    INSERT INTO agent_bf_requests (business_id, membership_id, requested_amount, reason)
    VALUES (v_business_id, p_membership_id, ROUND(p_amount), NULLIF(btrim(p_reason), ''))
    RETURNING request_id INTO v_request_id;
  END IF;

  -- Every Owner, not just businesses.owner_person_id: a co-owner holding the
  -- role through business_members must be able to answer this too, or the
  -- Agent stays blocked whenever the registered owner is unavailable.
  FOR v_owner IN
    SELECT DISTINCT person_id FROM business_members
     WHERE business_id = v_business_id AND role = 'Owner'
       AND membership_status = 'Active' AND removed_at IS NULL
    UNION
    SELECT owner_person_id FROM businesses WHERE business_id = v_business_id
  LOOP
    IF v_owner IS NULL THEN CONTINUE; END IF;
    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    ) VALUES (
      v_owner, v_business_id, 'Pending Approval',
      COALESCE(v_agent_name, 'An agent') || ' has asked for BF of '
        || ROUND(p_amount)::text
        || COALESCE('. ' || NULLIF(btrim(p_reason), ''), '')
        || ' They cannot issue loans until it is granted.',
      'agent_bf_request', v_request_id
    );
  END LOOP;

  RETURN v_request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app.decide_agent_bf_request(
  p_request_id uuid,
  p_approve boolean,
  p_amount numeric DEFAULT NULL,
  p_note text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE
  v_req    RECORD;
  v_person bigint := app.current_person_id();
  v_agent  bigint;
  v_amount numeric(14,0);
BEGIN
  SELECT * INTO v_req FROM agent_bf_requests WHERE request_id = p_request_id;
  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Request not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_req.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may answer a BF request' USING ERRCODE = '42501';
  END IF;
  IF v_req.status <> 'Pending' THEN
    RAISE EXCEPTION 'This request has already been answered.' USING ERRCODE = '23514';
  END IF;

  SELECT person_id INTO v_agent FROM business_members
   WHERE membership_id = v_req.membership_id;

  IF p_approve THEN
    v_amount := ROUND(COALESCE(p_amount, v_req.requested_amount));
    IF v_amount <= 0 THEN
      RAISE EXCEPTION 'Grant an amount greater than zero, or reject the request.'
        USING ERRCODE = '23514';
    END IF;
    PERFORM app.grant_agent_bf(v_req.membership_id, v_amount);

    UPDATE agent_bf_requests
       SET status = 'Approved', decided_amount = v_amount,
           decided_by_person_id = v_person, decided_at = now(),
           decision_note = NULLIF(btrim(p_note), '')
     WHERE request_id = p_request_id;
  ELSE
    UPDATE agent_bf_requests
       SET status = 'Rejected', decided_by_person_id = v_person,
           decided_at = now(), decision_note = NULLIF(btrim(p_note), '')
     WHERE request_id = p_request_id;
  END IF;

  IF v_agent IS NOT NULL THEN
    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    ) VALUES (
      v_agent, v_req.business_id,
      CASE WHEN p_approve THEN 'Approval' ELSE 'Rejection' END,
      CASE WHEN p_approve
           THEN 'Your BF request was approved: ' || v_amount::text
                || CASE WHEN v_amount <> v_req.requested_amount
                        THEN ' (you asked for ' || v_req.requested_amount::text || ')'
                        ELSE '' END
           ELSE 'Your BF top-up request was rejected.'
      END || COALESCE(' ' || NULLIF(btrim(p_note), ''), ''),
      'agent_bf_request', p_request_id
    );
  END IF;

  RETURN json_build_object(
    'request_id', p_request_id,
    'status', CASE WHEN p_approve THEN 'Approved' ELSE 'Rejected' END,
    'granted', v_amount,
    'requested', v_req.requested_amount);
END;
$function$;

GRANT EXECUTE ON FUNCTION app.request_agent_bf(uuid, numeric, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION app.decide_agent_bf_request(uuid, boolean, numeric, text) TO authenticated, service_role;

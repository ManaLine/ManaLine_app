-- notification_type_enum has no 'Approval' or 'Rejection'.
--
-- The previous migration created cleanly and failed on its first call, as a
-- plpgsql body always will -- it is not type-checked until it runs. The whole
-- decide path was dead until it was actually invoked.
--
-- 'Owner Approval Confirmation' is the enum's word for exactly this. A refusal
-- has no value of its own, so it is 'Other': adding one would be a migration
-- on a type half the schema references, for a message whose wording already
-- says what happened.
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
    -- The Owner may grant a different figure. They know what is in the till,
    -- and approving the asked-for amount by default is a convenience, not a
    -- rule.
    v_amount := ROUND(COALESCE(p_amount, v_req.requested_amount));
    IF v_amount <= 0 THEN
      RAISE EXCEPTION 'Grant an amount greater than zero, or reject the request.'
        USING ERRCODE = '23514';
    END IF;

    -- grant_agent_bf keeps its own pre-flight guard: it refuses to hand out
    -- more than the Owner's own BF holds. That check stays where it is.
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

  -- The Agent hears back either way. Being refused and being ignored look the
  -- same from the road, and only one of them is something an Owner meant.
  IF v_agent IS NOT NULL THEN
    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    ) VALUES (
      v_agent, v_req.business_id,
      (CASE WHEN p_approve THEN 'Owner Approval Confirmation' ELSE 'Other' END)
        ::notification_type_enum,
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

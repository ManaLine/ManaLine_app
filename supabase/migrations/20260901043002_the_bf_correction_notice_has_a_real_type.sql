-- 'General' is not a notification_type_enum value. The previous migration
-- applied cleanly and threw on its first call -- plpgsql bodies are not
-- type-checked at CREATE time, and an enum literal inside an INSERT is
-- exactly the kind of thing that only fails when the row is actually written.
--
-- 'Owner Approval Confirmation' is the closest real member: this notice tells
-- the agent the Owner has acted on what they raised.
--
-- Identical to the previous migration in every other respect.
CREATE OR REPLACE FUNCTION app.grant_agent_bf(p_agent_membership_id uuid, p_amount numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_owner_bf DECIMAL(14,0);
  v_owner_membership UUID;
  v_was_disputed BOOLEAN;
BEGIN
  v_business_id := app.business_id_for_membership(p_agent_membership_id);
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Membership not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may grant BF' USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Top-up amount must be positive' USING ERRCODE = '23514';
  END IF;

  SELECT owner_bf_balance INTO v_owner_bf
  FROM businesses WHERE business_id = v_business_id FOR UPDATE;
  IF v_owner_bf < p_amount THEN
    RAISE EXCEPTION 'Owner BF is only %, cannot top up %', v_owner_bf, p_amount USING ERRCODE = '23514';
  END IF;

  SELECT membership_id INTO v_owner_membership
  FROM business_members
  WHERE business_id = v_business_id AND person_id = app.current_person_id()
    AND role = 'Owner' AND membership_status = 'Active'
  LIMIT 1;

  INSERT INTO agent_bf_grants (business_id, membership_id, amount, business_date, granted_by_membership_id)
  VALUES (v_business_id, p_agent_membership_id, p_amount, CURRENT_DATE, v_owner_membership);

  PERFORM app.recompute_business_bf(v_business_id);

  UPDATE agent_bf_assignments
     SET update_requested = FALSE,
         confirmed_by_agent = FALSE,
         updated_at = now()
   WHERE assignment_id = (
     SELECT assignment_id FROM agent_bf_assignments
      WHERE membership_id = p_agent_membership_id
      ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
      LIMIT 1)
     AND update_requested
  RETURNING TRUE INTO v_was_disputed;

  IF v_was_disputed THEN
    INSERT INTO notifications (
      recipient_person_id, business_id, notification_type, message,
      related_entity_type, related_entity_uuid
    )
    SELECT bm.person_id, v_business_id, 'Owner Approval Confirmation',
           'Your opening BF has been corrected. Open the app to check the new '
             || 'figure and confirm it before you start collecting.',
           'agent_bf_assignment', a.assignment_id
      FROM business_members bm
      JOIN agent_bf_assignments a ON a.membership_id = bm.membership_id
     WHERE bm.membership_id = p_agent_membership_id
     ORDER BY COALESCE(a.business_date::TIMESTAMP, a.created_at) DESC
     LIMIT 1;
  END IF;

  RETURN (SELECT agent_bf_current FROM agent_bf_assignments
           WHERE membership_id = p_agent_membership_id
           ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC LIMIT 1);
END;
$function$;

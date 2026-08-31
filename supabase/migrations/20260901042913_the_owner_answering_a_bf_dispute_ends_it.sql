-- An agent who disputed their opening BF stayed blocked after the Owner
-- fixed it. There was a stuck row on this book: assignment f91cfc80,
-- agent_bf_current 10,000 -- the Owner granted the money -- with
-- update_requested still TRUE and the agent unable to collect.
--
-- The flag is not unclearable. confirm_bf_assignment clears it. But that is
-- AGENT-side (membership_belongs_to_current_person), and a disputing agent is
-- sent to _BfUpdateRequestedBlock, which was a dead-end panel with no action
-- on it at all. So the only route out of the state was through a button the
-- state itself hides, and nothing the Owner could do touched it.
--
-- Granting BF is the Owner answering the dispute -- it is the correction the
-- agent asked for -- so it ends the dispute here.
--
-- WHAT IT DELIBERATELY DOES NOT DO: mark the figure agreed. The agent said
-- the number was wrong; the Owner changing it does not make the agent right
-- or wrong, it makes the number different. So confirmed_by_agent goes back to
-- FALSE and the agent lands on the ordinary BF confirm gate showing the
-- corrected figure, which they confirm. Owner corrects, agent agrees, work
-- resumes -- rather than the app deciding on the agent's behalf that they are
-- satisfied.
--
-- MONEY PATH: the grant itself is untouched. The rows inserted into
-- agent_bf_grants, the owner-BF pre-flight check and the recompute all behave
-- exactly as before; the only addition is the flag update on the agent's
-- latest assignment row, plus a notice telling them to come and look.
--
-- NOTE: this version names notification_type 'General', which is not a member
-- of notification_type_enum, so it applied cleanly and threw on its first
-- call. Repaired in the next migration; kept as applied because the ledger
-- records it.
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
    SELECT bm.person_id, v_business_id, 'General',
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

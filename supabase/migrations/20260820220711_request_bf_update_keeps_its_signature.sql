-- A disputed opening BF now reaches the Owner.
--
-- SEEN LIVE: the Agent's screen says "Your Opening BF dispute has been sent to
-- the Owner. You will be re-prompted with the corrected figure once they
-- resolve it." Nothing was sent anywhere. app.request_bf_update set
-- agent_bf_assignments.update_requested = TRUE and stopped, and no Owner
-- screen read that column. The Agent is locked out of their round waiting for
-- a message the Owner would never receive.
--
-- 'Pending Approval' rather than a new enum label: the Owner's notification
-- list already renders it, and a new label would need every consumer updated
-- before it displayed as anything.
--
-- The previous migration wrote this as (uuid) while the real function is
-- (uuid, text DEFAULT NULL), so it created a SECOND overload rather than
-- replacing — ambiguous, and PostgREST refuses it. Drop that and rebuild on
-- the original argument list.
DROP FUNCTION IF EXISTS app.request_bf_update(uuid);

CREATE OR REPLACE FUNCTION app.request_bf_update(
  p_membership_id uuid,
  p_note text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_assignment_id UUID;
  v_business_id   UUID;
  v_opening       NUMERIC(14,0);
  v_agent_name    TEXT;
  v_owner         BIGINT;
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  SELECT assignment_id, opening_bf INTO v_assignment_id, v_opening
    FROM agent_bf_assignments
   WHERE membership_id = p_membership_id
   ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
   LIMIT 1;

  IF v_assignment_id IS NULL THEN
    RAISE EXCEPTION 'No agent_bf_assignments row exists for this agent — access not yet granted'
      USING ERRCODE = 'P0002';
  END IF;

  UPDATE agent_bf_assignments
     SET update_requested = TRUE, updated_at = now()
   WHERE assignment_id = v_assignment_id;

  SELECT bm.business_id, p.full_name
    INTO v_business_id, v_agent_name
    FROM business_members bm
    JOIN persons p ON p.person_id = bm.person_id
   WHERE bm.membership_id = p_membership_id;

  -- Every Owner of the business, not just businesses.owner_person_id: a
  -- co-owner holding the role through business_members must be able to
  -- resolve this too, or the Agent stays blocked whenever the registered
  -- owner is unavailable.
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
      COALESCE(v_agent_name, 'An agent') || ' disputes their opening BF of '
        || COALESCE(v_opening, 0)::text
        || COALESCE('. Note: ' || NULLIF(btrim(p_note), ''), '')
        || '. They cannot start collecting until it is corrected.',
      'agent_bf_assignment', v_assignment_id
    );
  END LOOP;
END;
$$;

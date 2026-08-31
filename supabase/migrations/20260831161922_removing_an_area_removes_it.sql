-- "Remove" left the area sitting in the list, Inactive, still offering to
-- take villages and agents. Five of nine areas on this book were in that
-- state, and three of those five had no history whatsoever -- no account
-- period, no agent assignment, nothing. They were litter, and there was no
-- way to sweep them up.
--
-- deactivate_operating_area did the right things as far as it went: freed the
-- villages so they could join another round, released the agents. What it
-- never did was leave.
--
-- WHAT REMOVE MEANS NOW, in three cases:
--
--   * live loans in the area -> BLOCKED unless the Owner insists. Somebody is
--     still collecting there; making the area vanish underneath them is how a
--     round goes missing. p_force is the "I know, do it anyway" the warning
--     dialog sends back, and even then it only deactivates.
--   * no live loans, no history -> DELETED. Genuinely gone: the villages and
--     assignments go with it and the row is dropped.
--   * no live loans, but history -> DEACTIVATED. account_periods reference
--     this area and each one is the record of an agent's round: what was
--     collected, what was settled, what the Owner approved. Deleting the area
--     would either destroy those or orphan them. A business's past does not
--     get tidied away because a line is no longer worked.
--
-- The third case is the reason this is not simply a DELETE. All three FKs
-- into operating_areas are NO ACTION, which is correct and stays that way.
CREATE OR REPLACE FUNCTION app.remove_operating_area(
  p_operating_area_id UUID,
  p_force BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_business_id UUID;
  v_name TEXT;
  v_live_loans INT;
  v_periods INT;
BEGIN
  SELECT business_id, name INTO v_business_id, v_name
  FROM operating_areas WHERE operating_area_id = p_operating_area_id;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Operating area not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may remove an operating area'
      USING ERRCODE = '42501';
  END IF;

  -- Customers living in this area's villages, with money still out.
  SELECT count(*) INTO v_live_loans
  FROM loans l
  JOIN customers c        ON c.customer_id = l.customer_id
  JOIN persons p          ON p.person_id = c.person_id
  JOIN person_addresses pa ON pa.person_id = p.person_id AND pa.is_current
  JOIN operating_area_locations oal
       ON oal.location_id = pa.village_id
      AND oal.operating_area_id = p_operating_area_id
      AND oal.removed_at IS NULL
  WHERE l.deleted_at IS NULL
    AND l.loan_status IN ('Active', 'Grace Period', 'Penalty');

  IF v_live_loans > 0 AND NOT p_force THEN
    RETURN json_build_object(
      'status', 'blocked',
      'live_loans', v_live_loans,
      'name', v_name);
  END IF;

  SELECT count(*) INTO v_periods
  FROM account_periods WHERE operating_area_id = p_operating_area_id;

  -- Free the villages so they can join another round, and release the agents
  -- so a removed area stops appearing in their assignment list. Both happen
  -- whichever way this ends.
  UPDATE operating_area_locations SET removed_at = now()
  WHERE operating_area_id = p_operating_area_id AND removed_at IS NULL;

  UPDATE agent_area_assignments SET removed_at = now()
  WHERE operating_area_id = p_operating_area_id AND removed_at IS NULL;

  IF v_periods = 0 AND v_live_loans = 0 THEN
    DELETE FROM operating_area_locations
     WHERE operating_area_id = p_operating_area_id;
    DELETE FROM agent_area_assignments
     WHERE operating_area_id = p_operating_area_id;
    DELETE FROM operating_areas
     WHERE operating_area_id = p_operating_area_id;

    INSERT INTO audit_log (
      business_id, actor_person_id, action_type, entity_type, entity_id,
      entity_uuid, new_value, business_date
    ) VALUES (
      v_business_id, app.current_person_id(), 'Other Admin Event',
      'operating_area_deleted', 0, p_operating_area_id,
      json_build_object('name', v_name), CURRENT_DATE
    );

    RETURN json_build_object('status', 'deleted', 'name', v_name);
  END IF;

  UPDATE operating_areas SET status = 'Inactive'
  WHERE operating_area_id = p_operating_area_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    'operating_area_deactivated', 0, p_operating_area_id,
    json_build_object('name', v_name, 'account_periods', v_periods,
                      'live_loans', v_live_loans),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'deactivated',
    'name', v_name,
    'account_periods', v_periods,
    'live_loans', v_live_loans);
END;
$$;

-- An Agent with no float starts at zero. They are not locked out.
--
-- BEFORE: no agent_bf_assignments row meant AgentSessionStage
-- .bfBlockedNoAssignment — the Agent opened the app to a dead end until the
-- Owner remembered to grant BF. They could not see their business, their
-- round, or their customers. But an Agent holding no cash is a perfectly
-- ordinary state: they collect all morning and hand it over, and on many days
-- they are handed nothing to start with.
--
-- Zero is also the honest figure. Inventing a float would be worse, and
-- blocking pretends the number is unknown when it is known to be nothing.
--
-- Nothing about spending changes: app.create_loan_with_bf_check still refuses
-- INSUFFICIENT_FLOAT, so an Agent at zero can collect but cannot lend, which
-- is exactly right. The Owner grants BF when there is cash to hand over, and
-- can still disable the Agent outright through membership_status.
--
-- Agent PERMISSIONS needed no change and were left alone: every can_* column
-- already defaults to true (bar can_delete_records), and both RPCs that create
-- an agent — register_new_agent and create_business_with_owner — already
-- insert the permissions row. Checked before assuming.
CREATE OR REPLACE FUNCTION app.ensure_agent_bf_assignment(p_membership_id uuid)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_business_id UUID;
  v_assignment  agent_bf_assignments%ROWTYPE;
BEGIN
  SELECT business_id INTO v_business_id
    FROM business_members
   WHERE membership_id = p_membership_id AND role = 'Agent';

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No agent membership found' USING ERRCODE = 'P0002';
  END IF;

  -- The Agent themselves, or an Owner setting them up.
  IF NOT app.membership_belongs_to_current_person(p_membership_id)
     AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_assignment
    FROM agent_bf_assignments
   WHERE membership_id = p_membership_id
   ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
   LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO agent_bf_assignments (
      membership_id, business_date, opening_bf, agent_bf_current,
      confirmed_by_agent
    ) VALUES (
      p_membership_id, CURRENT_DATE, 0, 0, false
    ) RETURNING * INTO v_assignment;
  END IF;

  RETURN json_build_object(
    'assignment_id',     v_assignment.assignment_id,
    'opening_bf',        v_assignment.opening_bf,
    'confirmed_by_agent',v_assignment.confirmed_by_agent,
    'update_requested',  v_assignment.update_requested
  );
END;
$$;

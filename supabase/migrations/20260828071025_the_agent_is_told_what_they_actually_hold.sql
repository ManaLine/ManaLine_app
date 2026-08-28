-- The Agent's own screens showed `opening_bf` and called it their BF.
--
-- opening_bf is what they STARTED the session with and is never updated
-- again; agent_bf_current is what they hold now, and it is the column
-- app.create_loan_with_bf_check locks and spends against. So an Agent
-- holding Rs 2,69,190 was shown Rs 0, refused their own loan screen, and
-- the same agent read Rs 2,69,190 in the Owner's workforce view. Two
-- columns, two answers, one pocket.
--
-- This RPC is the Agent side's only server-issued BF figure, and it did
-- not return agent_bf_current at all, so the client could not show the
-- right number even once it wanted to.
--
-- Same signature (p_membership_id uuid) -- CREATE OR REPLACE is safe here
-- and cannot create a second overload.
--
-- The ORDER BY is also unified with create_loan_with_bf_check's
-- (business_date DESC NULLS LAST). Three call sites ordered the same table
-- three different ways -- created_at here, business_date there,
-- COALESCE(business_date, created_at) in this function -- which with more
-- than one assignment row would have let the screen read one row while the
-- loan check locked another.
CREATE OR REPLACE FUNCTION app.ensure_agent_bf_assignment(p_membership_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
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
   ORDER BY business_date DESC NULLS LAST, created_at DESC
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
    'assignment_id',      v_assignment.assignment_id,
    'opening_bf',         v_assignment.opening_bf,
    'agent_bf_current',   v_assignment.agent_bf_current,
    'confirmed_by_agent', v_assignment.confirmed_by_agent,
    'update_requested',   v_assignment.update_requested
  );
END;
$$;

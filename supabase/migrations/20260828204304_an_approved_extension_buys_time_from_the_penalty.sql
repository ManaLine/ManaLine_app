-- An approved extension did nothing to the loan.
--
-- extension_requests carried a status and no duration at all, so "approved"
-- meant a row said Approved and the customer's position was unchanged: the
-- penalty clock kept running, the round kept offering the door, and the Agent
-- who had just promised somebody a week had nothing to show for it.
--
-- An extension means "do not penalise them for this period". That is exactly
-- what grace_period_days already does -- app.loan_penalty_eligible_from adds
-- it to the last scheduled instalment -- so approving one grants grace rather
-- than inventing a second mechanism beside it.
--
-- Days is the storage unit even though the screen asks in days, weeks or
-- months, for the same reason grace does: two units for one quantity is how
-- a fortnight becomes fourteen months.
ALTER TABLE extension_requests
  ADD COLUMN extend_by_days INT CHECK (extend_by_days IS NULL OR extend_by_days > 0),
  ADD COLUMN extended_until DATE,
  ADD COLUMN decided_at TIMESTAMP;

COMMENT ON COLUMN extension_requests.extend_by_days IS
  'How much time was asked for, in days. Null on rows created before the '
  'question was asked.';
COMMENT ON COLUMN extension_requests.extended_until IS
  'Set on approval: business_date + extend_by_days. The round treats a door '
  'as answered until this date, and the grace granted on the loan matches it.';

-- Approving is two writes that must not come apart: the decision, and the
-- grace it buys. A row marked Approved whose loan never got the days is the
-- failure this function exists to prevent.
CREATE OR REPLACE FUNCTION app.decide_extension(
  p_extension_id UUID,
  p_approve BOOLEAN,
  p_extend_by_days INT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_loan_id UUID;
  v_business_id UUID;
  v_status TEXT;
  v_days INT;
  v_until DATE;
  v_grace_before INT;
BEGIN
  SELECT e.loan_id, e.status, COALESCE(p_extend_by_days, e.extend_by_days)
    INTO v_loan_id, v_status, v_days
    FROM extension_requests e
   WHERE e.extension_id = p_extension_id
   FOR UPDATE;

  IF v_loan_id IS NULL THEN
    RAISE EXCEPTION 'No such extension request' USING ERRCODE = 'P0002';
  END IF;

  SELECT l.business_id, l.grace_period_days INTO v_business_id, v_grace_before
    FROM loans l WHERE l.loan_id = v_loan_id AND l.deleted_at IS NULL;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'That loan no longer exists' USING ERRCODE = 'P0002';
  END IF;

  -- The same gate grace itself uses: the Owner, or an Agent the Owner has
  -- given the permission to.
  IF NOT (app.is_owner(v_business_id)
          OR (app.is_active_agent(v_business_id)
              AND app.agent_permission(v_business_id, 'can_grant_grace_period')))
  THEN
    RAISE EXCEPTION 'Not authorized to decide extensions on this loan'
      USING ERRCODE = '42501';
  END IF;

  IF v_status <> 'Pending' THEN
    RAISE EXCEPTION 'This extension has already been decided'
      USING ERRCODE = '23514';
  END IF;

  IF p_approve THEN
    IF v_days IS NULL OR v_days <= 0 THEN
      RAISE EXCEPTION 'An approved extension needs a duration'
        USING ERRCODE = '23514';
    END IF;
    -- A year of extension is not an extension, it is a rewritten loan. Same
    -- ceiling grant_grace_period enforces.
    IF v_days > 365 THEN
      RAISE EXCEPTION 'An extension cannot exceed 365 days' USING ERRCODE = '22023';
    END IF;

    v_until := CURRENT_DATE + v_days;

    UPDATE extension_requests
       SET status = 'Approved',
           extend_by_days = v_days,
           extended_until = v_until,
           decided_by_person_id = app.current_person_id(),
           decided_at = now()
     WHERE extension_id = p_extension_id;

    -- Added to whatever grace the loan already had, not replacing it: two
    -- extensions in a season are two extensions.
    UPDATE loans
       SET grace_period_days = LEAST(COALESCE(grace_period_days, 0) + v_days, 365),
           updated_at = now()
     WHERE loan_id = v_loan_id;
  ELSE
    UPDATE extension_requests
       SET status = 'Rejected',
           decided_by_person_id = app.current_person_id(),
           decided_at = now()
     WHERE extension_id = p_extension_id;
  END IF;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, old_value, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    'loan_extension', 0, v_loan_id,
    json_build_object('grace_period_days', v_grace_before),
    json_build_object('approved', p_approve, 'extend_by_days', v_days,
                      'extended_until', v_until),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    'loan_id', v_loan_id,
    'extend_by_days', v_days,
    'extended_until', v_until
  );
END;
$$;

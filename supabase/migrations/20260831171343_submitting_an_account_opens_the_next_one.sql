-- Submitting closed the account and opened nothing.
--
-- The period went to 'Submitted' and that was the end of it. Everything the
-- agent collected afterwards -- that evening, the next morning, all the way
-- until somebody manually started a session -- fell outside every period, so
-- app.account_period_window returned no row and the round fell back to
-- grouping by day. That is the daily-entries problem: one customer paying
-- Rs 100 a day got a receipt per day instead of one per account.
--
-- An account now runs from the moment the last one was handed over. Submit at
-- 18:30 on 1-1-26 and the next account begins at 18:30 on 1-1-26; the Rs 100
-- taken at 19:00 belongs to it.
--
-- ON A RETURNED SETTLEMENT: the new period stays. Money collected after the
-- handover belongs to the next account whether or not the Owner has approved
-- the previous one yet -- the agent has physically taken it since. A returned
-- settlement is corrected against its own period by id, which is how
-- ag_006 reaches it, not through account_period_window; the window always
-- answers with the newest period and that is deliberately the live one.
--
-- Patched off the live definition so the rest of the body -- the ownership
-- check, the already-submitted guard, the opening/collections/loans/expenses
-- reads, the held figure and the settlement row -- is untouched.
DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT;
  v_new TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'submit_agent_settlement';

  v_old := '  UPDATE account_periods
     SET status = ''Submitted''
   WHERE account_period_id = p_account_period_id;';

  v_new := '  UPDATE account_periods
     SET status = ''Submitted'', submitted_at = now()
   WHERE account_period_id = p_account_period_id;

  -- The next account starts now, not when somebody remembers to start it.
  -- Without this the agent collected into no period at all until a session
  -- was opened by hand, and the round fell back to grouping by day.
  INSERT INTO account_periods (
    business_id, operating_area_id, agent_membership_id,
    business_start_date, planned_business_end_date, status
  )
  SELECT ap.business_id, ap.operating_area_id, ap.agent_membership_id,
         now(), NULL, ''Running''
  FROM account_periods ap
  WHERE ap.account_period_id = p_account_period_id
    AND NOT EXISTS (
      SELECT 1 FROM account_periods live
       WHERE live.agent_membership_id = ap.agent_membership_id
         AND live.operating_area_id = ap.operating_area_id
         AND live.status = ''Running'');';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'submit_agent_settlement period update not found — not patched';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;

-- Dead since the period stopped having a planned end: v_dur and v_unit are
-- read and never used again.
CREATE OR REPLACE FUNCTION app.assign_agent_area(
  p_agent_id uuid,
  p_operating_area_id uuid,
  p_frequency area_assignment_frequency_enum DEFAULT 'Once'::area_assignment_frequency_enum,
  p_valid_from date DEFAULT CURRENT_DATE,
  p_valid_to date DEFAULT NULL::date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_membership_id UUID;
  v_assignment_id UUID;
BEGIN
  SELECT bm.business_id, bm.membership_id INTO v_business_id, v_membership_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE a.agent_id = p_agent_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may assign areas' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM operating_areas
    WHERE operating_area_id = p_operating_area_id AND business_id = v_business_id
  ) THEN
    RAISE EXCEPTION 'Area does not belong to this business' USING ERRCODE = '42501';
  END IF;

  IF p_valid_from IS NULL THEN p_valid_from := CURRENT_DATE; END IF;
  IF p_valid_to IS NOT NULL AND p_valid_to < p_valid_from THEN
    RAISE EXCEPTION 'valid_to cannot be before valid_from' USING ERRCODE = '23514';
  END IF;

  UPDATE agent_area_assignments
  SET valid_to = p_valid_from - 1
  WHERE operating_area_id = p_operating_area_id
    AND agent_id = p_agent_id
    AND removed_at IS NULL
    AND valid_to IS NULL;

  INSERT INTO agent_area_assignments (agent_id, operating_area_id, frequency, valid_from, valid_to)
  VALUES (p_agent_id, p_operating_area_id, p_frequency, p_valid_from, p_valid_to)
  RETURNING assignment_id INTO v_assignment_id;

  IF NOT EXISTS (
    SELECT 1 FROM account_periods
    WHERE operating_area_id = p_operating_area_id AND status = 'Running'
  ) THEN
    INSERT INTO account_periods (
      business_id, operating_area_id, agent_membership_id,
      business_start_date, planned_business_end_date, status
    ) VALUES (
      v_business_id, p_operating_area_id, v_membership_id, now(),
      NULL,
      'Running'
    );
  END IF;

  RETURN v_assignment_id;
END;
$function$;

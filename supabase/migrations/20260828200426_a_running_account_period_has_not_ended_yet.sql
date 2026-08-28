-- A period that is Running is OPEN, whatever its planned end says.
--
-- The window used COALESCE(actual_end_date, planned_business_end_date). On
-- this business the planned end is four days after the start, and an agent
-- who works Tuesday to Monday before submitting is inside the period the
-- whole time -- the plan simply guessed short. Under the old rule Saturday,
-- Sunday and Monday fell outside it, so a customer paying Rs 100 a day got
-- four receipts across one account instead of one.
--
-- The money was never wrong: every payment is its own dated row either way,
-- so the day ledger, the agent's float and the settlement total are the same.
-- What broke was the grouping, which is the thing the receipt is FOR.
--
-- planned_business_end_date is a forecast. actual_end_date is the fact, and
-- until it is set the period has not ended. A Running period therefore
-- extends to today, and a closed one stops where it actually stopped.
CREATE OR REPLACE FUNCTION app.account_period_window(
  p_agent_membership_id UUID, p_business_date DATE)
RETURNS TABLE (cycle_from DATE, cycle_to DATE)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
  SELECT ap.business_start_date::DATE,
         COALESCE(
           ap.actual_end_date::DATE,
           -- Still running: open-ended, so today is inside it however long
           -- the round has taken.
           CASE WHEN ap.status = 'Running'
                THEN GREATEST(p_business_date, ap.planned_business_end_date::DATE)
                ELSE ap.planned_business_end_date::DATE
           END)
    FROM account_periods ap
   WHERE ap.agent_membership_id = p_agent_membership_id
     AND p_business_date >= ap.business_start_date::DATE
     AND (
       ap.actual_end_date IS NOT NULL
         AND p_business_date <= ap.actual_end_date::DATE
       OR ap.actual_end_date IS NULL
         AND (ap.status = 'Running'
              OR p_business_date <= ap.planned_business_end_date::DATE)
     )
   ORDER BY ap.business_start_date DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION app.account_period_window IS
  'The one-entry window for a Weekly or Monthly loan: the account period the '
  'collector is working. A Running period is open-ended -- its planned end is '
  'a forecast, not a boundary. Returns no row when no period covers the date, '
  'and callers then fall back to the day.';

-- record_collection reads the window through the shared function rather than
-- its own copy of the rule. Patched in place off the live definition so the
-- rest of the body -- authorisation, validation, the parent-receipt link, the
-- BF and balance writes -- stays exactly as the previous migration left it.
DO $mig$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'record_collection';

  v_def := replace(v_def,
'    SELECT ap.business_start_date::DATE,
           COALESCE(ap.actual_end_date, ap.planned_business_end_date)::DATE
      INTO v_cycle_from, v_cycle_to
      FROM account_periods ap
     WHERE ap.agent_membership_id = p_collected_by_membership_id
       AND p_business_date >= ap.business_start_date::DATE
       AND p_business_date <= COALESCE(ap.actual_end_date, ap.planned_business_end_date)::DATE
     ORDER BY ap.business_start_date DESC
     LIMIT 1;',
'    -- One definition of the window, shared with v_collection_due. A Running
    -- period is open-ended: its planned end is a forecast, and an agent who
    -- works Tuesday to Monday before submitting is inside it the whole time.
    SELECT w.cycle_from, w.cycle_to INTO v_cycle_from, v_cycle_to
      FROM app.account_period_window(p_collected_by_membership_id, p_business_date) w;');

  IF v_def NOT LIKE '%account_period_window%' THEN
    RAISE EXCEPTION 'window block not found — record_collection was not patched';
  END IF;

  EXECUTE v_def;
END
$mig$;

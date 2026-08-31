-- An account period had a planned end date, and the plan was always wrong.
--
-- planned_business_end_date was computed at creation from the operating
-- area's account_cycle_duration and unit -- three days, a week, a month --
-- and an agent works until they hand the money over, not until a number
-- configured months ago says the round is done. Every bug this caused was the
-- same bug: a forecast used as a boundary. Collections after day four landed
-- outside the window, so one customer paying Rs 100 a day got four receipts
-- across one account. The settlement preview scoped itself to those planned
-- dates and read Rs 0 against a float of Rs 5,08,930.
--
-- Both were patched by treating a Running period as open-ended. This removes
-- the thing being worked around: a period has no planned end. It starts when
-- the previous one was submitted and it ends when this one is.
--
-- The column stays, nullable, because closed periods created before today
-- have real values in it and their history should keep saying what was
-- planned at the time. NULL means "runs until submitted", which is now every
-- new period.
ALTER TABLE account_periods
  ALTER COLUMN planned_business_end_date DROP NOT NULL;

COMMENT ON COLUMN account_periods.planned_business_end_date IS
  'NULL on every period created from 2026-08-31: an account runs until the '
  'agent submits it, so there is no planned end. Non-null values are '
  'historical -- what the cycle configuration predicted before that '
  'configuration was removed. Never a boundary: use app.account_period_window.';

-- The window now has a third case: no planned end at all.
--
-- Same shape as before otherwise. A closed period stops where it actually
-- stopped, a Running one reaches today, and a period with no plan and no
-- actual end is open by definition rather than by comparison.
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
           -- Still running, or never had a plan: open-ended, so today is
           -- inside it however long the round has taken.
           CASE WHEN ap.status = 'Running' OR ap.planned_business_end_date IS NULL
                THEN GREATEST(p_business_date,
                              COALESCE(ap.planned_business_end_date::DATE, p_business_date))
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
              OR ap.planned_business_end_date IS NULL
              OR p_business_date <= ap.planned_business_end_date::DATE)
     )
   ORDER BY ap.business_start_date DESC
   LIMIT 1;
$$;

COMMENT ON FUNCTION app.account_period_window IS
  'The one-entry window for a Weekly or Monthly loan: the account period the '
  'collector is working. A period runs from its start until it is submitted; '
  'planned_business_end_date is historical and never a boundary. Returns no '
  'row when no period covers the date, and callers then fall back to the day.';

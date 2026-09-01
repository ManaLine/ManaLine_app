-- A weekly customer could not be collected from for fifteen days.
--
-- The one-entry window for a Weekly or Monthly loan was the account period.
-- That was defensible while a period was four planned days. It stopped being
-- defensible when I made periods open-ended -- they now run from the last
-- submission until the next -- so the window stretched to fifteen days and
-- counting, and every customer already collected once inside it showed as
-- done with no way to take this week's money. My regression, from
-- 20260831171213.
--
-- The two ideas were conflated. An account period is about handing cash to
-- the Owner. A repayment type is about how often somebody pays. They are
-- different clocks and only one of them belongs in "have they paid yet".
--
-- THE RULE, as the Owner states it: a Weekly loan is collected once a week, a
-- Monthly loan once a month -- and submitting an account also starts a fresh
-- entry, because money taken after the handover belongs to the next account.
-- So the window starts at the LATER of the two: this week's start, or the
-- current account period's start.
--
-- Calendar weeks (Monday) and calendar months, not seven-day buckets counted
-- from each loan's issue date. An agent walking a round thinks "this week",
-- not "day 8 of Ramesh's cycle", and a per-loan bucket is unexplainable at a
-- doorstep when two neighbours fall on different days.
--
-- Daily loans are unchanged: their window is the day, as it always was.
CREATE OR REPLACE FUNCTION app.collection_entry_window(
  p_agent_membership_id UUID,
  p_business_date DATE,
  p_repayment_type repayment_frequency_enum
)
RETURNS TABLE (window_from DATE, window_to DATE, window_kind TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_period_from DATE;
  v_cadence_from DATE;
  v_kind TEXT;
BEGIN
  IF p_repayment_type = 'Daily' OR p_repayment_type IS NULL THEN
    RETURN QUERY SELECT p_business_date, p_business_date, 'day'::text;
    RETURN;
  END IF;

  IF p_repayment_type = 'Weekly' THEN
    v_cadence_from := date_trunc('week', p_business_date)::date;
    v_kind := 'week';
  ELSE
    v_cadence_from := date_trunc('month', p_business_date)::date;
    v_kind := 'month';
  END IF;

  -- The account the collector is working, if any. No period -- the Owner
  -- collecting, or an Agent with no session open -- leaves the cadence to
  -- stand on its own.
  SELECT w.cycle_from INTO v_period_from
    FROM app.account_period_window(p_agent_membership_id, p_business_date) w;

  IF v_period_from IS NOT NULL AND v_period_from > v_cadence_from THEN
    -- The account started mid-week: this week's entry has not been used yet,
    -- because everything before the handover belongs to the account that was
    -- handed over.
    v_cadence_from := v_period_from;
    v_kind := v_kind || ' (since this account opened)';
  END IF;

  RETURN QUERY SELECT v_cadence_from, p_business_date, v_kind;
END;
$$;

COMMENT ON FUNCTION app.collection_entry_window IS
  'How long one collection entry covers, for the duplicate check. Daily: the '
  'day. Weekly: the calendar week. Monthly: the calendar month. In every case '
  'never reaching back before the current account period started, because '
  'submitting an account starts a fresh entry. Shared by record_collection '
  'and v_collection_due so the round and the write cannot disagree.';

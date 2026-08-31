-- account_cycle_duration, account_cycle_unit and submission_time are NOT NULL
-- with no default, so every caller had to supply a cycle even though nothing
-- reads one any more -- an account runs from the last submission to the next.
--
-- Defaults rather than DROP COLUMN. Dropping is irreversible and these carry
-- real history: what each area's rounds were planned to be before the
-- configuration was removed. Left in place with a default, the columns stop
-- being a question anybody has to answer and stay readable if the reason for
-- an old planned_business_end_date is ever asked.
--
-- Nothing in app.* reads them now: add_area_to_session, start_business_session
-- and assign_agent_area were the three, and all three were patched to open
-- periods with no planned end.
ALTER TABLE operating_areas
  ALTER COLUMN account_cycle_duration SET DEFAULT 3,
  ALTER COLUMN account_cycle_unit SET DEFAULT 'Days',
  ALTER COLUMN submission_time SET DEFAULT '21:00:00';

COMMENT ON COLUMN operating_areas.account_cycle_duration IS
  'Historical. An account period runs until the agent submits it; nothing '
  'reads this. Kept, with a default, so old planned_business_end_date values '
  'remain explicable.';
COMMENT ON COLUMN operating_areas.account_cycle_unit IS
  'Historical — see account_cycle_duration.';
COMMENT ON COLUMN operating_areas.submission_time IS
  'Historical — see account_cycle_duration. Submission is when the agent '
  'submits, not a configured hour.';

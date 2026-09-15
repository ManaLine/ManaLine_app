-- Answering the one product question worth answering, without an SDK.
--
-- docs/decisions/2026-09-15-analytics.md: the highest-value unknown is WHERE
-- OWNERS ABANDON MIGRATION. It is the longest, hardest flow in the app, it is
-- the first thing a new business does, and a business that fails it never
-- becomes a user at all. The whole one-at-a-time door was built on a GUESS
-- about that flow and nothing measures whether the guess was right.
--
-- NO ANALYTICS SDK, and this is why. Every screen here carries a villager's
-- name, village, phone and outstanding balance. A general-purpose SDK
-- defaults to automatic screen tracking and device identifiers, and sends
-- them outside India. The people in this database signed up to borrow money,
-- not to be measured, and most could not meaningfully be asked.
--
-- businesses.migration_wizard_step already exists. Two columns turn it from a
-- resume pointer into an answer:
--
--   migration_wizard_step goes BACKWARDS when an Owner navigates back, so it
--   says where somebody is, not how far they got. furthest_step never
--   decreases.
--
--   Without a timestamp, "stopped at step 4" cannot be told from "is on step
--   4 right now". Abandonment is a question about time, not position.
--
-- Nothing leaves the handset that was not already there. These are two
-- columns on a row the Owner already owns, readable only through the same RLS
-- everything else uses.
ALTER TABLE businesses
    ADD COLUMN IF NOT EXISTS migration_furthest_step SMALLINT,
    ADD COLUMN IF NOT EXISTS migration_step_touched_at TIMESTAMP;

COMMENT ON COLUMN businesses.migration_furthest_step IS
  'The highest wizard step this business ever reached. Never decreases, unlike '
  'migration_wizard_step, which follows the Owner backwards when they navigate '
  'back. This is the one that answers "where did they stop".';
COMMENT ON COLUMN businesses.migration_step_touched_at IS
  'When the wizard step last moved. Without it, "stopped at step 4" cannot be '
  'told apart from "is on step 4 right now".';

-- Backfilled from what is already known, so the column is not blank for every
-- business that migrated before today. GREATEST against the current step
-- because that is the only evidence available for the past.
UPDATE businesses
   SET migration_furthest_step = GREATEST(COALESCE(migration_furthest_step, 0),
                                          COALESCE(migration_wizard_step, 0))
 WHERE migration_wizard_step IS NOT NULL;

-- Recorded where the step is already written, so nothing else has to remember.
-- DROP then CREATE is not needed: the parameter list is unchanged.
CREATE OR REPLACE FUNCTION app.set_migration_wizard_step(
    p_business_id UUID,
    p_step SMALLINT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the owner may set the migration step'
      USING ERRCODE = '42501';
  END IF;

  UPDATE businesses
     SET migration_wizard_step = p_step,
         -- Never backwards. An Owner who reaches step 6 and navigates to step
         -- 2 has still reached 6, and that is the fact worth keeping.
         migration_furthest_step =
           GREATEST(COALESCE(migration_furthest_step, 0), COALESCE(p_step, 0)),
         migration_step_touched_at = now()
   WHERE business_id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.set_migration_wizard_step(UUID, SMALLINT) TO authenticated;

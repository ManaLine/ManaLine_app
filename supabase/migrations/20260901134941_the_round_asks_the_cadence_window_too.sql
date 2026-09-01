-- The round's "already collected" test now asks the same window the write
-- does, so the screen and record_collection cannot disagree about whether
-- this week's money has been taken.
--
-- Rebuilt from the view's own definition with one substitution, rather than
-- retyped: v_collection_due carries a long list of lateral joins for the
-- visit, the extension, the address and the day's takings, and retyping them
-- to change one join is how a column quietly goes missing.
--
-- The lateral gains a third output column (the window's name) which nothing
-- selects yet; the view's own column list is unchanged, which is what
-- CREATE OR REPLACE VIEW requires.
DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT;
  v_new TEXT;
BEGIN
  SELECT pg_get_viewdef(c.oid) INTO v_def
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relname = 'v_collection_due' AND n.nspname = 'app';

  v_old := 'app.account_period_window(l.collection_agent_membership_id, CURRENT_DATE) period(cycle_from, cycle_to)';
  v_new := 'app.collection_entry_window(l.collection_agent_membership_id, CURRENT_DATE, l.repayment_type) period(cycle_from, cycle_to, cycle_kind)';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'v_collection_due window join not found -- not patched';
  END IF;

  EXECUTE 'CREATE OR REPLACE VIEW app.v_collection_due AS ' || replace(v_def, v_old, v_new);
END
$mig$;

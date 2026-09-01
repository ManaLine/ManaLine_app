-- record_collection asks the shared window function now, so the write and the
-- round agree on whether somebody has already paid this week.
--
-- Patched off the live definition so nothing else in this body moves: the
-- authorisation checks, the duplicate guard, the parent-receipt link, the BF
-- and balance writes and the idempotency replay are exactly as the previous
-- migrations left them. The only change is which window is asked for.
DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT;
  v_new TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'record_collection';

  v_old := '  IF v_repayment_type <> ''Daily'' THEN
    -- One definition of the window, shared with v_collection_due. A Running
    -- period is open-ended: its planned end is a forecast, and an agent who
    -- works Tuesday to Monday before submitting is inside it the whole time.
    SELECT w.cycle_from, w.cycle_to INTO v_cycle_from, v_cycle_to
      FROM app.account_period_window(p_collected_by_membership_id, p_business_date) w;
    IF v_cycle_from IS NOT NULL THEN
      v_from := v_cycle_from;
      v_to   := v_cycle_to;
      v_window := ''cycle'';
    END IF;
  END IF;';

  v_new := '  -- One definition of the window, shared with v_collection_due: the
  -- calendar week or month, never reaching back past the account period the
  -- collector is working. It used to be the account period itself, which
  -- became fifteen days once periods stopped having a planned end -- so a
  -- weekly customer collected once could not be collected again until a
  -- settlement was submitted.
  SELECT w.window_from, w.window_to, w.window_kind
    INTO v_cycle_from, v_cycle_to, v_window
    FROM app.collection_entry_window(
           p_collected_by_membership_id, p_business_date, v_repayment_type) w;
  IF v_cycle_from IS NOT NULL THEN
    v_from := v_cycle_from;
    v_to   := v_cycle_to;
  END IF;';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'record_collection window block not found -- not patched';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;

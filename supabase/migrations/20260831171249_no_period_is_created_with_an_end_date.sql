-- The three places that opened an account period all computed an end date
-- from the operating area's cycle configuration. There is no cycle
-- configuration any more: a period runs until the agent submits it.
--
-- Patched off the live definitions so nothing else in these bodies moves --
-- the authorisation checks, the draft guard, the already-Running guard and
-- the audit rows are all exactly as the previous migrations left them. The
-- only change in each is that planned_business_end_date is NULL, which turns
-- three SELECT ... FROM operating_areas inserts into plain VALUES inserts,
-- since operating_areas was only being read for the duration and unit.
DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT;
  v_new TEXT;
BEGIN
  -- add_area_to_session
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'add_area_to_session';

  v_old := '  SELECT v_business_id, p_area_id, p_membership_id, v_now,
         v_now + CASE oa.account_cycle_unit
           WHEN ''Days'' THEN (oa.account_cycle_duration::TEXT || '' days'')::INTERVAL
           WHEN ''Weeks'' THEN (oa.account_cycle_duration::TEXT || '' weeks'')::INTERVAL
           WHEN ''Months'' THEN (oa.account_cycle_duration::TEXT || '' months'')::INTERVAL
         END,
         ''Running''
  FROM operating_areas oa WHERE oa.operating_area_id = p_area_id
  RETURNING account_period_id INTO v_period_id;';
  v_new := '  VALUES (v_business_id, p_area_id, p_membership_id, v_now, NULL, ''Running'')
  RETURNING account_period_id INTO v_period_id;';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'add_area_to_session insert block not found — not patched';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);

  -- start_business_session
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'start_business_session';

  v_old := '    SELECT v_business_id, v_area_id, p_membership_id, v_now,
           v_now + CASE oa.account_cycle_unit
             WHEN ''Days'' THEN (oa.account_cycle_duration::TEXT || '' days'')::INTERVAL
             WHEN ''Weeks'' THEN (oa.account_cycle_duration::TEXT || '' weeks'')::INTERVAL
             WHEN ''Months'' THEN (oa.account_cycle_duration::TEXT || '' months'')::INTERVAL
           END,
           ''Running''
    FROM operating_areas oa WHERE oa.operating_area_id = v_area_id
    RETURNING account_period_id INTO v_period_id;';
  v_new := '    VALUES (v_business_id, v_area_id, p_membership_id, v_now, NULL, ''Running'')
    RETURNING account_period_id INTO v_period_id;';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'start_business_session insert block not found — not patched';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);

  -- assign_agent_area
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'assign_agent_area';

  v_old := '      v_business_id, p_operating_area_id, v_membership_id, now(),
      now() + (v_dur || '' '' ||
        CASE v_unit WHEN ''Weeks'' THEN ''week'' WHEN ''Months'' THEN ''month'' ELSE ''day'' END)::interval,
      ''Running''';
  v_new := '      v_business_id, p_operating_area_id, v_membership_id, now(),
      NULL,
      ''Running''';

  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'assign_agent_area insert block not found — not patched';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;

-- The expense branch itself, added to ledger_history.
--
-- Rewritten from the function's own source so the eight branches already there
-- are untouched and only the new one is added. Rebuilding a nine-branch UNION
-- by hand from a paste would risk changing something nobody was looking at.
DO $$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'ledger_history';

  v_src := replace(v_src,
'    UNION ALL

    SELECT ''adjustment:'' || sa.adjustment_id,',
'    UNION ALL

    -- The migrated book''s own expense lines. They live on migration_weeks
    -- because import_weekly_account writes nothing to `expenses`; copying them
    -- there would double-count against day_ledger and profit, both of which
    -- already take the week''s declared figure. Read, not copied.
    SELECT me.line_key, ''expense'', ''out'',
           me.business_date, me.business_date::timestamp,
           me.amount, NULL, me.label, NULL
    FROM app.migrated_expense_lines(p_business_id) me

    UNION ALL

    SELECT ''adjustment:'' || sa.adjustment_id,');

  IF position('migrated_expense_lines' in v_src) = 0 THEN
    RAISE EXCEPTION 'The patch did not apply: ledger_history no longer contains the text it was matching on.';
  END IF;

  EXECUTE v_src;
END $$;

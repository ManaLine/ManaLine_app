-- `?` is a jsonb operator; p_rows is json, so the key test has to be a null
-- check on the extracted value. plpgsql applied the body happily and failed on
-- the first call, as it always does.
--
-- Applied as an in-place text substitution on the stored body. The corrected
-- form is already written into 20260818133308, so replaying the batch from
-- scratch makes this a no-op rather than a second edit.
DO $$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'import_weekly_account';

  v_src := replace(v_src,
    'IF v_row ? ''expenses_total'' THEN',
    'IF (v_row -> ''expenses_total'') IS NOT NULL THEN');

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION app.import_weekly_account(p_business_id uuid, p_rows json)
     RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS %L',
    v_src);
END $$;

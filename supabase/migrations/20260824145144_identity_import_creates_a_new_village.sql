-- The identity import creates a village it has not seen, rather than refusing.
--
-- It raised: 'Village "X" (PIN Y) has not been added yet - add it on the Areas
-- & Villages step first.' That step came AFTER identities in the wizard, so
-- the order was back to front from the start. Villages are now set up before
-- the wizard runs and the identity sheet offers them as a dropdown -- but a
-- dropdown that refuses what is not on it would stop a migration over the one
-- thing the Owner is most likely to be right about: the name of a village they
-- collect in every week.
--
-- Rewritten from the function's own source so the rest of it -- dedupe
-- decisions, MLID minting, every other role -- is untouched. Rebuilding it by
-- hand from a paste would risk changing something nobody was looking at.
DO $$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'bulk_import_identities';

  v_src := replace(v_src,
'        IF v_pin <> '''' AND v_village IS NOT NULL THEN
          SELECT location_id INTO v_location
            FROM locations
           WHERE pin_code = v_pin AND lower(village_town_name) = lower(v_village);
          IF v_location IS NULL THEN
            RAISE EXCEPTION ''Village "%" (PIN %) has not been added yet - add it on the Areas & Villages step first.'',
              v_village, v_pin USING ERRCODE = ''P0002'';
          END IF;',
'        IF v_pin <> '''' AND v_village IS NOT NULL THEN
          -- Created if it is new, rather than refused. See the migration note.
          -- find_or_create_village resolves the real mandal and district out
          -- of lgd_villages where it can, and leaves them Unconfirmed where it
          -- cannot -- being absent from the register is not grounds for
          -- refusing someone their own book.
          v_location := app.find_or_create_village(v_pin::varchar, v_village::varchar);');

  IF position('find_or_create_village' in v_src) = 0 THEN
    RAISE EXCEPTION 'The patch did not apply: bulk_import_identities no longer contains the text it was matching on.';
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION app.bulk_import_identities(p_business_id uuid, p_rows json)
     RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS %L',
    v_src);
END $$;

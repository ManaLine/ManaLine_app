-- The Customers page runs before the Weekly Account page, and at that point
-- migrated_through_date is still NULL - so replaying the instalment history
-- fires tg_recompute_day_ledger and leaves a DERIVED day_ledger row on every
-- collection date inside what is about to become the migrated span.
--
-- Those rows are exactly the thing this design rejects: figures computed from
-- transactions for a period the book already states. Inside the span only the
-- account dates are real, so the importer clears the rest of the span once it
-- knows where the span ends. It never touches a date outside it.
CREATE OR REPLACE FUNCTION app.migration_clear_derived_days(
  p_business_id uuid,
  p_from date,
  p_through date,
  p_account_dates date[]
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM day_ledger
   WHERE business_id = p_business_id
     AND business_date >= p_from
     AND business_date <= p_through
     AND NOT (business_date = ANY (p_account_dates));
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- Applied as a text substitution on the stored body of import_weekly_account:
-- collect each account date as it is written, then clear everything else in the
-- span just before the business row is stamped.
DO $$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'import_weekly_account';

  v_src := replace(v_src,
    '  v_last_close numeric := NULL;
  v_last_date date := NULL;',
    '  v_last_close numeric := NULL;
  v_last_date date := NULL;
  v_dates date[] := ''{}'';');

  v_src := replace(v_src,
    '    v_prev_close := v_close; v_prev_date := v_date;
    v_last_close := v_close; v_last_date := v_date;',
    '    v_dates := v_dates || v_date;
    v_prev_close := v_close; v_prev_date := v_date;
    v_last_close := v_close; v_last_date := v_date;');

  v_src := replace(v_src,
    '  UPDATE businesses
     SET migrated_through_date =',
    '  PERFORM app.migration_clear_derived_days(p_business_id, v_first_date, v_last_date, v_dates);

  UPDATE businesses
     SET migrated_through_date =');

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION app.import_weekly_account(p_business_id uuid, p_rows json)
     RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS %L',
    v_src);
END $$;

GRANT EXECUTE ON FUNCTION app.migration_clear_derived_days(uuid, date, date, date[]) TO authenticated, service_role;

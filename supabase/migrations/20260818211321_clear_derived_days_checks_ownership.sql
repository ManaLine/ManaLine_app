-- Found in review, not in testing: app.migration_clear_derived_days is
-- SECURITY DEFINER, granted to `authenticated`, takes a business_id and a date
-- range, and DELETES day_ledger rows — with no authorization check at all. Any
-- signed-in person could have erased another business's ledger days by calling
-- it directly; RLS does not save you inside a definer function, that is the
-- point of one.
--
-- It is only ever called from app.import_weekly_account, which does check
-- ownership, so nothing reached it wrongly in practice. The check belongs here
-- regardless: a definer function has to stand on its own, because the next
-- caller will not be the one you had in mind.
CREATE OR REPLACE FUNCTION app.migration_clear_derived_days(
  p_business_id uuid,
  p_from date,
  p_through date,
  p_account_dates date[]
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_deleted INT;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  -- A null or empty span would widen the delete rather than narrow it.
  IF p_from IS NULL OR p_through IS NULL OR p_through < p_from THEN
    RAISE EXCEPTION 'A from/through span is required.' USING ERRCODE = '23514';
  END IF;

  DELETE FROM day_ledger
   WHERE business_id = p_business_id
     AND business_date >= p_from
     AND business_date <= p_through
     AND NOT (business_date = ANY (COALESCE(p_account_dates, ARRAY[]::date[])));
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

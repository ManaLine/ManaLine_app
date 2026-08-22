-- Clearing derived days must cover the whole span, not just from the first
-- account row onwards.
--
-- import_weekly_account passes the first and last account dates. Anything
-- dated BEFORE the book's first account row therefore survived -- while still
-- sitting inside migrated_through_date, where recompute_day_ledger returns
-- early and can never touch it again. A permanent orphan, derived, inside a
-- span the book otherwise governs.
--
-- sri satyanarayana had one: 2026-01-01, holding three loans that the book had
-- already counted in its 2-1 account row, opening on Rs 100 (the cut-off cash
-- used as a day-one seed) and closing on MINUS Rs 68,500.
--
-- p_from stays in the signature and still narrows the delete; it is now taken
-- together with the earliest ledger row the business actually has, so the span
-- starts where the data starts. The null/empty guard is unchanged: it is there
-- to stop a missing argument widening the delete, and that still holds.
CREATE OR REPLACE FUNCTION app.migration_clear_derived_days(
  p_business_id uuid, p_from date, p_through date, p_account_dates date[])
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_deleted INT;
  v_first   DATE;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  -- A null or empty span would widen the delete rather than narrow it.
  IF p_from IS NULL OR p_through IS NULL OR p_through < p_from THEN
    RAISE EXCEPTION 'A from/through span is required.' USING ERRCODE = '23514';
  END IF;

  -- Where the ledger actually starts, which may be before the book's first
  -- account row.
  SELECT MIN(business_date) INTO v_first
    FROM day_ledger WHERE business_id = p_business_id;
  v_first := LEAST(p_from, COALESCE(v_first, p_from));

  DELETE FROM day_ledger
   WHERE business_id = p_business_id
     AND business_date >= v_first
     AND business_date <= p_through
     AND NOT (business_date = ANY (COALESCE(p_account_dates, ARRAY[]::date[])));
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$function$;

-- The days a business actually did something on.
--
-- THE OWNER'S RULE, 2026-09-17: "show only submitted accounts (with any of
-- these - an active collection or loan or an expense)". The Daily Record Book
-- was listing every day_ledger row, and day_ledger has a row for every day the
-- recompute trigger has ever touched -- including days where the figures are
-- all zero because nothing happened. Counted before writing this: 82 ledger
-- rows across five businesses, 17 with any activity. Three whole books were
-- showing nothing but empty days.
--
-- EXISTENCE OF A ROW, NOT A NON-ZERO TOTAL. The client could have filtered on
-- (collections > 0 OR loans > 0 OR expenses > 0) without a round trip, and it
-- would be wrong in the direction that hides work: a collection recorded as a
-- no-payment, or a written-off expense, is a day somebody worked and must
-- appear. "Active" here means a live row exists.
--
-- COLLECTIONS HAVE NO business_id -- they reach the business through loan_id,
-- which is why this is a subquery rather than a fourth column on a UNION of
-- three flat scans. Checked against information_schema before writing it.
--
-- deleted_at IS NULL on all three, matching app.recompute_day_ledger. A day
-- whose only entry was deleted is a day with nothing on it, and the ledger
-- already agrees -- its figures recomputed to zero when the delete landed.
--
-- TWO CONSUMERS, ONE ANSWER, deliberately. The list filters itself on this,
-- and the date picker offers exactly these dates ("only show dates that are
-- actively submitted account dates"). If they were computed separately the
-- calendar would eventually offer a day the list refuses to show.
--
-- SUPERSEDED THE SAME DAY by 20260917182338, which found this rule hides a
-- migrated weekly account -- a day carrying real money with no source rows
-- behind it. Left here unedited because a migration file is a record of what
-- ran, not something to correct until it looks right.

CREATE OR REPLACE FUNCTION app.active_account_dates(
  p_business_id uuid,
  p_from        date DEFAULT NULL,
  p_to          date DEFAULT NULL
) RETURNS TABLE(business_date date)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- plpgsql so this can RAISE. As a WHERE clause, an unauthorized reader
  -- would get zero dates -- indistinguishable from a book nobody has used.
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s account dates'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT d FROM (
    SELECT l.issue_business_date AS d
      FROM loans l
     WHERE l.business_id = p_business_id
       AND l.deleted_at IS NULL
    UNION
    SELECT c.business_date
      FROM collections c
     WHERE c.deleted_at IS NULL
       AND c.loan_id IN (SELECT l2.loan_id FROM loans l2
                          WHERE l2.business_id = p_business_id)
    UNION
    SELECT e.business_date
      FROM expenses e
     WHERE e.business_id = p_business_id
       AND e.deleted_at IS NULL
  ) s
  WHERE (p_from IS NULL OR d >= p_from)
    AND (p_to   IS NULL OR d <= p_to)
  ORDER BY d DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.active_account_dates(uuid, date, date)
  TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'active_account_dates';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'active_account_dates has % overloads', v_n;
  END IF;
END $$;

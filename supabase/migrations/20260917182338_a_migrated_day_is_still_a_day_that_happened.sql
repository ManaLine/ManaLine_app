-- Corrects app.active_account_dates, written an hour earlier in this session
-- against a rule I had taken too literally.
--
-- The Owner's words were "an active collection or loan or an expense". Taken
-- at face value that is EXISTS on the three source tables, which is what the
-- first version did. Counted against the real book before believing it:
--
--   17  ledger days with source rows behind them
--    1  ledger day carrying money with NO source rows
--   22  ledger days that are genuinely empty
--
-- That middle day is a WEEKLY MIGRATED ACCOUNT. app.import_weekly_account
-- writes aggregate figures straight into day_ledger for history that pre-dates
-- the app -- there were never per-row loans or collections to find, which is
-- why the ledger holds Rs 9,76,640 more in loans and Rs 10,11,800 more in
-- collections than the source tables do. Hiding it would have deleted a
-- fortnight of somebody's book from their own screen, and the figures would
-- still have been inside the BF chain, so the day AFTER it would have opened
-- on a balance with no visible cause.
--
-- So: a day is active if a source row exists OR any figure on it is non-zero.
-- The second clause is what makes migrated history visible; the first is what
-- keeps a no-payment collection or a written-off expense visible when every
-- figure happens to be zero. Neither subsumes the other.
--
-- SIGNATURE UNCHANGED -- (uuid, date, date) -- so CREATE OR REPLACE is the
-- correct tool here and does not create the second overload CLAUDE.md warns
-- about. The overload count is asserted below regardless.
--
-- KNOWN AND DELIBERATELY NOT FIXED HERE: 12 dates on this book carry loans or
-- collections and have no day_ledger row at all (2026-01-01 through 03-19,
-- each exactly one day before a migrated weekly row). They cannot appear in a
-- list built from day_ledger, and this function does not pretend otherwise by
-- offering a date the list would refuse. Recomputing them is a money change on
-- a live book -- the weekly aggregate beside each one may already contain the
-- same rows, in which case recompute would double count -- so it is a decision
-- to be taken deliberately, not a side effect of a display fix.

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
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s account dates'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT d.business_date
    FROM day_ledger d
   WHERE d.business_id = p_business_id
     AND (p_from IS NULL OR d.business_date >= p_from)
     AND (p_to   IS NULL OR d.business_date <= p_to)
     AND (
       d.total_collections > 0 OR d.total_loan_distribution > 0
       OR d.total_expenses > 0 OR d.investor_deposits > 0
       OR d.investor_withdrawals > 0 OR d.cheti_paid > 0
       OR d.cheti_received > 0
       -- collections carry no business_id; they reach the book via loan_id.
       OR EXISTS (SELECT 1 FROM collections c
                   WHERE c.deleted_at IS NULL
                     AND c.business_date = d.business_date
                     AND c.loan_id IN (SELECT l2.loan_id FROM loans l2
                                        WHERE l2.business_id = p_business_id))
       OR EXISTS (SELECT 1 FROM loans l
                   WHERE l.business_id = p_business_id
                     AND l.deleted_at IS NULL
                     AND l.issue_business_date = d.business_date)
       OR EXISTS (SELECT 1 FROM expenses e
                   WHERE e.business_id = p_business_id
                     AND e.deleted_at IS NULL
                     AND e.business_date = d.business_date)
     )
   ORDER BY d.business_date DESC;
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

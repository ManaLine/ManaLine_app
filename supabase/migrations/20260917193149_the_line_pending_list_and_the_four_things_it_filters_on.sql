-- The Line Pending List, design document section 2.6.1.1, reached from the
-- Account Sheet (2.6) the Daily Record Book now draws.
--
--   "From date - to date.
--    Bal Amount Min.- Eg. 0, 500, 5000.
--    Select No. of pending Weeks/Months- Eg. Last 10weeks/Last 3Months.
--    Add Sort by option (New,Old,Date,Amount,Name,Village name & Pin)."
--
-- WHAT "PENDING WEEKS" MEANS, because the obvious reading is wrong.
--
-- The easy definition is instalments REMAINING -- balance divided by the
-- instalment. Computed against the live book it returns 947 to 984 for the two
-- Daily loans, which is not a number anybody would call "weeks pending"; it is
-- how much of the loan is left to run, and a loan issued yesterday would top
-- the list.
--
-- What a line business means is instalments OVERDUE: how many have come due
-- since the loan was issued, minus how many have actually been paid. On the
-- same data that gives 0-34 weeks, 3-4 months and 205-207 days, which is a
-- book somebody would recognise. So:
--
--   elapsed = floor((today - issue_business_date) / period_days)
--   paid    = floor((repayment_amount - remaining_balance) / installment_amount)
--   overdue = greatest(0, elapsed - paid)
--
-- GREATEST(0, ...) because a customer who has paid ahead is not owed a
-- negative number of weeks, and because a loan issued today divides to zero.
--
-- The unit follows the loan, so one filter box means weeks on a weekly loan
-- and months on a monthly one -- which is exactly how the document writes it,
-- "Weeks/Months" in one line. Mixing both in one list and filtering on a bare
-- count is the honest behaviour: an Owner asking for "10 pending" wants
-- everyone ten periods behind, whatever their period is.
--
-- installment_amount is never zero or null on the live book (checked: 0 of 59)
-- but NULLIF guards the division anyway -- a divide-by-zero here would take out
-- the whole list rather than one row.
--
-- period_days: Daily 1, Weekly 7, Monthly 30. Thirty, not a calendar month,
-- matching the 30-day month CLAUDE.md pins the interest engine to.
--
-- NO SORTING HERE. Six sort orders over a list this size (52 pending loans on
-- the largest live book) belong in the client, where changing one is instant
-- and costs no round trip. The RPC returns a stable order so the list does not
-- shuffle between loads.

CREATE OR REPLACE FUNCTION app.line_pending_list(
  p_business_id uuid,
  p_from        date    DEFAULT NULL,
  p_to          date    DEFAULT NULL,
  p_min_balance numeric DEFAULT 0,
  p_min_periods integer DEFAULT 0
) RETURNS TABLE(
  loan_id            uuid,
  customer_id        uuid,
  full_name          text,
  care_of            text,
  village            text,
  pin_code           text,
  balance            numeric,
  installment_amount numeric,
  repayment_type     text,
  issued             date,
  periods_overdue    integer,
  last_paid          date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s pending list'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH pending AS (
    SELECT l.loan_id, l.customer_id, l.remaining_balance, l.installment_amount,
           l.repayment_type::text AS rtype, l.issue_business_date,
           GREATEST(0,
             FLOOR((CURRENT_DATE - l.issue_business_date)::numeric
                   / CASE l.repayment_type::text
                       WHEN 'Daily'   THEN 1
                       WHEN 'Weekly'  THEN 7
                       WHEN 'Monthly' THEN 30
                       ELSE 7
                     END)
             - FLOOR((l.repayment_amount - l.remaining_balance)
                     / NULLIF(l.installment_amount, 0))
           )::integer AS overdue
      FROM loans l
     WHERE l.business_id = p_business_id
       AND l.deleted_at IS NULL
       AND l.remaining_balance > 0
       AND (p_from IS NULL OR l.issue_business_date >= p_from)
       AND (p_to   IS NULL OR l.issue_business_date <= p_to)
  )
  SELECT p.loan_id,
         p.customer_id,
         pe.full_name,
         pe.father_husband_name,
         loc.village_town_name,
         loc.pin_code,
         p.remaining_balance,
         p.installment_amount,
         p.rtype,
         p.issue_business_date,
         p.overdue,
         (SELECT MAX(c.business_date) FROM collections c
           WHERE c.loan_id = p.loan_id AND c.deleted_at IS NULL)
    FROM pending p
    JOIN customers cu ON cu.customer_id = p.customer_id
    JOIN persons   pe ON pe.person_id   = cu.person_id
    -- LEFT, on both: a customer with no current address still owes the money,
    -- and dropping them from the pending list would hide a debt because of a
    -- missing village row.
    LEFT JOIN person_addresses pa
           ON pa.person_id = pe.person_id AND pa.is_current
    LEFT JOIN locations loc ON loc.location_id = pa.village_id
   WHERE p.remaining_balance >= COALESCE(p_min_balance, 0)
     AND p.overdue          >= COALESCE(p_min_periods, 0)
   ORDER BY p.overdue DESC, p.remaining_balance DESC, p.loan_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.line_pending_list(uuid, date, date, numeric, integer)
  TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'line_pending_list';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'line_pending_list has % overloads', v_n;
  END IF;
END $$;

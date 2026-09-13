-- A migrated book would have read 100% struck, and this is the fix.
--
-- app.migrate_loan writes the instalment schedule but NO collections -- by
-- design, because fabricating collections would put money into day_ledger on
-- days it never arrived. So a loan typed in balance-only has no collection
-- history at all, its last_collection is NULL, and "nothing collected since
-- the cutoff" is true of every single one. An Owner who had just entered two
-- hundred customers would have been told their entire book was dead money.
--
-- The Owner's own proposal solved it without any new data: infer activity from
-- the loan's dates. Their first version compared the GIVEN date against a fixed
-- six months, which is right for a twelve-week loan and wrong for a
-- twenty-four-month one -- a monthly loan eighteen months into a two-year term
-- is perfectly healthy and would have been called dead.
--
-- So the yardstick is the loan's OWN term. Instalments = repayment /
-- instalment, interval = repayment_type, and the expected end date follows --
-- the same arithmetic migrate_loan already does to build the schedule:
--
--   12 weeks given 18 months ago  -> due 15 months ago  -> struck
--   24 months given 18 months ago -> due 6 months hence -> running
--   12 weeks given 2 months ago   -> due next month     -> running
--
-- The second is the case a fixed window gets wrong, and the first is provably
-- right rather than guessed: a loan cannot have gone six months unpaid when it
-- has only existed for two.
--
-- expected_end is returned BESIDE last_collection, never merged into it. A
-- struck figure derived from loan terms is an estimate; one derived from
-- collections is a fact, and the screen has to be able to say which. Reading
-- an estimate as a fact is how somebody knocks on the wrong door.
--
-- DROP then CREATE: the RETURNS TABLE gains a column and Postgres refuses to
-- replace a function whose return type changed. Overloads verified 1 after.
-- Read-only throughout, and the money RPCs are untouched.
DROP FUNCTION IF EXISTS app.migration_customer_positions(uuid);

CREATE FUNCTION app.migration_customer_positions(
  p_business_id uuid
) RETURNS TABLE (
  person_id         bigint,
  mlid              varchar,
  full_name         varchar,
  village           varchar,
  in_operating_area boolean,
  customer_id       uuid,
  loan_id           uuid,
  balance           numeric,
  last_collection   date,
  expected_end      date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
  SELECT
    p.person_id,
    p.mlid,
    p.full_name,
    loc.village_town_name AS village,
    EXISTS (
      SELECT 1
        FROM operating_area_locations oal
       WHERE oal.business_id = p_business_id
         AND oal.location_id = pa.village_id
         AND oal.removed_at IS NULL
    ) AS in_operating_area,
    c.customer_id,
    l.loan_id,
    COALESCE(l.remaining_balance, 0) AS balance,
    (SELECT MAX(col.business_date)
       FROM collections col
      WHERE col.loan_id = l.loan_id) AS last_collection,
    -- When the loan was due to finish, from its own terms. NULL when the
    -- instalment is missing or zero -- no arithmetic is better than a divide
    -- by zero dressed up as a date.
    CASE
      WHEN l.loan_id IS NULL THEN NULL
      WHEN COALESCE(l.installment_amount, 0) <= 0 THEN NULL
      ELSE l.effective_date
           + (CEIL(l.repayment_amount / l.installment_amount)::int
              * CASE l.repayment_type
                  WHEN 'Daily'   THEN INTERVAL '1 day'
                  WHEN 'Weekly'  THEN INTERVAL '1 week'
                  WHEN 'Monthly' THEN INTERVAL '1 month'
                END)
    END::date AS expected_end
  FROM business_members bm
  JOIN persons   p ON p.person_id = bm.person_id
  JOIN customers c ON c.membership_id = bm.membership_id
  LEFT JOIN loans l
         ON l.customer_id = c.customer_id
        AND l.deleted_at IS NULL
        AND l.remaining_balance > 0
  LEFT JOIN person_addresses pa
         ON pa.person_id = p.person_id AND pa.is_current
  LEFT JOIN locations loc ON loc.location_id = pa.village_id
  WHERE bm.business_id = p_business_id
    AND bm.role = 'Customer'
    AND bm.membership_status <> 'Removed'
    AND app.is_owner(p_business_id);
$function$;

GRANT EXECUTE ON FUNCTION app.migration_customer_positions(uuid) TO anon, authenticated;

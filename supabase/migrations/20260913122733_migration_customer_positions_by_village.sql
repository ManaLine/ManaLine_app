-- What a village's book looks like, one loan per row.
--
-- The Owner enters a pre-existing book village by village, and after each
-- village wants to reconcile against the paper: how many customers, what is
-- still owed, and how much of it is money nobody has paid in months.
--
-- WHY THIS IS A FUNCTION AND NOT A QUERY FROM THE PHONE. The figure that makes
-- it useful is the LAST COLLECTION per loan, and computing that on the client
-- means pulling every collection row the business has ever recorded. A book of
-- two hundred customers collected daily is tens of thousands of rows, over a
-- village connection, to produce one screen of totals. The database does the
-- max(); the phone receives one row per loan.
--
-- SUPERSEDED IMMEDIATELY by 20260913122807, which adds in_operating_area. This
-- file is the record of what ran, not of what the function is now.
CREATE OR REPLACE FUNCTION app.migration_customer_positions(
  p_business_id uuid
) RETURNS TABLE (
  person_id      bigint,
  mlid           varchar,
  full_name      varchar,
  village        varchar,
  customer_id    uuid,
  loan_id        uuid,
  balance        numeric,
  last_collection date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
  SELECT
    p.person_id, p.mlid, p.full_name,
    loc.village_town_name AS village,
    c.customer_id, l.loan_id,
    l.remaining_balance AS balance,
    (SELECT MAX(col.business_date) FROM collections col WHERE col.loan_id = l.loan_id)
  FROM business_members bm
  JOIN persons   p ON p.person_id = bm.person_id
  JOIN customers c ON c.membership_id = bm.membership_id
  JOIN loans     l ON l.customer_id = c.customer_id
  LEFT JOIN person_addresses pa ON pa.person_id = p.person_id AND pa.is_current
  LEFT JOIN locations loc ON loc.location_id = pa.village_id
  WHERE bm.business_id = p_business_id
    AND bm.role = 'Customer'
    AND app.is_owner(p_business_id)
    AND l.deleted_at IS NULL
    AND l.remaining_balance > 0;
$function$;

GRANT EXECUTE ON FUNCTION app.migration_customer_positions(uuid) TO anon, authenticated;

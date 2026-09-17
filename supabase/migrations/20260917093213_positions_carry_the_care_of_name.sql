-- The one-person entry screen has to say whose entry it is.
--
-- Reached from a member row, that screen was drawing a VILLAGE book with the
-- person's name in the title bar: "1 Customers" above a collapsed row you had
-- to tap open to reach the loans. It was reported from a handset as exactly
-- that -- "why showing 1 customers?".
--
-- A header naming the person needs the care-of name, which is how somebody is
-- told apart from the other three men of that name in the village, and
-- persons.father_husband_name is where it lives. The RPC already returns the
-- village and the live loans; this is the one column it was missing.
--
-- DROP THEN CREATE, not CREATE OR REPLACE: the RETURNS TABLE changes, and
-- Postgres refuses to replace a function whose return type differs (42P13)
-- rather than quietly making a second one -- but the same rule is written
-- here anyway, because the next person changing this file will be changing a
-- parameter, not a column.
--
-- The loans half is untouched and already correct: the LEFT JOIN carries
-- `l.remaining_balance > 0`, so what comes back is the ACTIVE loans and
-- nothing else.

DROP FUNCTION IF EXISTS app.migration_customer_positions(uuid);

CREATE FUNCTION app.migration_customer_positions(p_business_id uuid)
RETURNS TABLE(
  person_id bigint,
  mlid character varying,
  full_name character varying,
  father_husband_name character varying,
  village character varying,
  in_operating_area boolean,
  customer_id uuid,
  loan_id uuid,
  balance numeric,
  last_collection date,
  expected_end date
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
  SELECT
    p.person_id,
    p.mlid,
    p.full_name,
    p.father_husband_name,
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

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'migration_customer_positions';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'migration_customer_positions has % overloads', v_n;
  END IF;
END $$;

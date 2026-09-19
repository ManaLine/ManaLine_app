-- A village of n customers could be searched by name and MLID, and not by
-- the thing an Owner is most likely to have in front of them.
--
-- The Owner, 2026-09-19: "add search - in one-by-one - customers - if there
-- are n customers user needs a search inside it by name, phone no, MLID."
--
-- Name and MLID were already there. The phone was not, and could not be: the
-- row this list is built from never carried it. Searching by phone is the one
-- of the three that works when somebody rings -- a name is ambiguous in a
-- village where four people share it, and nobody reads an MLID down a phone
-- before saying who they are.
--
-- DROP then CREATE, not CREATE OR REPLACE: the return shape gains a column,
-- and a second overload is how PostgREST comes to answer HTTP 300 instead of
-- choosing. The overload count is asserted below.
--
-- mobile_number is NULLable on persons -- a customer copied out of a paper
-- book may have no phone at all, which is why persons_mlti_needs_hard_key
-- accepts an Aadhaar OR a mobile OR is_migrated. Coalesced to '' so the app
-- gets a string to match against rather than a null to guard on at every
-- call site.
DROP FUNCTION IF EXISTS app.migration_customer_positions(uuid);
CREATE FUNCTION app.migration_customer_positions(p_business_id uuid)
RETURNS TABLE (
  person_id bigint,
  mlid character varying,
  full_name character varying,
  father_husband_name character varying,
  mobile_number character varying,
  village character varying,
  in_operating_area boolean,
  customer_id uuid,
  loan_id uuid,
  balance numeric,
  last_collection date,
  expected_end date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
  SELECT
    p.person_id,
    p.mlid,
    p.full_name,
    p.father_husband_name,
    COALESCE(p.mobile_number, '')::varchar AS mobile_number,
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
$$;

GRANT EXECUTE ON FUNCTION app.migration_customer_positions(uuid) TO authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'migration_customer_positions';
  IF v_n <> 1 THEN RAISE EXCEPTION 'expected 1 overload, found %', v_n; END IF;
END $$;

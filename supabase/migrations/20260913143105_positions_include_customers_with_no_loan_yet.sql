-- Every customer in the book, with their live loans if they have any.
--
-- The inner JOIN to loans meant a village where nothing had been entered yet
-- produced no rows, so it drew no card -- and the Owner had no way IN to the
-- village they were about to enter. The screen exists to enter a book, and it
-- was only willing to show the parts already entered.
--
-- Measured on a real book, before and after: 50 rows / 49 customers became 59
-- rows / 58 customers, of whom NINE have no loan. Those nine were invisible.
-- Total balance unchanged at 24,52,040 -- the check that matters, since they
-- carry nothing: no money moved, only people appeared.
--
-- LEFT JOIN, with the liveness test moved into the ON clause: putting
-- `l.deleted_at IS NULL AND l.remaining_balance > 0` in the WHERE would filter
-- the outer rows straight back out and restore the bug while looking like a fix.
--
-- A customer with no live loan comes back with loan_id NULL and balance 0.
-- They count toward the village's head count -- which is the number the Owner
-- checks against the page -- and contribute nothing to any money figure. The
-- caller must not treat them as struck: they are not a loan that stopped being
-- paid, they are a person whose loan has not been typed in yet. Their
-- last_collection is null by definition, so a struck test of "nothing since the
-- cutoff, or nothing ever" would name all nine of them as people who had
-- stopped paying, at zero rupees each.
CREATE OR REPLACE FUNCTION app.migration_customer_positions(
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
  last_collection   date
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
    -- The current address only. A person who has moved is counted in the
    -- village they are in now, which is the village an agent will walk to.
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
      WHERE col.loan_id = l.loan_id) AS last_collection
  FROM business_members bm
  JOIN persons   p ON p.person_id = bm.person_id
  JOIN customers c ON c.membership_id = bm.membership_id
  -- The liveness test lives HERE, not in the WHERE, or the outer join is
  -- undone and villages with nothing entered vanish again.
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

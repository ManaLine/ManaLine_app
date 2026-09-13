-- Adds in_operating_area to app.migration_customer_positions.
--
-- DROP then CREATE, not CREATE OR REPLACE: the RETURNS TABLE gains a column,
-- and Postgres refuses to replace a function whose return type changed. The
-- overload count is checked after -- two of these would be PGRST203 and the
-- screen would just say it could not load. Verified 1.
--
-- WHY THE SERVER ANSWERS THIS. The screen groups a book by village and needs a
-- "Not in any operating area" group so a customer in an unworked village is
-- visible rather than silently absent. Deciding that on the phone meant
-- comparing village NAMES against operatingVillages(), which formats them as
-- "Uranduru (517640)" -- so the phone would be parsing a display string back
-- into data to answer a question the database can answer with a join. String
-- matching on place names is how a village with a spelling variant quietly
-- becomes a different village.
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
    l.remaining_balance AS balance,
    (SELECT MAX(col.business_date)
       FROM collections col
      WHERE col.loan_id = l.loan_id) AS last_collection
  FROM business_members bm
  JOIN persons   p ON p.person_id = bm.person_id
  JOIN customers c ON c.membership_id = bm.membership_id
  JOIN loans     l ON l.customer_id = c.customer_id
  LEFT JOIN person_addresses pa
         ON pa.person_id = p.person_id AND pa.is_current
  LEFT JOIN locations loc ON loc.location_id = pa.village_id
  WHERE bm.business_id = p_business_id
    AND bm.role = 'Customer'
    AND app.is_owner(p_business_id)
    -- A deleted loan is not part of the book. A closed one carries no balance
    -- and would only add noise to a reconciliation.
    AND l.deleted_at IS NULL
    AND l.remaining_balance > 0;
$function$;

GRANT EXECUTE ON FUNCTION app.migration_customer_positions(uuid) TO anon, authenticated;

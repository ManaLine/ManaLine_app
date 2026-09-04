-- One place to answer "where does this person live", so the search RPC does not
-- carry a four-line correlated subquery three times over.
--
-- Written because the migration before this one called it and it did not exist.
-- That applied perfectly -- plpgsql bodies are not type-checked at CREATE time,
-- so a call to a function that has never been written is indistinguishable from
-- a correct one until something invokes it. Caught by invoking, which is the
-- only thing that ever catches it.
--
-- CURRENT address only. NULL when there is none, so a caller can tell "no
-- address on file" from a real place and show nothing rather than an empty
-- separator.
CREATE OR REPLACE FUNCTION app.person_current_village(p_person_id bigint)
RETURNS character varying
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
  SELECT l.village_town_name
    FROM person_addresses pa
    JOIN locations l ON l.location_id = pa.village_id
   WHERE pa.person_id = p_person_id
     AND pa.is_current
   LIMIT 1;
$function$;

GRANT EXECUTE ON FUNCTION app.person_current_village(bigint) TO anon, authenticated;

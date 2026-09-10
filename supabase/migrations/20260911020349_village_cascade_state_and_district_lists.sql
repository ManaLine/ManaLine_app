-- @target: production
-- Task 2 of the village cascade needs the distinct state and district lists
-- that PIN entry never had to ask for. PostgREST has no DISTINCT operator on
-- a plain table/view select -- postgrest-dart's isDistinct() filters ON a
-- value, it does not deduplicate rows -- so the only way to get 35 states
-- back instead of 767,191 rows is a function that runs the DISTINCT in SQL
-- and returns just the answer.
--
-- Measured directly (Task 1's report): `select distinct state` with no
-- filter is 244 ms because it cannot use the (state, district) index without
-- a filter and walks the whole table; `select distinct district where
-- state = ?` is 8 ms because it can. Both numbers are for the query alone --
-- calling it from Dart pays the same cost, which is exactly why the data
-- layer caches states() in memory for the process lifetime rather than
-- reissuing this.
CREATE OR REPLACE FUNCTION app.lgd_states()
RETURNS TABLE(state text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT g.state::text
    FROM lgd_villages g
   ORDER BY g.state;
$function$;

GRANT EXECUTE ON FUNCTION app.lgd_states() TO anon, authenticated;

CREATE OR REPLACE FUNCTION app.lgd_districts(p_state text)
RETURNS TABLE(district text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT g.district::text
    FROM lgd_villages g
   WHERE g.state = btrim(p_state)
   ORDER BY g.district;
$function$;

GRANT EXECUTE ON FUNCTION app.lgd_districts(text) TO anon, authenticated;

-- The Owner asked for both: "enable user to select mandal, district".
--
-- district_options_for_village, applied an hour ago, offered only the
-- district. It is dropped rather than left beside a second function, because
-- two functions answering the same question is how they drift -- and because
-- the district options DEPEND on the mandal: change the mandal and the
-- districts the directory lists for it change with it. Asked separately they
-- would disagree the moment somebody corrected the mandal first.
--
-- DROP then CREATE, not CREATE OR REPLACE: the name, parameters and return
-- shape all change, and a second overload is how PostgREST comes to answer
-- HTTP 300 instead of choosing. Counted after applying -- one of each.
DROP FUNCTION IF EXISTS app.district_options_for_village(uuid, uuid);
DROP FUNCTION IF EXISTS app.place_options_for_village(uuid, uuid, varchar);

CREATE FUNCTION app.place_options_for_village(p_business_id uuid,
                                              p_location_id uuid,
                                              p_mandal varchar DEFAULT NULL)
RETURNS TABLE (kind text, value text, used_here int, in_directory boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_pin    varchar;
  v_name   varchar;
  v_mandal varchar;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only this business''s Owner can look at this.';
  END IF;

  SELECT pin_code, village_town_name, mandal
    INTO v_pin, v_name, v_mandal
    FROM locations WHERE location_id = p_location_id;
  IF v_name IS NULL THEN RETURN; END IF;

  -- The mandal the districts are being asked ABOUT: whatever the caller is
  -- currently showing, which may be one they have just picked and not saved.
  v_mandal := coalesce(nullif(btrim(coalesce(p_mandal, '')), ''), v_mandal);

  RETURN QUERY
  -- ---- mandals at this PIN -------------------------------------------
  WITH mine_m AS (
    SELECT l.mandal::text AS v, count(*)::int AS n
      FROM operating_area_locations o
      JOIN locations l ON l.location_id = o.location_id
     WHERE o.business_id = p_business_id
       AND o.removed_at IS NULL
       AND l.pin_code = v_pin
     GROUP BY l.mandal
  ),
  dir_m AS (
    SELECT DISTINCT g.mandal::text AS v FROM lgd_villages g WHERE g.pincode = v_pin
  ),
  -- ---- districts for the mandal in hand -------------------------------
  mine_d AS (
    SELECT l.district::text AS v, count(*)::int AS n
      FROM operating_area_locations o
      JOIN locations l ON l.location_id = o.location_id
     WHERE o.business_id = p_business_id
       AND o.removed_at IS NULL
       AND lower(l.mandal) = lower(v_mandal)
     GROUP BY l.district
  ),
  dir_d AS (
    SELECT DISTINCT g.district::text AS v
      FROM lgd_villages g
     WHERE g.pincode = v_pin AND lower(g.mandal) = lower(v_mandal)
  )
  SELECT 'mandal', coalesce(m.v, d.v), coalesce(m.n, 0), (d.v IS NOT NULL)
    FROM mine_m m FULL OUTER JOIN dir_m d ON lower(d.v) = lower(m.v)
  UNION ALL
  SELECT 'district', coalesce(m.v, d.v), coalesce(m.n, 0), (d.v IS NOT NULL)
    FROM mine_d m FULL OUTER JOIN dir_d d ON lower(d.v) = lower(m.v)
  -- Most used first, then A to Z. "new & most used on top", the Owner's
  -- ordering: a name they typed themselves for another village counts as
  -- used and rises, which is the whole suggestion mechanism -- no new table,
  -- because `locations` already records every choice anybody made.
  ORDER BY 1, 3 DESC, 2;
END $$;

GRANT EXECUTE ON FUNCTION app.place_options_for_village(uuid, uuid, varchar) TO authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'place_options_for_village';
  IF v_n <> 1 THEN RAISE EXCEPTION 'expected 1 overload, found %', v_n; END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'district_options_for_village';
  IF v_n <> 0 THEN RAISE EXCEPTION 'the superseded function is still there'; END IF;
END $$;

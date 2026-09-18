-- The merge was reading area links that had been removed.
--
-- operating_area_locations is SOFT DELETED -- it carries removed_at, and the
-- unique index that enforces "one business puts a village in one area" is
-- partial:
--
--   uq_oal_business_location ON (business_id, location_id) WHERE removed_at IS NULL
--
-- The first version of these three functions filtered none of that, which is
-- the whole reason I read the pair on this book as sitting in three different
-- areas and refused to merge them. They sit in ONE live area each, the same
-- one; the other three rows were removed months ago. The refusal was computed
-- from deleted data.
--
-- pg_constraint does not list uq_oal_business_location, because it is an index
-- and not a constraint. Reading one and not the other is how a column that
-- decides everything here stayed invisible for an afternoon.
--
-- The delete becomes a soft delete for the same reason: a hard DELETE would be
-- the only hard delete this table has ever taken, and would lose the record
-- that the village was ever worked by that area.

CREATE OR REPLACE FUNCTION app.village_merge_blocked_reason(p_business_id uuid,
                                                            p_loser_id uuid,
                                                            p_survivor_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_biz      uuid;
  v_loser    uuid[];
  v_survivor uuid[];
  v_names    text;
BEGIN
  IF p_loser_id = p_survivor_id THEN
    RETURN 'A village cannot be merged into itself.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM locations WHERE location_id = p_survivor_id
                    AND status = 'Active') THEN
    RETURN 'The village being kept is not active.';
  END IF;

  -- Every business with a member living on the losing row -- those are the
  -- books whose rounds could change -- PLUS the caller's own, which is checked
  -- whether or not anybody lives there.
  --
  -- The caller is in the list for a reason. Their losing area links are
  -- removed by the merge, so if the survivor is not in those areas, an area
  -- silently stops covering a village. Nobody's round changes today, because
  -- nobody lives there today; the next customer registered in that village
  -- would land in a different area than the Owner expects, and nothing would
  -- connect that to a merge weeks earlier.
  FOR v_biz IN
    SELECT DISTINCT bm.business_id
      FROM person_addresses pa
      JOIN business_members bm ON bm.person_id = pa.person_id
     WHERE pa.village_id = p_loser_id
       AND pa.is_current
       AND bm.membership_status = 'Active'
    UNION
    SELECT p_business_id
  LOOP
    SELECT coalesce(array_agg(DISTINCT o.operating_area_id), '{}')
      INTO v_loser
      FROM operating_area_locations o
     WHERE o.location_id = p_loser_id AND o.business_id = v_biz
       AND o.removed_at IS NULL;

    SELECT coalesce(array_agg(DISTINCT o.operating_area_id), '{}')
      INTO v_survivor
      FROM operating_area_locations o
     WHERE o.location_id = p_survivor_id AND o.business_id = v_biz
       AND o.removed_at IS NULL;

    -- Set equality, in both directions. A survivor covered by MORE areas is
    -- not the safe side of this: it widens who can see everybody already
    -- living there.
    IF NOT (v_loser <@ v_survivor AND v_survivor <@ v_loser) THEN
      IF app.is_owner(v_biz) THEN
        -- The areas that cover one and not the other -- the symmetric
        -- difference, spelled out rather than assembled from set operators,
        -- because EXCEPT and UNION bind left to right and the obvious way to
        -- write this computes something else.
        SELECT string_agg(DISTINCT oa.name, ', ' ORDER BY oa.name)
          INTO v_names
          FROM operating_areas oa
         WHERE (oa.operating_area_id = ANY (v_loser)
                AND NOT (oa.operating_area_id = ANY (v_survivor)))
            OR (oa.operating_area_id = ANY (v_survivor)
                AND NOT (oa.operating_area_id = ANY (v_loser)));
        RETURN 'These two villages are worked by different areas ('
               || coalesce(v_names, 'none')
               || '). Put both villages in the same areas first, or the '
               || 'customers here would change rounds.';
      ELSE
        RETURN 'A customer living here also belongs to another business, '
               || 'where these two villages are worked by different areas. '
               || 'They cannot be merged from here.';
      END IF;
    END IF;
  END LOOP;

  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION app.duplicate_village_candidates(p_business_id uuid)
RETURNS TABLE (
  keep_location_id   uuid,
  keep_name          text,
  keep_mandal        text,
  keep_district      text,
  keep_source        text,
  keep_people        int,
  drop_location_id   uuid,
  drop_name          text,
  drop_mandal        text,
  drop_district      text,
  drop_source        text,
  drop_people        int,
  pin_code           text,
  score              real,
  blocked_reason     text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app, extensions
AS $$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only this business''s Owner can look for duplicate villages.';
  END IF;

  RETURN QUERY
  WITH used AS (
    SELECT l.*
      FROM locations l
     WHERE l.status = 'Active'
       AND (EXISTS (SELECT 1 FROM operating_area_locations o
                     WHERE o.location_id = l.location_id
                       AND o.business_id = p_business_id
                       AND o.removed_at IS NULL)
        OR  EXISTS (SELECT 1 FROM person_addresses pa
                      JOIN business_members bm ON bm.person_id = pa.person_id
                     WHERE pa.village_id = l.location_id
                       AND pa.is_current
                       AND bm.business_id = p_business_id
                       AND bm.membership_status = 'Active'))
  ),
  counted AS (
    SELECT u.*,
           (SELECT count(*) FROM person_addresses pa
             WHERE pa.village_id = u.location_id AND pa.is_current)::int AS people
      FROM used u
  ),
  pairs AS (
    SELECT a.location_id a_id, b.location_id b_id,
           a.people a_people, b.people b_people,
           a.pin_code::text AS pin,
           extensions.similarity(lower(a.village_town_name),
                                 lower(b.village_town_name)) AS sim
      FROM counted a
      JOIN counted b
        ON a.location_id < b.location_id
       AND (a.pin_code = b.pin_code
            OR (lower(a.mandal) = lower(b.mandal)
                AND lower(a.district) = lower(b.district)))
     WHERE extensions.similarity(lower(a.village_town_name),
                                 lower(b.village_town_name)) >= 0.35
  ),
  directed AS (
    SELECT CASE WHEN p.a_people > p.b_people THEN p.a_id
                WHEN p.b_people > p.a_people THEN p.b_id
                WHEN (SELECT c.source FROM counted c WHERE c.location_id = p.a_id) = 'Directory'
                     THEN p.a_id ELSE p.b_id END AS keep_id,
           CASE WHEN p.a_people > p.b_people THEN p.b_id
                WHEN p.b_people > p.a_people THEN p.a_id
                WHEN (SELECT c.source FROM counted c WHERE c.location_id = p.a_id) = 'Directory'
                     THEN p.b_id ELSE p.a_id END AS drop_id,
           p.pin, p.sim
      FROM pairs p
  )
  SELECT k.location_id, k.village_town_name::text, k.mandal::text,
         k.district::text, k.source::text, k.people,
         d.location_id, d.village_town_name::text, d.mandal::text,
         d.district::text, d.source::text, d.people,
         x.pin, x.sim,
         app.village_merge_blocked_reason(p_business_id, d.location_id,
                                          k.location_id)
    FROM directed x
    JOIN counted k ON k.location_id = x.keep_id
    JOIN counted d ON d.location_id = x.drop_id
   ORDER BY x.sim DESC;
END $$;

CREATE OR REPLACE FUNCTION app.merge_villages(p_business_id uuid, p_loser_id uuid,
                                              p_survivor_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_reason  text;
  v_people  int := 0;
  v_areas   int := 0;
  v_routes  int := 0;
  v_dropped text;
  v_kept    text;
  v_left    int;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only this business''s Owner can merge villages.';
  END IF;

  SELECT village_town_name INTO v_dropped FROM locations WHERE location_id = p_loser_id;
  SELECT village_town_name INTO v_kept    FROM locations WHERE location_id = p_survivor_id;
  IF v_dropped IS NULL OR v_kept IS NULL THEN
    RAISE EXCEPTION 'One of these villages no longer exists.';
  END IF;

  v_reason := app.village_merge_blocked_reason(p_business_id, p_loser_id,
                                              p_survivor_id);
  IF v_reason IS NOT NULL THEN
    RAISE EXCEPTION '%', v_reason;
  END IF;

  -- ADDRESSES MOVE, ALL OF THEM, current and past alike. A historical address
  -- left pointing at a deactivated row would be a row nothing can resolve to a
  -- name; the person lived in this village under either spelling.
  UPDATE person_addresses SET village_id = p_survivor_id
   WHERE village_id = p_loser_id;
  GET DIAGNOSTICS v_people = ROW_COUNT;

  -- This business's live area links. The sets are equal or we would not be
  -- here, so every losing link duplicates one the survivor already has.
  --
  -- SOFT DELETED, like every other removal from this table. The partial unique
  -- index is what makes that work: a removed row does not block the survivor's
  -- live one.
  UPDATE operating_area_locations o
     SET removed_at = now()
   WHERE o.location_id = p_loser_id AND o.business_id = p_business_id
     AND o.removed_at IS NULL;
  GET DIAGNOSTICS v_areas = ROW_COUNT;

  -- Routes are walking order, not permission: nothing is derived from them, so
  -- a losing link is repointed unless the route already has the survivor, in
  -- which case it is dropped so the village is not visited twice. This table
  -- has no removed_at, so a delete is the only removal it has.
  DELETE FROM route_locations r
   WHERE r.location_id = p_loser_id
     AND EXISTS (SELECT 1 FROM route_locations r2
                  WHERE r2.route_id = r.route_id
                    AND r2.location_id = p_survivor_id)
     AND r.route_id IN (SELECT route_id FROM routes
                         WHERE business_id = p_business_id);

  UPDATE route_locations SET location_id = p_survivor_id
   WHERE location_id = p_loser_id
     AND route_id IN (SELECT route_id FROM routes WHERE business_id = p_business_id);
  GET DIAGNOSTICS v_routes = ROW_COUNT;

  -- DEACTIVATED ONLY WHEN NOBODY IS LEFT ON IT. Another business may still
  -- work this row; `locations` is shared and this Owner does not get to
  -- retire a village out from under them. A removed area link does not count
  -- as use -- it is a record that the village was dropped, not that it is
  -- worked.
  SELECT (SELECT count(*) FROM person_addresses WHERE village_id = p_loser_id)
       + (SELECT count(*) FROM operating_area_locations
           WHERE location_id = p_loser_id AND removed_at IS NULL)
       + (SELECT count(*) FROM route_locations WHERE location_id = p_loser_id)
    INTO v_left;

  IF v_left = 0 THEN
    UPDATE locations SET status = 'Inactive' WHERE location_id = p_loser_id;
  END IF;

  RETURN json_build_object(
    'kept', v_kept,
    'dropped', v_dropped,
    'addresses_moved', v_people,
    'area_links_removed', v_areas,
    'route_links_moved', v_routes,
    'still_in_use_elsewhere', v_left > 0
  );
END $$;

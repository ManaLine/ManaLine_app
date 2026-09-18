-- One village, two rows. This is how they become one row.
--
-- The Owner, 2026-09-18: "merge duplicate villages", and on what it must cost
-- them: "their loans, collections and account history follow silently - just
-- their address village name changes to the new one, remaining all stays."
--
-- THAT RULE IS ALREADY TRUE, and it is worth saying why rather than trusting
-- it. Exactly three tables reference `locations`, all by foreign key, checked
-- against pg_constraint and against every column in the schema named for a
-- village or a location:
--
--   person_addresses.village_id
--   operating_area_locations.location_id
--   route_locations.location_id
--
-- Nothing money-related is among them. Loans, collections, day_ledger,
-- account_periods and receipts do not know what a village is, so repointing
-- an address cannot move a rupee. The history follows silently because it was
-- never attached to the village in the first place.
--
-- WHAT CAN MOVE IS WHO COLLECTS. app.agent_covers_customer derives an agent's
-- reach like this:
--
--   customers -> person_addresses.village_id -> operating_area_locations
--             -> operating_areas -> agent_area_assignments -> agents
--
-- So a customer's village decides which agent may see them, and which area's
-- account period their collections land in. If the two rows sit in different
-- areas, merging them moves people between rounds -- quietly, and for a
-- reason nobody would connect to a village merge a week later.
--
-- HENCE THE ONE REFUSAL. For every business that has a member living on the
-- losing row, that business's set of areas covering the loser must be exactly
-- the set covering the survivor. Equal, not merely overlapping: a survivor in
-- MORE areas widens coverage for everybody already on it, and
-- "widening a filter changes everything downstream of it" is written in
-- CLAUDE.md because this project has shipped that bug.
--
-- The check runs for OTHER businesses too, and tells the caller nothing about
-- them beyond the fact that it cannot proceed. A person has one address, so
-- moving them moves them for every book they are in; an Owner may decide that
-- for their own business and may not decide it for somebody else's.
--
-- THE LOSING ROW IS DEACTIVATED, NEVER DELETED. `locations` is a shared
-- directory with no business_id -- five businesses read the same rows -- and a
-- DELETE would be irreversible on a table this app does not own. Inactive is
-- enough: suggest_similar_villages and the village search both filter on
-- Active, so a deactivated duplicate stops being offered and stops being
-- typed in again, which is the whole point.

-- ---------------------------------------------------------------------------
-- Why a merge cannot happen, or NULL when it can.
-- ---------------------------------------------------------------------------
-- Split out because two callers need the same answer and they must never
-- disagree: the list has to say "this one is blocked" before the Owner picks
-- it, and the merge has to refuse for the same reason when they do.
--
-- It names the caller's OWN areas, because that is a refusal the Owner can act
-- on -- add the survivor to that area, or take the loser out of it. It names
-- nothing at all about another business, because whose customer that is, and
-- what they call their rounds, is not this Owner's to see.
DROP FUNCTION IF EXISTS app.village_merge_blocked_reason(uuid, uuid, uuid);
CREATE FUNCTION app.village_merge_blocked_reason(p_business_id uuid,
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
  v_mine     boolean;
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
  -- deleted by the merge, so if the survivor is not in those areas, an area
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
     WHERE o.location_id = p_loser_id AND o.business_id = v_biz;

    SELECT coalesce(array_agg(DISTINCT o.operating_area_id), '{}')
      INTO v_survivor
      FROM operating_area_locations o
     WHERE o.location_id = p_survivor_id AND o.business_id = v_biz;

    -- Set equality, in both directions. A survivor covered by MORE areas is
    -- not the safe side of this: it widens who can see everybody already
    -- living there.
    IF NOT (v_loser <@ v_survivor AND v_survivor <@ v_loser) THEN
      v_mine := app.is_owner(v_biz);
      IF v_mine THEN
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

-- ---------------------------------------------------------------------------
-- Which pairs look like the same place.
-- ---------------------------------------------------------------------------
-- Suggestions only. The merge itself takes whatever two rows it is given, and
-- deliberately does not require them to appear here: a village known by two
-- unrelated names is exactly the case trigram similarity cannot find, and the
-- Owner standing in it can.
--
-- THE THRESHOLD IS MEASURED, NOT PICKED. On this book the one real duplicate,
-- 'Panagal' against 'Panagallu (Rural)', scores 0.500. The next-highest pair
-- among villages that merely share a PIN scores 0.042, and the rest score
-- zero. Sharing a PIN is not sameness -- 517640 covers Uranduru, Srikalahasti
-- and Panagallu, three different places -- so the PIN only narrows the
-- candidates and the name does the deciding.
DROP FUNCTION IF EXISTS app.duplicate_village_candidates(uuid);
CREATE FUNCTION app.duplicate_village_candidates(p_business_id uuid)
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
    -- The villages this business actually works: attached to one of its areas,
    -- or lived in by one of its members. A duplicate the Owner has never
    -- touched is not their problem to resolve.
    SELECT l.*
      FROM locations l
     WHERE l.status = 'Active'
       AND (EXISTS (SELECT 1 FROM operating_area_locations o
                     WHERE o.location_id = l.location_id
                       AND o.business_id = p_business_id)
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
  -- THE SURVIVOR IS SUGGESTED, NOT IMPOSED: the row more people already live
  -- on, because that is the smaller move and the fewer addresses rewritten.
  -- A tie goes to the Directory row, whose mandal and district came from the
  -- LGD reference rather than from somebody typing at a doorstep.
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

-- ---------------------------------------------------------------------------
-- The merge.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.merge_villages(uuid, uuid, uuid);
CREATE FUNCTION app.merge_villages(p_business_id uuid, p_loser_id uuid,
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

  -- The same answer the list showed, asked again at the moment it matters: an
  -- area can be added to a village between the Owner reading the list and
  -- tapping Merge.
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

  -- This business's area links. The sets are equal or we would not be here, so
  -- every losing link is a duplicate of one the survivor already has, and the
  -- de-duplication is a delete rather than a repoint.
  DELETE FROM operating_area_locations o
   WHERE o.location_id = p_loser_id AND o.business_id = p_business_id;
  GET DIAGNOSTICS v_areas = ROW_COUNT;

  -- Routes are walking order, not permission: nothing is derived from them, so
  -- a losing link is repointed unless the route already has the survivor, in
  -- which case it is dropped so the village is not visited twice.
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
  -- retire a village out from under them.
  SELECT (SELECT count(*) FROM person_addresses WHERE village_id = p_loser_id)
       + (SELECT count(*) FROM operating_area_locations WHERE location_id = p_loser_id)
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

GRANT EXECUTE ON FUNCTION app.duplicate_village_candidates(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app.village_merge_blocked_reason(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app.merge_villages(uuid, uuid, uuid) TO authenticated;

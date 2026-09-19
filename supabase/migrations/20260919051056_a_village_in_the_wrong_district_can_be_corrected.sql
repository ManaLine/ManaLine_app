-- A village stored under the wrong district had no way back.
--
-- The Owner, item 11: "which is correct if app fills it wrong or old data &
-- one user selects a new mandal or district instead of old app creates it's &
-- suggest the same in next user search".
--
-- Asking at pick time stops NEW villages being stamped with the pre-2022
-- district. It does nothing for the ones already stored, and on this book that
-- is every village in Srikalahasti mandal.
--
-- WHY THIS IS SAFE TO EDIT AND A MERGE IS NOT. Both touch `locations`, which
-- is shared by all five books and has no business_id. But a merge REPOINTS
-- people -- it moves addresses, and coverage is derived from an address. A
-- district is a LABEL. Checked rather than assumed, against the whole schema:
--
--   functions reading locations.district or .mandal   1  (suggest_similar_villages, display only)
--   views referencing them                            0
--   indexes on them                                   0
--   foreign keys on them                              0
--
-- uq_locations_pin_village_lower is on (pin_code, lower(village_town_name)) --
-- the district is not part of village identity, so correcting it cannot make a
-- duplicate, cannot break a join, and cannot move a rupee. It is the name of a
-- place being written correctly.
--
-- ONLY A VILLAGE THIS BOOK ACTUALLY WORKS. An Owner may fix the district of a
-- village they operate in; they may not reach into one only somebody else
-- uses. That is the narrowest rule that still lets the correction happen, and
-- it means a village nobody works cannot be edited by anybody -- which is
-- correct, because nobody is looking at it.
--
-- THE STATE IS NOT EDITABLE. No state in India has split in the lifetime of
-- this data, a wrong state is a different defect (one village had one, fixed
-- in 20260901060331), and leaving it out keeps this to the question actually
-- being asked.
DROP FUNCTION IF EXISTS app.correct_location_place(uuid, uuid, varchar, varchar);
CREATE FUNCTION app.correct_location_place(p_business_id uuid,
                                           p_location_id uuid,
                                           p_mandal varchar,
                                           p_district varchar)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_old_mandal   varchar;
  v_old_district varchar;
  v_name         varchar;
  v_used         boolean;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only this business''s Owner can correct a village.';
  END IF;

  SELECT village_town_name, mandal, district
    INTO v_name, v_old_mandal, v_old_district
    FROM locations WHERE location_id = p_location_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'That village no longer exists.';
  END IF;

  -- Worked by this book: attached to one of its live areas, or lived in by
  -- one of its members.
  SELECT EXISTS (SELECT 1 FROM operating_area_locations o
                  WHERE o.location_id = p_location_id
                    AND o.business_id = p_business_id
                    AND o.removed_at IS NULL)
      OR EXISTS (SELECT 1 FROM person_addresses pa
                   JOIN business_members bm ON bm.person_id = pa.person_id
                  WHERE pa.village_id = p_location_id
                    AND pa.is_current
                    AND bm.business_id = p_business_id
                    AND bm.membership_status = 'Active')
    INTO v_used;

  IF NOT v_used THEN
    RAISE EXCEPTION 'This village is not worked by this business, so it '
                    'cannot be corrected from here.';
  END IF;

  IF coalesce(btrim(p_mandal), '') = '' OR coalesce(btrim(p_district), '') = '' THEN
    RAISE EXCEPTION 'A mandal and a district are both required.';
  END IF;

  UPDATE locations
     SET mandal   = btrim(p_mandal),
         district = btrim(p_district)
   WHERE location_id = p_location_id;

  RETURN json_build_object(
    'village', v_name,
    'was_mandal', v_old_mandal,
    'was_district', v_old_district,
    'now_mandal', btrim(p_mandal),
    'now_district', btrim(p_district)
  );
END $$;

-- What to offer, and in what order.
--
-- "new & most used on top" is the Owner's ordering. Three sources, in this
-- order of authority:
--
--   1. what this book already uses for that mandal  -- their own answer, and
--      the one that keeps a book internally consistent
--   2. what the directory lists for that village    -- the legal options,
--      including the post-split name they are probably looking for
--   3. anything else the directory has for the mandal
--
-- A district the Owner has typed themselves for another village lands in (1)
-- on the next village, which is the "app creates it's & suggest the same in
-- next user search" half of the request -- no new table, because `locations`
-- already records every choice anybody made.
DROP FUNCTION IF EXISTS app.district_options_for_village(uuid, uuid);
CREATE FUNCTION app.district_options_for_village(p_business_id uuid,
                                                 p_location_id uuid)
RETURNS TABLE (district text, used_here int, in_directory boolean)
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

  RETURN QUERY
  WITH mine AS (
    SELECT l.district::text AS d, count(*)::int AS n
      FROM operating_area_locations o
      JOIN locations l ON l.location_id = o.location_id
     WHERE o.business_id = p_business_id
       AND o.removed_at IS NULL
       AND lower(l.mandal) = lower(v_mandal)
     GROUP BY l.district
  ),
  directory AS (
    SELECT DISTINCT g.district::text AS d
      FROM lgd_villages g
     WHERE g.pincode = v_pin
       AND (lower(g.village) = lower(v_name) OR lower(g.mandal) = lower(v_mandal))
  )
  SELECT coalesce(m.d, x.d),
         coalesce(m.n, 0),
         (x.d IS NOT NULL)
    FROM mine m
    FULL OUTER JOIN directory x ON lower(x.d) = lower(m.d)
   ORDER BY coalesce(m.n, 0) DESC, coalesce(m.d, x.d);
END $$;

GRANT EXECUTE ON FUNCTION app.correct_location_place(uuid, uuid, varchar, varchar) TO authenticated;
GRANT EXECUTE ON FUNCTION app.district_options_for_village(uuid, uuid) TO authenticated;

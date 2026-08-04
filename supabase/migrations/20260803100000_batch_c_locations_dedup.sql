-- =============================================================================
-- BATCH C (2/3) — locations: dedup + unique index + race-safe insert (#16)
-- =============================================================================
-- WHAT THIS FILE DOES:
--   (1) Consolidates any duplicate location rows that share the same
--       pin_code and village name (case-insensitive). The duplicate
--       diagnostic script already exists at supabase/cleanup_test_data.sql;
--       this migration automates it so every deploy produces a consistent
--       table. Person addresses, operating_area_locations, and route_locations
--       that pointed at a removed duplicate are re-pointed to the survivor.
--
--   (2) Adds a PARTIAL UNIQUE INDEX that prevents future duplicates.
--
--   (3) Makes add_location_if_missing race-safe: when two concurrent
--       registrations try to add the same missing village, the second
--       call sees the first via ON CONFLICT (not a plain SELECT-then-INSERT
--       race), and returns the survivor's id. The unique index from (2)
--       is what makes ON CONFLICT work.
--
--   Folding into the #13 rate-limit buckets happens in Batch D.
-- -----------------------------------------------------------------------------

-- 1. Consolidate duplicates: for each (pin_code, village) group with
--    more than one row, keep the oldest (lowest created_at / id) and
--    re-point all FK consumers to it before removing the extras.
DO $$
DECLARE r RECORD; v_keep UUID; v_drop UUID;
BEGIN
  FOR r IN
    -- Ordered by location_id, not created_at: `locations` has no timestamp
    -- column. Any deterministic order works — we only need a stable survivor.
    SELECT pin_code, lower(village_town_name) AS village_key,
           array_agg(location_id ORDER BY location_id) AS ids
    FROM locations
    GROUP BY pin_code, lower(village_town_name)
    HAVING count(*) > 1
  LOOP
    v_keep := r.ids[1];
    FOR i IN 2 .. array_length(r.ids, 1) LOOP
      v_drop := r.ids[i];
      -- Re-point all foreign-key consumers of this location before removal.
      UPDATE person_addresses     SET village_id = v_keep WHERE village_id = v_drop;
      UPDATE operating_area_locations SET location_id = v_keep WHERE location_id = v_drop;
      UPDATE route_locations      SET location_id = v_keep WHERE location_id = v_drop;
      DELETE FROM locations WHERE location_id = v_drop;
    END LOOP;
  END LOOP;
END;
$$;

-- 2. Unique index: one pin_code + village name per table (case-insensitive).
--    Expression indexes with lower() are IMMUTABLE in the default collation,
--    which is what the database uses. Fails safely on any leftover duplicates
--    the dedup block above might not have caught (a data-integrity signal,
--    not a silent bypass).
CREATE UNIQUE INDEX uq_locations_pin_village_lower
  ON locations (pin_code, lower(village_town_name));

-- 3. make add_location_if_missing race-safe:
--    ON CONFLICT DO NOTHING means the second concurrent caller simply gets
--    back the survivor inserted by the first (via the existing SELECT-after-
--    conflict path in the function body).
--    NOTE: the unique index above must exist for ON CONFLICT to bind.
CREATE OR REPLACE FUNCTION app.add_location_if_missing(
  p_pin_code          VARCHAR(6),
  p_village_town_name VARCHAR(150),
  p_area_type         location_area_type_enum,
  p_mandal            VARCHAR(100),
  p_district          VARCHAR(100),
  p_state             VARCHAR(100)
)
RETURNS TABLE (location_id UUID, was_existing BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id UUID;
  v_new_id UUID;
BEGIN
  IF p_pin_code IS NULL OR length(trim(p_pin_code)) != 6 THEN
    RAISE EXCEPTION 'pin_code must be exactly 6 digits';
  END IF;
  IF trim(coalesce(p_village_town_name, '')) = '' THEN
    RAISE EXCEPTION 'village_town_name is required';
  END IF;
  IF trim(coalesce(p_mandal, '')) = '' OR trim(coalesce(p_district, '')) = ''
     OR trim(coalesce(p_state, '')) = '' THEN
    RAISE EXCEPTION 'mandal, district, and state are all required';
  END IF;

  -- Fast path: check if it already exists.
  SELECT l.location_id INTO v_existing_id
  FROM locations l
  WHERE l.pin_code = trim(p_pin_code)
    AND lower(l.village_town_name) = lower(trim(p_village_town_name))
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_id, true;
    RETURN;
  END IF;

  -- The unique index uq_locations_pin_village_lower prevents duplicates.
  -- If a concurrent caller raced past the SELECT above and inserted the
  -- same village first, the INSERT conflicts and DO NOTHING lets us fall
  -- through to read the survivor's id.
  INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status)
  VALUES (trim(p_pin_code), trim(p_village_town_name), p_area_type,
          trim(p_mandal), trim(p_district), trim(p_state), 'Active')
  ON CONFLICT (pin_code, lower(village_town_name)) DO NOTHING
  RETURNING locations.location_id INTO v_new_id;

  -- RETURNING yields a row only when THIS statement inserted one, so it is
  -- the direct answer to "did we create it?" — no timestamp comparison
  -- needed (and `locations` carries no created_at to compare against).
  IF v_new_id IS NOT NULL THEN
    RETURN QUERY SELECT v_new_id, false;
    RETURN;
  END IF;

  -- DO NOTHING fired: a concurrent caller inserted it between our fast-path
  -- SELECT and this INSERT. Hand back their row.
  RETURN QUERY
    SELECT l.location_id, true
    FROM locations l
    WHERE l.pin_code = trim(p_pin_code)
      AND lower(l.village_town_name) = lower(trim(p_village_town_name))
    LIMIT 1;
END;
$$;

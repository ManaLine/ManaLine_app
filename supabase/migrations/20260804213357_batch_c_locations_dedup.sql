DO $$
DECLARE r RECORD; v_keep UUID; v_drop UUID;
BEGIN
  FOR r IN
    SELECT pin_code, lower(village_town_name) AS village_key,
           array_agg(location_id ORDER BY location_id) AS ids
    FROM locations
    GROUP BY pin_code, lower(village_town_name)
    HAVING count(*) > 1
  LOOP
    v_keep := r.ids[1];
    FOR i IN 2 .. array_length(r.ids, 1) LOOP
      v_drop := r.ids[i];
      UPDATE person_addresses     SET village_id = v_keep WHERE village_id = v_drop;
      UPDATE operating_area_locations SET location_id = v_keep WHERE location_id = v_drop;
      UPDATE route_locations      SET location_id = v_keep WHERE location_id = v_drop;
      DELETE FROM locations WHERE location_id = v_drop;
    END LOOP;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX uq_locations_pin_village_lower
  ON locations (pin_code, lower(village_town_name));

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

  SELECT l.location_id INTO v_existing_id
  FROM locations l
  WHERE l.pin_code = trim(p_pin_code)
    AND lower(l.village_town_name) = lower(trim(p_village_town_name))
  LIMIT 1;
  IF v_existing_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_id, true;
    RETURN;
  END IF;

  INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status)
  VALUES (trim(p_pin_code), trim(p_village_town_name), p_area_type,
          trim(p_mandal), trim(p_district), trim(p_state), 'Active')
  ON CONFLICT (pin_code, lower(village_town_name)) DO NOTHING
  RETURNING locations.location_id INTO v_new_id;

  IF v_new_id IS NOT NULL THEN
    RETURN QUERY SELECT v_new_id, false;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT l.location_id, true
    FROM locations l
    WHERE l.pin_code = trim(p_pin_code)
      AND lower(l.village_town_name) = lower(trim(p_village_town_name))
    LIMIT 1;
END;
$$;

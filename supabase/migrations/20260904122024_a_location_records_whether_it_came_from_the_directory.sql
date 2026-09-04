-- add_location_if_missing is called from two quite different places and could
-- not tell them apart:
--
--   materialising a REFERENCE pick   the village is in lgd_villages and
--                                    somebody chose it -> 'Directory'
--   the Add New Village form         the directory has never heard of it and
--                                    somebody typed it -> 'Owner Entered'
--
-- Both landed with the column default, so every row read as owner-entered and
-- the provenance column answered nothing. p_source distinguishes them.
--
-- DROP then CREATE, not CREATE OR REPLACE: the parameter list changes, and a
-- defaulted parameter added by REPLACE creates a SECOND overload that makes
-- PostgREST answer 300 (PGRST203). Counted after applying -- 1.
--
-- The default is 'Owner Entered' so the six existing callers keep working
-- unchanged and the safe answer is the one they get: a row wrongly marked
-- owner-entered shows up for review, a row wrongly marked Directory hides.
DROP FUNCTION IF EXISTS app.add_location_if_missing(
  character varying, character varying, location_area_type_enum,
  character varying, character varying, character varying);

CREATE FUNCTION app.add_location_if_missing(
  p_pin_code           character varying,
  p_village_town_name  character varying,
  p_area_type          location_area_type_enum,
  p_mandal             character varying,
  p_district           character varying,
  p_state              character varying,
  p_source             location_source_enum DEFAULT 'Owner Entered'
)
RETURNS TABLE(location_id uuid, was_existing boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status, source)
  VALUES (trim(p_pin_code), trim(p_village_town_name), p_area_type,
          trim(p_mandal), trim(p_district), trim(p_state), 'Active', p_source)
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
$function$;

GRANT EXECUTE ON FUNCTION app.add_location_if_missing(
  character varying, character varying, location_area_type_enum,
  character varying, character varying, character varying,
  location_source_enum) TO anon, authenticated;

-- A village the Owner has not set up yet is created, not refused.
--
-- bulk_import_identities rejected any customer whose village was not already
-- in `locations`, telling the Owner to "add it on the Areas & Villages step
-- first" -- a step that comes AFTER identities in the wizard. The order has
-- always been back to front, and the Owner has now decided villages are set up
-- before the wizard runs at all, with the identity sheet offering them as a
-- dropdown.
--
-- But a dropdown that refuses what is not on it would stop a migration over
-- the one thing the Owner is most likely to be right about: the name of a
-- village they collect in every week. So a village typed in fresh is created.
--
-- Resolved against lgd_villages first -- 768,529 rows of the official register
-- -- so a village created this way carries its real mandal, district and
-- state rather than the 'Unconfirmed' placeholder find_or_create_location
-- leaves behind when it only has a pincode to go on. A pincode and village
-- that are not in the register are still accepted, with the geography left
-- unconfirmed: the Owner knows their own round better than the register does,
-- and being absent from it is not grounds for refusing their book.
CREATE OR REPLACE FUNCTION app.find_or_create_village(
  p_pin_code varchar,
  p_village varchar
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_location_id uuid;
  v_lgd RECORD;
  v_placeholder CONSTANT varchar := 'Unconfirmed';
BEGIN
  IF p_pin_code IS NULL OR btrim(p_pin_code) = ''
     OR p_village IS NULL OR btrim(p_village) = '' THEN
    RETURN NULL;
  END IF;

  SELECT location_id INTO v_location_id
    FROM locations
   WHERE pin_code = p_pin_code
     AND lower(village_town_name) = lower(btrim(p_village));
  IF v_location_id IS NOT NULL THEN RETURN v_location_id; END IF;

  SELECT mandal, district, state INTO v_lgd
    FROM lgd_villages
   WHERE pincode = p_pin_code
     AND lower(village) = lower(btrim(p_village))
   LIMIT 1;

  INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status)
  VALUES (p_pin_code, btrim(p_village), 'Village',
          COALESCE(v_lgd.mandal, v_placeholder),
          COALESCE(v_lgd.district, v_placeholder),
          COALESCE(v_lgd.state, v_placeholder),
          'Active')
  -- Two rows of one sheet naming the same new village race each other
  -- otherwise; uq_locations_pin_village_lower would fail the whole import over
  -- a village it was about to create anyway.
  ON CONFLICT (pin_code, lower(village_town_name)) DO NOTHING
  RETURNING location_id INTO v_location_id;

  IF v_location_id IS NULL THEN
    SELECT location_id INTO v_location_id
      FROM locations
     WHERE pin_code = p_pin_code
       AND lower(village_town_name) = lower(btrim(p_village));
  END IF;

  RETURN v_location_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.find_or_create_village(varchar, varchar)
  TO authenticated, service_role;

-- Hit on the live test: "duplicate key value violates unique constraint
-- uq_oal_business_location".
--
-- That index is UNIQUE (business_id, location_id) WHERE removed_at IS NULL — a
-- village is walked by exactly one round per business, which is right. The
-- existence check here asked the WRONG question: "is this village already in
-- THIS area?" It is not, so it inserted, and collided with the row putting that
-- village in a DIFFERENT area — the areas the Owner had already created by hand
-- before running the wizard.
--
-- A village that already belongs to a round is now LEFT WHERE IT IS and
-- reported back. Moving one between rounds changes who collects it; that is an
-- operational decision for the Owner on the areas screen, not something an
-- import should do quietly because a spreadsheet column said otherwise.
CREATE OR REPLACE FUNCTION app.migration_create_areas(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_village json;
  v_index INT := 0;
  v_out json[] := '{}';
  v_kept json[] := '{}';
  v_area_id uuid;
  v_name varchar;
  v_location_id uuid;
  v_pin varchar;
  v_attached INT;
  v_existing_area uuid;
  v_existing_name varchar;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to add operating areas for this business' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    v_name := NULLIF(btrim(COALESCE(v_row ->> 'name', '')), '');
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Row %: Area name is required.', v_index USING ERRCODE = '23514';
    END IF;

    SELECT operating_area_id INTO v_area_id
      FROM operating_areas
     WHERE business_id = p_business_id AND lower(name) = lower(v_name);

    IF v_area_id IS NULL THEN
      INSERT INTO operating_areas (
        business_id, name, status, account_cycle_duration, account_cycle_unit, submission_time
      ) VALUES (
        p_business_id, v_name, 'Active',
        COALESCE((v_row ->> 'account_cycle_duration')::int, 1),
        COALESCE(NULLIF(v_row ->> 'account_cycle_unit', ''), 'Weeks')::account_cycle_unit_enum,
        COALESCE(NULLIF(v_row ->> 'submission_time', ''), '18:00')::time
      ) RETURNING operating_area_id INTO v_area_id;
    END IF;

    v_attached := 0;
    FOR v_village IN SELECT * FROM json_array_elements(COALESCE(v_row -> 'villages', '[]'::json)) LOOP
      v_pin := regexp_replace(COALESCE(v_village ->> 'pin_code', ''), '[^0-9]', '', 'g');

      SELECT location_id INTO v_location_id
        FROM locations
       WHERE pin_code = v_pin AND lower(village_town_name) = lower(btrim(COALESCE(v_village ->> 'village', '')));

      IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Row %: village "%" (PIN %) has not been added yet.',
          v_index, v_village ->> 'village', v_pin USING ERRCODE = 'P0002';
      END IF;

      -- Keyed on the business, matching the unique index. This is the fix.
      SELECT oal.operating_area_id, oa.name
        INTO v_existing_area, v_existing_name
        FROM operating_area_locations oal
        JOIN operating_areas oa ON oa.operating_area_id = oal.operating_area_id
       WHERE oal.business_id = p_business_id
         AND oal.location_id = v_location_id
         AND oal.removed_at IS NULL;

      IF v_existing_area IS NULL THEN
        INSERT INTO operating_area_locations (operating_area_id, location_id, business_id)
        VALUES (v_area_id, v_location_id, p_business_id);
        v_attached := v_attached + 1;
      ELSIF v_existing_area <> v_area_id THEN
        -- Already walked by another round. Left alone, and said so.
        v_kept := v_kept || json_build_object(
          'village', v_village ->> 'village',
          'pin_code', v_pin,
          'kept_in_area', v_existing_name,
          'not_moved_to', v_name
        );
      END IF;
    END LOOP;

    v_out := v_out || json_build_object(
      'row', v_index, 'name', v_name, 'operating_area_id', v_area_id, 'villages_attached', v_attached
    );
  END LOOP;

  RETURN json_build_object(
    'areas', array_to_json(v_out),
    'total', v_index,
    'left_in_existing_areas', array_to_json(v_kept)
  );
END;
$$;

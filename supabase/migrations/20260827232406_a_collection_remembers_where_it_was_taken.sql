-- Where the money was actually collected.
--
-- The collect sheet used to lead with "Could not check this against the saved
-- address" -- a verdict on the CUSTOMER's address, shown before an Agent had
-- done anything wrong, and usually saying only that the phone had no fix yet.
-- It answered a question nobody asked and cast doubt while doing it.
--
-- What is wanted instead is a plain record: where the Agent was standing when
-- they took the money. Coordinates are stored because they are the audit
-- value; a village NAME is stored beside them because that is the only part
-- worth putting on a screen.
--
-- Nothing here can fail a collection. The stamp happens AFTER the collection
-- exists, exactly like update_loan_gps, so a phone with no signal records the
-- money and simply has no location against it.
alter table collections add column if not exists gps_latitude   numeric(9,6);
alter table collections add column if not exists gps_longitude  numeric(9,6);
alter table collections add column if not exists gps_accuracy_m numeric(6,1);
alter table collections add column if not exists gps_captured_at timestamp;
alter table collections add column if not exists location_name  text;

comment on column collections.location_name is
  'Village resolved from the pin at write time, or NULL. Never a guess: if no '
  'pinned address is within 2km the name is left empty rather than filled with '
  'the nearest thing found.';

-- locations carries no coordinates -- only person_addresses does -- so the
-- only honest way to name a position is the nearest pinned customer address.
-- Beyond 2km that stops meaning anything, and a wrong village on a money
-- record is worse than a blank one.
create or replace function app.village_at_point(p_lat numeric, p_lng numeric)
returns text
language sql
stable
security definer
set search_path = public, app
as $$
  SELECT l.village_town_name
  FROM person_addresses pa
  JOIN locations l ON l.location_id = pa.village_id
  WHERE pa.gps_latitude IS NOT NULL
    AND p_lat IS NOT NULL
    AND ACOS(LEAST(1, GREATEST(-1,
          SIN(RADIANS(pa.gps_latitude)) * SIN(RADIANS(p_lat))
          + COS(RADIANS(pa.gps_latitude)) * COS(RADIANS(p_lat))
          * COS(RADIANS(pa.gps_longitude - p_lng))))) * 6371000 <= 2000
  ORDER BY ACOS(LEAST(1, GREATEST(-1,
          SIN(RADIANS(pa.gps_latitude)) * SIN(RADIANS(p_lat))
          + COS(RADIANS(pa.gps_latitude)) * COS(RADIANS(p_lat))
          * COS(RADIANS(pa.gps_longitude - p_lng))))) * 6371000
  LIMIT 1;
$$;

create or replace function app.update_collection_gps(
  p_collection_id uuid,
  p_lat numeric,
  p_lng numeric,
  p_accuracy_m numeric
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
DECLARE
  v_business_id UUID;
BEGIN
  SELECT l.business_id INTO v_business_id
  FROM collections c JOIN loans l ON l.loan_id = c.loan_id
  WHERE c.collection_id = p_collection_id;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No such collection' USING ERRCODE = '23503';
  END IF;

  -- Same reach as recording the collection in the first place: whoever may
  -- collect for this business may stamp where they were.
  IF NOT (app.is_owner(v_business_id)
          OR app.is_active_agent(v_business_id)) THEN
    RAISE EXCEPTION 'Not authorized to stamp this collection'
      USING ERRCODE = '42501';
  END IF;

  UPDATE collections
     SET gps_latitude   = p_lat,
         gps_longitude  = p_lng,
         gps_accuracy_m = p_accuracy_m,
         gps_captured_at = now(),
         location_name  = app.village_at_point(p_lat, p_lng)
   WHERE collection_id = p_collection_id;
END;
$$;

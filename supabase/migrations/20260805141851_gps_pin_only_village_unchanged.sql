-- P2: GPS records a pin. It does not decide which village you are in.
--
-- DECISION (option 1 of three): capture stores lat/lng and verifies the pin;
-- the agent still picks the village by hand. `locations` holds pin_code,
-- village_town_name, mandal, district and state -- and no coordinates -- so
-- there is nothing in our own data to resolve a village against. The
-- alternatives were seeding coordinates per village (wrong ones would silently
-- misfile customers, the failure mode hardest to notice) or an external
-- geocoder (cost, plus a network dependency in the middle of a flow that runs
-- in low-signal villages).
--
-- The old function implied otherwise. It returned a village name, which reads
-- as "GPS resolved your village", when all it ever did was copy village_id
-- from the previous address row.
--
-- It also had a silent no-op. It set the current address to is_current=FALSE
-- and then re-inserted by SELECTing `FROM person_addresses old WHERE
-- is_current = FALSE ... LIMIT 1`. For a customer with no prior address row
-- that SELECT matches nothing, so the INSERT wrote nothing -- and PostgREST
-- returns 200 for a statement that changed no rows, so the caller could not
-- tell. The customer would be left with NO current address at all, because the
-- UPDATE that closed the old one still committed.
--
-- Recording where an address is, is not a change of address. So this version
-- updates the current row in place: no close-and-recreate, no history churn,
-- no window in which the person has no current address, and nothing to copy
-- incorrectly.
--
-- The return type changes from text to json. Safe: nothing calls this. The
-- whole GPS surface has been live and unreferenced -- there is no geolocation
-- package in pubspec.yaml and no location permission in AndroidManifest.xml.
DROP FUNCTION IF EXISTS app.update_customer_address_from_gps(uuid, numeric, numeric, numeric);

CREATE FUNCTION app.update_customer_address_from_gps(
  p_customer_id uuid,
  p_new_lat numeric,
  p_new_lng numeric,
  p_accuracy_m numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person_id  BIGINT;
  v_business_id UUID;
  v_address_id UUID;
  v_village    TEXT;
BEGIN
  SELECT c.person_id, cb.business_id INTO v_person_id, v_business_id
  FROM customers c
  JOIN business_members cb ON cb.membership_id = c.membership_id
  WHERE c.customer_id = p_customer_id;

  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT app.own_active_agent_membership_permits(
       app.active_membership_id(v_business_id, 'Agent'),
       'can_collect_payments', v_business_id
     ) AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to update this address' USING ERRCODE = '42501';
  END IF;

  IF p_new_lat IS NULL OR p_new_lng IS NULL THEN
    RAISE EXCEPTION 'A GPS fix is required to record a pin' USING ERRCODE = '23514';
  END IF;

  UPDATE person_addresses
     SET gps_latitude    = p_new_lat,
         gps_longitude   = p_new_lng,
         gps_accuracy_m  = p_accuracy_m,
         gps_captured_at = now()
   WHERE person_id = v_person_id
     AND is_current = TRUE
  RETURNING address_id INTO v_address_id;

  -- The explicit failure the old silent no-op needed. A customer with no
  -- current address is a real condition (it happens mid-registration), and the
  -- caller has to be able to tell that apart from success.
  IF v_address_id IS NULL THEN
    RAISE EXCEPTION 'This customer has no current address to pin'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT l.village_town_name INTO v_village
    FROM person_addresses pa
    LEFT JOIN locations l ON l.location_id = pa.village_id
   WHERE pa.address_id = v_address_id;

  -- village_resolved_from_gps is always false, and it is returned rather than
  -- omitted so the UI cannot quietly start implying otherwise: the village is
  -- whatever the agent already chose.
  RETURN json_build_object(
    'address_id', v_address_id,
    'village_name', v_village,
    'village_resolved_from_gps', false,
    'accuracy_m', p_accuracy_m
  );
END;
$function$;

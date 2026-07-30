-- MANA LINE — 0038_add_location_if_missing_rpc.sql
--
-- WHY: village search (LR-004 and others) can legitimately come up empty
-- for a real village our seed data hasn't covered yet — this app can't
-- wait for a complete national dataset before letting people register.
-- The fix must NOT be "let the user type free-text address" (that
-- breaks the standing convention: address-write paths must always
-- derive mandal/district/state from a real `locations` row, never free
-- text). Instead: let the person ADD the missing village as a real,
-- permanent `locations` row on the spot, then use it exactly like any
-- normal search result — same FK, same UUID, benefits every future
-- person who searches that same village afterward.
--
-- `locations` has no client INSERT policy at all (0013_rls_module1_tenancy.sql
-- only ever granted SELECT) — this SECURITY DEFINER RPC is the bootstrap
-- path, same pattern as 0034_create_business_with_owner_rpc.sql.
-- Callable by anon too (registration happens pre-login), unlike most
-- other RPCs in this app which require an authenticated session.

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
  v_new_id      UUID;
BEGIN
  IF p_pin_code IS NULL OR length(trim(p_pin_code)) != 6 THEN
    RAISE EXCEPTION 'pin_code must be exactly 6 digits';
  END IF;
  IF trim(coalesce(p_village_town_name, '')) = '' THEN
    RAISE EXCEPTION 'village_town_name is required';
  END IF;
  IF trim(coalesce(p_mandal, '')) = '' OR trim(coalesce(p_district, '')) = '' OR trim(coalesce(p_state, '')) = '' THEN
    RAISE EXCEPTION 'mandal, district, and state are all required';
  END IF;

  -- Dedup: if this exact pin_code + village_town_name already exists
  -- (case-insensitive), return the existing row instead of creating a
  -- near-duplicate — protects the master table's integrity even though
  -- this endpoint is open to anon callers.
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
  VALUES (trim(p_pin_code), trim(p_village_town_name), p_area_type, trim(p_mandal), trim(p_district), trim(p_state), 'Active')
  RETURNING locations.location_id INTO v_new_id;

  RETURN QUERY SELECT v_new_id, false;
END;
$$;

-- Grant to anon too — registration (LR-004) needs this before any login
-- exists, same reasoning as 0033's locations_public_select.
GRANT EXECUTE ON FUNCTION app.add_location_if_missing TO anon, authenticated;

COMMENT ON FUNCTION app.add_location_if_missing IS
  'Bootstrap insert for a village missing from locations, used by the "Add (if not found)" flow on address entry screens. Dedupes on pin_code+village_town_name (case-insensitive) before inserting. Callable by anon since registration happens pre-login.';

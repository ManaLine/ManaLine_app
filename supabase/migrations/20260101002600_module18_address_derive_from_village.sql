-- =============================================================================
-- 0027 — Module 18: Address RPCs — Derive mandal/district/state From Village
-- =============================================================================
-- Fixes a real design mismatch found while extending AG-004's address
-- support: person_addresses' own table comment says "mandal/district/state
-- auto-derived from village" (0001), but owner_update_customer_address
-- (0021) and agent_update_customer_address (0026) both accepted these as
-- free-text params instead of deriving them from locations via village_id.
-- Fixed here: both RPCs now take ONLY p_village_id for location — mandal/
-- district/state are looked up from locations, not accepted as input at
-- all, so a caller can no longer pass a village_id that disagrees with its
-- own mandal/district/state.
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS app.owner_update_customer_address(BIGINT, VARCHAR, VARCHAR, UUID, VARCHAR, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION app.owner_update_customer_address(
  p_person_id BIGINT, p_door_no VARCHAR, p_pin_code VARCHAR, p_village_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_mandal VARCHAR(100);
  v_district VARCHAR(100);
  v_state VARCHAR(100);
BEGIN
  IF NOT app.shares_active_business(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  SELECT mandal, district, state INTO v_mandal, v_district, v_state
  FROM locations WHERE location_id = p_village_id AND status = 'Active';
  IF v_mandal IS NULL THEN
    RAISE EXCEPTION 'Village not found or not Active' USING ERRCODE = 'P0002';
  END IF;

  UPDATE person_addresses SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = p_person_id AND is_current = TRUE;

  INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
  VALUES (p_person_id, COALESCE(p_door_no, '-'), COALESCE(p_pin_code, '000000'), p_village_id,
          v_mandal, v_district, v_state, CURRENT_DATE, TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_update_customer_address(BIGINT, VARCHAR, VARCHAR, UUID) TO authenticated;

DROP FUNCTION IF EXISTS app.agent_update_customer_address(UUID, VARCHAR, VARCHAR, UUID, VARCHAR, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION app.agent_update_customer_address(
  p_customer_id UUID, p_door_no VARCHAR, p_pin_code VARCHAR, p_village_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
  v_mandal VARCHAR(100);
  v_district VARCHAR(100);
  v_state VARCHAR(100);
BEGIN
  IF NOT app.agent_covers_customer(p_customer_id) THEN
    RAISE EXCEPTION 'Not authorized for this customer' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM customers c
    JOIN business_members bm ON bm.membership_id = c.assigned_agent_membership_id
    JOIN agent_permissions ap ON ap.permission_profile_id = bm.permission_profile_id
    WHERE c.customer_id = p_customer_id AND bm.person_id = app.current_person_id()
      AND ap.can_edit_customer_contact = TRUE
  ) THEN
    RAISE EXCEPTION 'Agent lacks can_edit_customer_contact permission' USING ERRCODE = '42501';
  END IF;

  SELECT person_id INTO v_person_id FROM customers WHERE customer_id = p_customer_id;

  SELECT mandal, district, state INTO v_mandal, v_district, v_state
  FROM locations WHERE location_id = p_village_id AND status = 'Active';
  IF v_mandal IS NULL THEN
    RAISE EXCEPTION 'Village not found or not Active' USING ERRCODE = 'P0002';
  END IF;

  UPDATE person_addresses SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = v_person_id AND is_current = TRUE;

  INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
  VALUES (v_person_id, COALESCE(p_door_no, '-'), COALESCE(p_pin_code, '000000'), p_village_id,
          v_mandal, v_district, v_state, CURRENT_DATE, TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION app.agent_update_customer_address(UUID, VARCHAR, VARCHAR, UUID) TO authenticated;

-- NOTE: investor_profile_state.dart / customer_profile_state.dart's
-- updatePhone/updateAddress (0019) write person_addresses DIRECTLY
-- (self-edit, not Owner/Agent-edits-another-person) and were NOT audited
-- for this same mandal/district/state-as-free-text issue in this pass —
-- flagged as a follow-up check, not fixed here (out of today's scope,
-- which was specifically the AG-004 extension).

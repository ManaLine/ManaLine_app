-- =============================================================================
-- 0026 — Module 17: Agent Update Customer Phone/Address RPCs
-- =============================================================================
-- Fixes a real bug found while extending AG-004's contact-info edit to
-- support address: agent_customer_state.dart's updateContactInfo writes
-- directly (client-side) to person_phone_history and persons for the
-- CUSTOMER's person_id — but RLS on both tables (0012/0019) only grants
-- self-write (person_phone_history_self_all, persons_self_update) plus
-- business-partner SELECT. There is no business-partner WRITE policy on
-- either table. This means the Agent's existing phone-update path, despite
-- being reported as "wired," would fail at the RLS layer on every real
-- call — same root cause as the Owner version fixed in 0021
-- (owner_update_customer_phone/address), just not caught until now because
-- nobody had run it against live RLS yet.
--
-- Fixed the same way as the Owner case: SECURITY DEFINER RPCs, gated on
-- app.agent_covers_customer() + the real can_edit_customer_contact
-- permission column (confirmed to exist, 0005) rather than app.is_owner().
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.agent_update_customer_phone(p_customer_id UUID, p_phone_number VARCHAR(15))
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
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

  UPDATE person_phone_history SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = v_person_id AND is_current = TRUE;

  INSERT INTO person_phone_history (person_id, phone_number, from_date, is_current, reason)
  VALUES (v_person_id, p_phone_number, CURRENT_DATE, TRUE, 'Updated by Agent');

  UPDATE persons SET mobile_number = p_phone_number WHERE person_id = v_person_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.agent_update_customer_phone(UUID, VARCHAR) TO authenticated;

CREATE OR REPLACE FUNCTION app.agent_update_customer_address(
  p_customer_id UUID, p_door_no VARCHAR, p_pin_code VARCHAR, p_village_id UUID,
  p_mandal VARCHAR, p_district VARCHAR, p_state VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
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

  UPDATE person_addresses SET to_date = CURRENT_DATE, is_current = FALSE
  WHERE person_id = v_person_id AND is_current = TRUE;

  INSERT INTO person_addresses (person_id, door_no, pin_code, village_id, mandal, district, state, from_date, is_current)
  VALUES (v_person_id, COALESCE(p_door_no, '-'), COALESCE(p_pin_code, '000000'), p_village_id,
          COALESCE(p_mandal, '-'), COALESCE(p_district, '-'), COALESCE(p_state, '-'), CURRENT_DATE, TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION app.agent_update_customer_address(UUID, VARCHAR, VARCHAR, UUID, VARCHAR, VARCHAR, VARCHAR) TO authenticated;

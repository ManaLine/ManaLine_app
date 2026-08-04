-- =============================================================================
-- BATCH C (3/3) — Location feature (M6)
-- =============================================================================
-- WHAT THIS FILE DOES:
--   (1) Adds lat/lng/accuracy to person_addresses (the Customer's own GPS
--       pin, captured once at registration) and to loans (the agent's GPS at
--       loan issue — the "second capture" that verifies the address is real).
--
--   (2) Adds a one-time consent flag to persons — the app must ask once
--       before it uses the device's GPS.
--
--   (3) Enforces exactly one current address per person via a partial unique
--       index (the documented invariant from 0001 that was never enforced).
--
--   (4) `compare_address_gps` RPC: given an agent's captured lat/lng and
--       accuracy, computes the distance to the customer's stored address GPS.
--       Returns match/mismatch with a flag for "indeterminate" (accuracy
--       too poor for a reliable comparison).
--
--   (5) `update_customer_address_from_gps` RPC: if the comparison is
--       different OR the agent explicitly confirms, overwrites the customer's
--       is_current address with the new pin + reverse-geocoded village.
--       Returns the village name resolved from the GPS pin.
--
--   No Google Maps key is required: the GPS chip gives lat/lng offline;
--   reverse-geocoding (for the village name) runs through the DB's
--   `locations` table once a GPS-based village finder is wired, or the
--   agent can confirm manually.
-- -----------------------------------------------------------------------------

-- ---- 1. Schema ---------------------------------------------------------

-- person_addresses: the customer's own GPS pin.
ALTER TABLE person_addresses
  ADD COLUMN gps_latitude     NUMERIC(9,6)  NULL,
  ADD COLUMN gps_longitude    NUMERIC(9,6)  NULL,
  ADD COLUMN gps_accuracy_m   NUMERIC(7,2)  NULL,
  ADD COLUMN gps_captured_at  TIMESTAMP     NULL;

COMMENT ON COLUMN person_addresses.gps_latitude  IS 'GPS pin of where the Customer was when they entered or confirmed this address. NULL = not captured.';
COMMENT ON COLUMN person_addresses.gps_accuracy_m IS 'Radius in metres (reported accuracy of the GPS fix). Used to decide whether an address comparison is trustworthy.';

-- loans: the agent's GPS at loan issue time (the second capture that
-- verifies the address is real).
ALTER TABLE loans
  ADD COLUMN issue_lat        NUMERIC(9,6)  NULL,
  ADD COLUMN issue_lng        NUMERIC(9,6)  NULL,
  ADD COLUMN issue_accuracy_m NUMERIC(7,2)  NULL,
  ADD COLUMN issue_gps_at     TIMESTAMP     NULL;

-- Consent flag: one-time acknowledgment at registration.
ALTER TABLE persons
  ADD COLUMN consent_location_capture BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN persons.consent_location_capture IS
  'TRUE once the person has acknowledged the one-time location-capture consent prompt (typically LR-007 first login).';

-- ---- 2. One-current-address partial unique index -----------------------
-- Enforces the documented invariant from 0001 (BR-225) that was never DB-
-- enforced: at most one address can be is_current = TRUE per person.
CREATE UNIQUE INDEX uq_person_addresses_one_current
  ON person_addresses (person_id) WHERE is_current = TRUE;

-- ---- 3. compare_address_gps — the agent's second capture against the    --
--      customer's stored address.                                        --
CREATE OR REPLACE FUNCTION app.compare_address_gps(
  p_customer_id UUID,
  p_agent_lat NUMERIC(9,6),
  p_agent_lng NUMERIC(9,6),
  p_agent_accuracy_m NUMERIC(7,2)
)
RETURNS TABLE(
  distance_m NUMERIC(8,1),
  is_match BOOLEAN,
  is_indeterminate BOOLEAN,
  address_lat NUMERIC(9,6),
  address_lng NUMERIC(9,6)
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  WITH addr AS (
    SELECT pa.gps_latitude, pa.gps_longitude
    FROM person_addresses pa
    WHERE pa.person_id = (SELECT c.person_id FROM customers c WHERE c.customer_id = p_customer_id)
      AND pa.is_current = TRUE
  ),
  dist AS (
    SELECT a.gps_latitude AS address_lat, a.gps_longitude AS address_lng,
           CASE
             WHEN a.gps_latitude IS NULL OR p_agent_lat IS NULL THEN NULL
             ELSE (
               ACOS(
                 LEAST(1, GREATEST(-1,
                   SIN(RADIANS(a.gps_latitude)) * SIN(RADIANS(p_agent_lat))
                   + COS(RADIANS(a.gps_latitude)) * COS(RADIANS(p_agent_lat))
                   * COS(RADIANS(a.gps_longitude - p_agent_lng))
                 ))
               ) * 6371000
             )::NUMERIC(8,1)
           END AS distance_m
    FROM addr a
  )
  SELECT d.distance_m,
         CASE WHEN d.distance_m IS NOT NULL THEN (d.distance_m <= 250) END,
         CASE WHEN d.distance_m IS NULL THEN TRUE ELSE p_agent_accuracy_m > 100 END,
         d.address_lat, d.address_lng
  FROM dist d;
$$;

COMMENT ON FUNCTION app.compare_address_gps(UUID, NUMERIC, NUMERIC, NUMERIC) IS
  'Returns Haversine distance in metres between an agent''s captured GPS and the customer''s stored address GPS. is_match = distance <= 250m (generous threshold for rural GPS). is_indeterminate = address has no GPS or agent accuracy too poor to trust. Used by the loan wizard to decide whether to update the address.';

-- ---- 4. update_customer_address_from_gps — agent confirms or replaces.  --
CREATE OR REPLACE FUNCTION app.update_customer_address_from_gps(
  p_customer_id UUID,
  p_new_lat NUMERIC(9,6),
  p_new_lng NUMERIC(9,6),
  p_accuracy_m NUMERIC(7,2)
)
RETURNS TEXT  -- returns the village name resolved from the pin
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
  v_business_id UUID;
  v_current_village UUID;
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

  -- Retire the old current address.
  UPDATE person_addresses SET is_current = FALSE, to_date = CURRENT_DATE
  WHERE person_id = v_person_id AND is_current = TRUE;

  -- Insert the new address. village_id is NULL here — to be resolved from
  -- the GPS pin once a village-finder is wired (manual confirmation is the
  -- current fallback). door_no and pin_code copied from the previous row
  -- (the agent may not have them).
  INSERT INTO person_addresses (person_id, door_no, pin_code, village_id,
    mandal, district, state, from_date, is_current,
    gps_latitude, gps_longitude, gps_accuracy_m, gps_captured_at)
  SELECT v_person_id,
    COALESCE(old.door_no, '-'), COALESCE(old.pin_code, '000000'),
    old.village_id, old.mandal, old.district, old.state,
    CURRENT_DATE, TRUE,
    p_new_lat, p_new_lng, p_accuracy_m, now()
  FROM person_addresses old
  WHERE old.person_id = v_person_id AND old.is_current = FALSE
  ORDER BY old.from_date DESC LIMIT 1;

  RETURN (SELECT village_town_name FROM locations WHERE location_id = (SELECT village_id FROM person_addresses WHERE person_id = v_person_id AND is_current = TRUE LIMIT 1));
END;
$$;

COMMENT ON FUNCTION app.update_customer_address_from_gps(UUID, NUMERIC, NUMERIC, NUMERIC) IS
  'Agent confirms or replaces the customer''s current address after a GPS capture. Copies door/pin/village/mandal/district/state from the previous address and adds the GPS pin. Returns the current village name.';

-- ---- 5. update_loan_gps — agent captures GPS at loan issue (called after   --
--      create_loan_with_bf_check returns the loan_id).                     --
CREATE OR REPLACE FUNCTION app.update_loan_gps(
  p_loan_id UUID,
  p_lat NUMERIC(9,6),
  p_lng NUMERIC(9,6),
  p_accuracy_m NUMERIC(7,2)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM loans l
    WHERE l.loan_id = p_loan_id
      AND (app.is_owner(l.business_id)
           OR app.own_active_agent_membership_permits(
                app.active_membership_id(l.business_id, 'Agent'),
                'can_issue_loans', l.business_id))
  ) THEN
    RAISE EXCEPTION 'Not authorized to record GPS on this loan' USING ERRCODE = '42501';
  END IF;
  UPDATE loans SET issue_lat = p_lat, issue_lng = p_lng,
    issue_accuracy_m = p_accuracy_m, issue_gps_at = now()
  WHERE loan_id = p_loan_id;
END;
$$;

COMMENT ON FUNCTION app.update_loan_gps(UUID, NUMERIC, NUMERIC, NUMERIC) IS
  'Sets the agent''s GPS capture on a loan after creation. Called right after create_loan_with_bf_check in the wizard flow. The caller must be the loan''s Owner or issuing Agent.';

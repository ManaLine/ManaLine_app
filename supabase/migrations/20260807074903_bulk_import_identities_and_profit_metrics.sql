-- P3: bulk identity onboarding (Agent/Customer/Investor together, with
-- auto-generated MLIDs) plus two new money metrics the old paper-book
-- migration needs: investor payable balance and business profit.
--
-- See docs/15_Calculation_Engine.md and CLAUDE.md for the locked money
-- rules this must not violate. Design finalized over a clarification pass
-- against a real historical ledger (Sri Tirumala Finance) before any of
-- this was written -- every formula below was checked against that book.

-- ---------------------------------------------------------------------
-- app.register_new_investor -- mirrors register_new_agent exactly, except
-- it lands the membership Active immediately. An Investor's deposit is
-- real money already in the business the moment the Owner records it;
-- unlike an Agent, there is no separate "accept the invite" step to wait
-- for.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.register_new_investor(
  p_business_id uuid,
  p_full_name character varying,
  p_father_husband_name character varying,
  p_gender_digit character,
  p_mobile_number character varying,
  p_aadhaar_number character varying
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_last8 VARCHAR(8);
  v_mlid VARCHAR(13);
  v_person_id BIGINT;
  v_membership_id UUID;
  v_investor_id UUID;
  v_existing_person_id BIGINT;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  -- BR-181/182, Addendum v3: Investor registration is Aadhaar-mandatory,
  -- MLPI-only -- same restriction already enforced for Agent.
  IF p_aadhaar_number IS NULL THEN
    RAISE EXCEPTION 'Aadhaar Number is required to register an Investor' USING ERRCODE = '23514';
  END IF;

  v_last8 := RIGHT(p_aadhaar_number, 8);
  v_mlid := 'MLPI' || p_gender_digit || v_last8;

  -- Same collision handling as register_new_agent: a fixed, fully
  -- deterministic MLID has no room to retry with a different value.
  SELECT person_id INTO v_existing_person_id FROM persons WHERE mlid = v_mlid;
  IF v_existing_person_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM persons WHERE person_id = v_existing_person_id AND aadhaar_number = p_aadhaar_number) THEN
      RAISE EXCEPTION 'This Aadhaar number is already registered under an existing account.' USING ERRCODE = '23505';
    ELSE
      RAISE EXCEPTION 'MLID collision: the last 8 digits of this Aadhaar number, combined with gender, already match a different existing person. This is a rare coincidence, not a duplicate — please contact support to resolve manually.' USING ERRCODE = '23505';
    END IF;
  END IF;

  INSERT INTO persons (
    mlid, mlid_type, gender_digit, full_name, father_husband_name,
    mobile_number, aadhaar_number, registration_source, customer_type
  ) VALUES (
    v_mlid, 'MLPI', p_gender_digit, p_full_name, p_father_husband_name,
    p_mobile_number, p_aadhaar_number, 'Owner', 'New'
  ) RETURNING person_id INTO v_person_id;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status,
    onboarding_method, invited_by_person_id
  ) VALUES (
    v_person_id, p_business_id, 'Investor', 'Active', 'Not Required',
    'Direct Registration', app.current_person_id()
  ) RETURNING membership_id INTO v_membership_id;

  INSERT INTO investors (membership_id, person_id)
  VALUES (v_membership_id, v_person_id)
  RETURNING investor_id INTO v_investor_id;

  RETURN v_investor_id;
END;
$function$;

REVOKE ALL ON FUNCTION app.register_new_investor(uuid, varchar, varchar, character, varchar, varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.register_new_investor(uuid, varchar, varchar, character, varchar, varchar) TO authenticated;

-- ---------------------------------------------------------------------
-- app.find_or_create_location -- resolves a bare pin code to a location
-- for bulk identity import. (pin_code, village_town_name) is the real
-- unique key here -- one pin code legitimately covers several villages --
-- so a pin code that matches zero or more-than-one existing location
-- cannot be guessed at. Those rows park under one shared "Unconfirmed"
-- placeholder per pin code; the Owner resolves it into a real village
-- later, and the placeholder's own name says it needs that.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.find_or_create_location(p_pin_code character varying)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_count int;
  v_location_id uuid;
  v_placeholder CONSTANT varchar := 'Unconfirmed';
BEGIN
  SELECT count(*) INTO v_count FROM locations WHERE pin_code = p_pin_code;

  IF v_count = 1 THEN
    SELECT location_id INTO v_location_id FROM locations WHERE pin_code = p_pin_code;
    RETURN v_location_id;
  END IF;

  SELECT location_id INTO v_location_id
    FROM locations
   WHERE pin_code = p_pin_code AND village_town_name = v_placeholder;
  IF v_location_id IS NOT NULL THEN
    RETURN v_location_id;
  END IF;

  INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status)
  VALUES (p_pin_code, v_placeholder, 'Village', v_placeholder, v_placeholder, v_placeholder, 'Active')
  RETURNING location_id INTO v_location_id;

  RETURN v_location_id;
END;
$function$;

REVOKE ALL ON FUNCTION app.find_or_create_location(varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.find_or_create_location(varchar) TO authenticated;

-- ---------------------------------------------------------------------
-- app.find_potential_duplicate_customers -- read-only check, called BEFORE
-- app.bulk_import_identities so the Owner can review a clickable
-- Merge/Ignore list first, same as the wizard's own design.
--
-- Scoped to Customer rows only. Agent and Investor are now Aadhaar-
-- mandatory (see register_new_agent / register_new_investor above), which
-- already gives them a hard, unique-constraint-backed duplicate check with
-- a clear error message -- a soft Name+PinCode match would be redundant
-- for those two roles. Customer is the one role where Aadhaar stays
-- optional, so it is the one role that actually needs this.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.find_potential_duplicate_customers(
  p_business_id uuid,
  p_rows        json
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_row json;
  v_index int := 0;
  v_matches json[] := '{}';
  v_existing json[];
  v_name text;
  v_pin text;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    IF (v_row ->> 'user_type') <> 'Customer' THEN
      CONTINUE;
    END IF;
    v_name := lower(trim(v_row ->> 'full_name'));
    v_pin  := v_row ->> 'pin_code';

    SELECT array_agg(json_build_object(
             'membership_id', bm.membership_id,
             'mlid', p.mlid,
             'full_name', p.full_name
           ))
      INTO v_existing
      FROM business_members bm
      JOIN persons p ON p.person_id = bm.person_id
      JOIN person_addresses pa ON pa.person_id = p.person_id AND pa.is_current
     WHERE bm.business_id = p_business_id
       AND bm.role = 'Customer'
       AND bm.membership_status <> 'Removed'
       AND lower(trim(p.full_name)) = v_name
       AND pa.pin_code = v_pin;

    IF v_existing IS NOT NULL AND array_length(v_existing, 1) > 0 THEN
      v_matches := v_matches || json_build_object(
        'row', v_index, 'reason', 'existing_customer', 'candidates', array_to_json(v_existing)
      );
    END IF;

    IF EXISTS (
      SELECT 1 FROM json_array_elements(p_rows) WITH ORDINALITY AS t(elem, ord)
       WHERE t.ord < v_index
         AND (elem ->> 'user_type') = 'Customer'
         AND lower(trim(elem ->> 'full_name')) = v_name
         AND (elem ->> 'pin_code') = v_pin
    ) THEN
      v_matches := v_matches || json_build_object('row', v_index, 'reason', 'duplicate_in_file');
    END IF;
  END LOOP;

  RETURN json_build_object('duplicates', COALESCE(array_to_json(v_matches), '[]'::json));
END;
$function$;

REVOKE ALL ON FUNCTION app.find_potential_duplicate_customers(uuid, json) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.find_potential_duplicate_customers(uuid, json) TO authenticated;

-- ---------------------------------------------------------------------
-- app.bulk_import_identities -- Step 1 of the migration wizard. A FEEDER
-- over register_new_customer / register_new_agent / register_new_investor,
-- not a second way to create a person -- same reasoning as
-- app.import_migrated_loans feeding app.migrate_loan. ALL-OR-NOTHING, ALL
-- ERRORS AT ONCE: each row runs in its own subtransaction so one bad row
-- doesn't hide the next one, and nothing commits until the whole sheet is
-- clean.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.bulk_import_identities(
  p_business_id uuid,
  p_rows        json
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_locked      BOOLEAN;
  v_row         json;
  v_index       INT := 0;
  v_ok          INT := 0;
  v_errors      json[] := '{}';
  v_created     json[] := '{}';
  v_msg         TEXT;
  v_type        TEXT;
  v_location    UUID;
  v_agent_id    UUID;
  v_investor_id UUID;
  v_customer_id UUID;
  v_mlid        VARCHAR;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to import records into this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;

    -- Owner already saw this row flagged as a likely duplicate and chose
    -- Ignore in the review step -- skip it without counting it as a
    -- failure.
    IF COALESCE(v_row ->> 'dedupe_decision', '') = 'ignore' THEN
      CONTINUE;
    END IF;

    BEGIN
      v_type := v_row ->> 'user_type';
      v_mlid := NULL;

      IF v_type = 'Customer' THEN
        v_location := NULL;
        IF NULLIF(v_row ->> 'pin_code', '') IS NOT NULL THEN
          v_location := app.find_or_create_location(v_row ->> 'pin_code');
        END IF;

        v_customer_id := app.register_new_customer(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', ''),
          NULLIF(v_row ->> 'door_no', ''),
          NULLIF(v_row ->> 'pin_code', ''),
          v_location
        );
        SELECT p.mlid INTO v_mlid FROM customers c JOIN persons p ON p.person_id = c.person_id
          WHERE c.customer_id = v_customer_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Customer', 'customer_id', v_customer_id, 'mlid', v_mlid
        );

      ELSIF v_type = 'Agent' THEN
        v_agent_id := app.register_new_agent(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', '')
        );

        -- register_new_agent lands a freshly invited agent as
        -- 'Pending Invitation' / 'Pending Verification' -- correct for
        -- someone about to be sent an invite, wrong for someone who has
        -- already been collecting for years before this app existed.
        -- Activated immediately here, the same way migrate_loan enters a
        -- historical loan as already Active rather than re-running loan
        -- origination.
        UPDATE business_members bm
           SET membership_status = 'Active', verification_status = 'Not Required'
          FROM agents a
         WHERE a.agent_id = v_agent_id AND bm.membership_id = a.membership_id;

        SELECT p.mlid INTO v_mlid FROM agents a JOIN persons p ON p.person_id = a.person_id
          WHERE a.agent_id = v_agent_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Agent', 'agent_id', v_agent_id, 'mlid', v_mlid
        );

      ELSIF v_type = 'Investor' THEN
        v_investor_id := app.register_new_investor(
          p_business_id,
          v_row ->> 'full_name',
          v_row ->> 'father_husband_name',
          v_row ->> 'gender_digit',
          NULLIF(v_row ->> 'mobile_number', ''),
          NULLIF(v_row ->> 'aadhaar_number', '')
        );
        SELECT p.mlid INTO v_mlid FROM investors i JOIN persons p ON p.person_id = i.person_id
          WHERE i.investor_id = v_investor_id;
        v_created := v_created || json_build_object(
          'row', v_index, 'user_type', 'Investor', 'investor_id', v_investor_id, 'mlid', v_mlid
        );

      ELSE
        RAISE EXCEPTION 'Unknown User Type "%": must be Agent, Customer or Investor', v_type;
      END IF;

      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index, 'full_name', v_row ->> 'full_name', 'error', v_msg
      );
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0, 'failed', array_length(v_errors, 1), 'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object('imported', v_ok, 'total', v_index, 'created', array_to_json(v_created));
END;
$function$;

REVOKE ALL ON FUNCTION app.bulk_import_identities(uuid, json) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.bulk_import_identities(uuid, json) TO authenticated;

-- ---------------------------------------------------------------------
-- app.bulk_import_investments -- Step 2's Investor tab. Rows carry the
-- MLID that Step 1 already generated (the tab is prefilled by the app, per
-- the wizard design) rather than a raw investor_id, since the Owner never
-- sees a UUID.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.bulk_import_investments(
  p_business_id uuid,
  p_rows        json
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_locked        BOOLEAN;
  v_row           json;
  v_index         INT := 0;
  v_ok            INT := 0;
  v_errors        json[] := '{}';
  v_msg           TEXT;
  v_investor_id   UUID;
  v_investment_id UUID;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to import records into this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    BEGIN
      SELECT i.investor_id INTO v_investor_id
        FROM investors i
        JOIN persons p ON p.person_id = i.person_id
        JOIN business_members bm ON bm.membership_id = i.membership_id
       WHERE p.mlid = (v_row ->> 'mlid') AND bm.business_id = p_business_id;

      IF v_investor_id IS NULL THEN
        RAISE EXCEPTION 'No Investor in this business matches MLID %', v_row ->> 'mlid';
      END IF;

      v_investment_id := app.record_investment(
        v_investor_id,
        (v_row ->> 'invested_amount')::NUMERIC,
        (v_row ->> 'roi')::NUMERIC,
        (v_row ->> 'interest_type')::investment_interest_type_enum,
        (v_row ->> 'invested_date')::DATE
      );

      -- profit_share_percent has no dedicated setter yet -- a plain
      -- Owner-declared column, not a derived or money-moving figure, so it
      -- is set directly rather than inventing a wrapper RPC for one UPDATE.
      IF NULLIF(v_row ->> 'profit_percent', '') IS NOT NULL THEN
        UPDATE investments
           SET profit_share_percent = (v_row ->> 'profit_percent')::NUMERIC,
               profit_share_effective_date = (v_row ->> 'invested_date')::DATE
         WHERE investment_id = v_investment_id;
      END IF;

      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index, 'mlid', v_row ->> 'mlid', 'error', v_msg
      );
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0, 'failed', array_length(v_errors, 1), 'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object('imported', v_ok, 'total', v_index);
END;
$function$;

REVOKE ALL ON FUNCTION app.bulk_import_investments(uuid, json) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.bulk_import_investments(uuid, json) TO authenticated;

-- ---------------------------------------------------------------------
-- app.business_investor_payable_balance -- "Bal పెట్టుబడి" from the old
-- paper book: what the business currently owes back to investors,
-- principal still standing plus interest not yet paid or compounded away.
-- Deliberately NOT the same figure as BF (cash in hand): an investor's
-- money already lent out to customers is still owed to the investor even
-- though it is not sitting in the till. investment_interest_snapshot's
-- available_balance already nets out prior payments and withdrawals (via
-- principal_amount and last_interest_payment_date), so this is a
-- straight sum, not a second reimplementation of that math.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.business_investor_payable_balance(
  p_business_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT COALESCE(SUM(s.available_balance), 0)
    FROM investments i
    CROSS JOIN LATERAL app.investment_interest_snapshot(i.investment_id, p_as_of) s
   WHERE i.business_id = p_business_id
     AND i.deleted_at IS NULL;
$function$;

REVOKE ALL ON FUNCTION app.business_investor_payable_balance(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.business_investor_payable_balance(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------
-- app.business_profit -- same shape as the old paper book's running
-- total: interest+agreement-fee income from lending, minus business
-- expenses, minus the lifetime interest cost of investor capital (paid,
-- accrued, or already rolled into principal -- all of it is money the
-- business owes for having used that capital, whether or not it has
-- actually been handed over yet). Cheti is excluded on purpose -- a cheti
-- is an asset, its instalments come back as an availed lumpsum, not an
-- expense (CLAUDE.md).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.business_profit(
  p_business_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT COALESCE((SELECT SUM(l.interest_amount + l.processing_fee)
                     FROM loans l
                    WHERE l.business_id = p_business_id
                      AND l.deleted_at IS NULL
                      AND l.issue_business_date <= p_as_of), 0)
       - COALESCE((SELECT SUM(e.amount)
                     FROM expenses e
                    WHERE e.business_id = p_business_id
                      AND e.deleted_at IS NULL
                      AND e.business_date <= p_as_of), 0)
       - COALESCE((SELECT SUM(s.total_interest_earned)
                     FROM investments i
                     CROSS JOIN LATERAL app.investment_interest_snapshot(i.investment_id, p_as_of) s
                    WHERE i.business_id = p_business_id
                      AND i.deleted_at IS NULL
                      AND i.effective_date <= p_as_of), 0);
$function$;

REVOKE ALL ON FUNCTION app.business_profit(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.business_profit(uuid, date) TO authenticated;

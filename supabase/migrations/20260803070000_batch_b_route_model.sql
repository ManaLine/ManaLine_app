-- =============================================================================
-- BATCH B (1/3) — Route-based, time-bounded agent access (M4)
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   An agent's territory is the OPERATING AREA they are assigned to (a named
--   round covering one or more villages), not a list of individual customers.
--   An assignment is now TIME-BOUND: it has a start date and an optional end
--   date, so coverage opens and closes on dates instead of lasting until
--   someone remembers to remove it.
--
--   The per-customer `customers.assigned_agent_membership_id` column is
--   DROPPED. It let the customer record point at an agent who no longer
--   covers that village, and it gave the Owner a second, overlapping place
--   to configure the same thing. Agent visibility is decided by ONE helper,
--   app.agent_covers_customer, which now means: "this customer's current
--   village belongs to an operating area the caller is assigned to right
--   now." Every RLS policy and every RPC that used the dropped column is
--   rewritten onto the same helper, so customers, loans, schedules,
--   collections, penalties and contacts all flip together.
--
--   BR-065 ("shared route, individual accountability"): one area can serve
--   any number of agents; whose transaction it was stays on
--   recorded_by_membership_id.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Time-bounded assignment. valid_to NULL = the window stays open until
--    the Owner re-assigns or removes.
-- ---------------------------------------------------------------------------
CREATE TYPE area_assignment_frequency_enum AS ENUM ('Once', 'Weekly', 'Monthly');

ALTER TABLE agent_area_assignments
  ADD COLUMN frequency  area_assignment_frequency_enum NOT NULL DEFAULT 'Once',
  ADD COLUMN valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN valid_to   DATE NULL;

COMMENT ON COLUMN agent_area_assignments.valid_to IS
  'NULL = the window stays open until the Owner re-assigns (which back-dates it) or removes the row.';

CREATE INDEX idx_agent_area_assignments_open
  ON agent_area_assignments(operating_area_id)
  WHERE removed_at IS NULL AND valid_to IS NULL;

-- uq_area_assignment_live was UNIQUE (operating_area_id, agent_id) WHERE
-- removed_at IS NULL — written before assignments had a window. It forbids a
-- SECOND ROW for the pair, not a second OPEN WINDOW, so assign_agent_area's
-- back-date-then-insert below would always fail with a unique violation.
-- Re-create it on the real invariant: at most one OPEN window per pair.
DROP INDEX IF EXISTS uq_area_assignment_live;
CREATE UNIQUE INDEX uq_area_assignment_live
  ON agent_area_assignments(operating_area_id, agent_id)
  WHERE removed_at IS NULL AND valid_to IS NULL;

-- ---------------------------------------------------------------------------
-- 2. app.agent_covers_customer — the one visibility helper, now area-based.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.agent_covers_customer(p_customer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM customers c
    -- The customer's current address picks their village (operating_areas
    -- carry no location column since the multi-village redesign).
    JOIN person_addresses pa
      ON pa.person_id = c.person_id AND pa.is_current = TRUE
    JOIN operating_area_locations oal
      ON oal.location_id = pa.village_id
    JOIN operating_areas oa
      ON oa.operating_area_id = oal.operating_area_id
    JOIN agent_area_assignments aaa
      ON aaa.operating_area_id = oa.operating_area_id
      AND aaa.removed_at IS NULL
      AND COALESCE(aaa.valid_from, CURRENT_DATE) <= CURRENT_DATE
      AND (aaa.valid_to IS NULL OR aaa.valid_to >= CURRENT_DATE)
    JOIN agents ag ON ag.agent_id = aaa.agent_id
    JOIN business_members bm ON bm.membership_id = ag.membership_id
    WHERE c.customer_id = p_customer_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
      AND bm.role = 'Agent'
  );
$$;

COMMENT ON FUNCTION app.agent_covers_customer(UUID) IS
  'TRUE when the current person holds a current (not removed, window open) Agent assignment to an operating area that contains this customer''s current village. Replaces the old per-customer assigned_agent_membership_id check.';

-- ---------------------------------------------------------------------------
-- 3. app.covering_agent_membership_id — the membership of whoever currently
--    covers a customer's village, used where a collecting agent must be
--    resolved (loan migration fallbacks, Owner profile display).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.covering_agent_membership_id(p_customer_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT bm.membership_id
  FROM customers c
  JOIN person_addresses pa
    ON pa.person_id = c.person_id AND pa.is_current = TRUE
  JOIN operating_area_locations oal
    ON oal.location_id = pa.village_id
  JOIN operating_areas oa
    ON oa.operating_area_id = oal.operating_area_id
  JOIN agent_area_assignments aaa
    ON aaa.operating_area_id = oa.operating_area_id
    AND aaa.removed_at IS NULL
    AND COALESCE(aaa.valid_from, CURRENT_DATE) <= CURRENT_DATE
    AND (aaa.valid_to IS NULL OR aaa.valid_to >= CURRENT_DATE)
  JOIN agents ag ON ag.agent_id = aaa.agent_id
  JOIN business_members bm ON bm.membership_id = ag.membership_id
  WHERE c.customer_id = p_customer_id
    AND bm.membership_status = 'Active'
  ORDER BY aaa.valid_from DESC NULLS LAST
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS policy that used the dropped column: an agent may read the
--    business_members rows of the customers they cover.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS business_members_agent_select_assigned_customers ON business_members;

CREATE POLICY business_members_agent_select_assigned_customers ON business_members
  FOR SELECT
  USING (
    role = 'Customer'
    AND app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_view_customers')
    AND EXISTS (
      SELECT 1 FROM customers c
      WHERE c.membership_id = business_members.membership_id
        AND app.agent_covers_customer(c.customer_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Agent contact-edit RPCs. The permission check no longer proves the
--    agent through customers.assigned_agent_membership_id; it resolves the
--    caller's own active Agent membership in the customer's business.
-- ---------------------------------------------------------------------------
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
    JOIN business_members cust_bm ON cust_bm.membership_id = c.membership_id
    JOIN business_members bm
      ON bm.business_id = cust_bm.business_id
      AND bm.person_id = app.current_person_id()
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
    JOIN agent_permissions ap ON ap.permission_profile_id = bm.permission_profile_id
    WHERE c.customer_id = p_customer_id
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
    JOIN business_members cust_bm ON cust_bm.membership_id = c.membership_id
    JOIN business_members bm
      ON bm.business_id = cust_bm.business_id
      AND bm.person_id = app.current_person_id()
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
    JOIN agent_permissions ap ON ap.permission_profile_id = bm.permission_profile_id
    WHERE c.customer_id = p_customer_id
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

-- ---------------------------------------------------------------------------
-- 6. Penalty gate — same pattern (the caller's own membership, not the
--    customer's assigned agent).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.can_apply_penalty_on_loan(p_loan_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_customer_id UUID;
BEGIN
  SELECT business_id, customer_id INTO v_business_id, v_customer_id
  FROM loans WHERE loan_id = p_loan_id;
  IF v_business_id IS NULL THEN
    RETURN FALSE;
  END IF;
  IF app.is_owner(v_business_id) THEN
    RETURN TRUE;
  END IF;
  RETURN app.agent_covers_customer(v_customer_id) AND EXISTS (
    SELECT 1 FROM customers c
    JOIN business_members cust_bm ON cust_bm.membership_id = c.membership_id
    JOIN business_members bm
      ON bm.business_id = cust_bm.business_id
      AND bm.person_id = app.current_person_id()
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
    JOIN agent_permissions ap ON ap.permission_profile_id = bm.permission_profile_id
    WHERE c.customer_id = v_customer_id
      AND ap.can_apply_penalty = TRUE
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. migrate_loan — the collecting-agent fallback used to read the customer's
--    assigned agent; it now asks who currently covers the customer's village.
--    Signature and every other behaviour preserved exactly.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.migrate_loan(uuid,uuid,numeric,numeric,numeric,date,repayment_frequency_enum,numeric,integer,numeric,uuid);

CREATE FUNCTION app.migrate_loan(
    p_customer_id uuid, p_business_id uuid, p_amount_given numeric,
    p_repayment_amount numeric, p_remaining_balance numeric,
    p_effective_date date, p_repayment_type repayment_frequency_enum,
    p_installment_amount numeric,
    p_grace_period_days integer DEFAULT 0,
    p_processing_fee numeric DEFAULT 0,
    p_collection_agent_membership_id uuid DEFAULT NULL::uuid
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  v_locked BOOLEAN;
  v_given DECIMAL(14,0) := CEIL(p_amount_given);
  v_repay DECIMAL(14,0) := CEIL(p_repayment_amount);
  v_remain DECIMAL(14,0) := CEIL(p_remaining_balance);
  v_fee DECIMAL(14,0) := CEIL(COALESCE(p_processing_fee, 0));
  v_inst DECIMAL(14,0) := CEIL(p_installment_amount);
  v_collected DECIMAL(14,0);
  v_interest DECIMAL(14,0);
  v_status loan_status_enum;
  v_agent_membership UUID;
  v_loan_id UUID;
  v_loan_number VARCHAR(30);
  v_interval INTERVAL;
  v_n INT;
  v_due DATE;
  v_left DECIMAL(14,0);
  v_amt DECIMAL(14,0);
  i INT;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(
               p_collection_agent_membership_id, 'can_migrate_records') THEN
    RAISE EXCEPTION 'Not authorized to enter pre-existing records for this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is locked for this business. Reopen migration before entering pre-existing records.'
      USING ERRCODE = '23514';
  END IF;

  IF v_repay <= 0 OR v_given <= 0 OR v_inst <= 0 THEN
    RAISE EXCEPTION 'Amount Given, Repayment Amount and Installment Amount must all be greater than zero'
      USING ERRCODE = '23514';
  END IF;
  IF v_remain < 0 OR v_remain > v_repay THEN
    RAISE EXCEPTION 'Remaining Balance must be between 0 and the Repayment Amount (%)', v_repay
      USING ERRCODE = '23514';
  END IF;
  IF v_given + v_fee > v_repay THEN
    RAISE EXCEPTION 'Amount Given plus Processing Fee (%) cannot exceed the Repayment Amount (%) - that would make interest negative',
      v_given + v_fee, v_repay USING ERRCODE = '23514';
  END IF;

  v_agent_membership := p_collection_agent_membership_id;
  IF v_agent_membership IS NULL THEN
    v_agent_membership := app.covering_agent_membership_id(p_customer_id);
  END IF;
  IF v_agent_membership IS NULL THEN
    SELECT bm.membership_id INTO v_agent_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.business_id = p_business_id
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
      AND bm.person_id = b.owner_person_id
    LIMIT 1;
  END IF;
  IF v_agent_membership IS NULL THEN
    RAISE EXCEPTION 'No collecting agent could be determined for this loan. Assign an agent to the customer first.'
      USING ERRCODE = '23502';
  END IF;

  v_collected := v_repay - v_remain;
  v_interest  := v_repay - v_given - v_fee;
  v_status    := (CASE WHEN v_remain <= 0 THEN 'Closed' ELSE 'Active' END)::loan_status_enum;

  v_interval := CASE p_repayment_type
                  WHEN 'Daily'   THEN INTERVAL '1 day'
                  WHEN 'Weekly'  THEN INTERVAL '7 days'
                  ELSE                INTERVAL '1 month'
                END;

  v_n := GREATEST(CEIL(v_remain::numeric / v_inst)::INT, 0);

  v_loan_number := 'LN-MIG-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO loans (
    loan_number, customer_id, business_id, repayment_amount, interest_amount,
    processing_fee, repayment_type, duration_value, installment_amount,
    grace_period_days, remaining_balance, collection_agent_membership_id, effective_date,
    loan_status, issue_business_date, live_photo_url
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, v_repay, v_interest,
    v_fee, p_repayment_type, v_n, v_inst,
    COALESCE(p_grace_period_days, 0), v_remain, v_agent_membership, p_effective_date,
    v_status,
    p_effective_date,
    'migrated:pre-existing-loan:no-live-photo'
  ) RETURNING loan_id INTO v_loan_id;

  v_left := v_remain;
  v_due := CURRENT_DATE;
  i := 1;
  WHILE v_left > 0 LOOP
    v_amt := LEAST(v_inst, v_left);
    INSERT INTO loan_schedule (loan_id, installment_number, due_date, installment_amount, status)
    VALUES (v_loan_id, i, v_due, v_amt, 'Pending');
    v_left := v_left - v_amt;
    v_due := (v_due + v_interval)::date;
    i := i + 1;
  END LOOP;

  -- NO owner_bf_balance UPDATE here. BF is declared; that declared count
  -- already contains the effect of every pre-existing loan.

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    p_business_id, app.current_person_id(), 'Other Admin Event', 'loan_migrated', 0,
    v_loan_id,
    json_build_object('amount_given', v_given, 'repayment_amount', v_repay,
                      'remaining_balance', v_remain, 'collected', v_collected,
                      'interest_amount', v_interest, 'effective_date', p_effective_date),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'loan_id', v_loan_id, 'loan_number', v_loan_number,
    'collected', v_collected, 'interest_amount', v_interest,
    'installments_created', GREATEST(i - 1, 0)
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION app.migrate_loan(uuid,uuid,numeric,numeric,numeric,date,repayment_frequency_enum,numeric,integer,numeric,uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. Drop the per-customer column. All dependent policies and functions are
--    already rewritten above, so the drop is clean.
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_customers_agent;
ALTER TABLE customers DROP COLUMN assigned_agent_membership_id;

-- ---------------------------------------------------------------------------
-- 9. assign_agent_area — closes the area's current open window and opens a
--    new one (mirrors what owner_api_service.assignAreaToAgent did
--    client-side, now atomic and Owner-gated server-side). Seeds the area's
--    first Running Account Period exactly like the old client path.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.assign_agent_area(
  p_agent_id UUID,
  p_operating_area_id UUID,
  p_frequency area_assignment_frequency_enum DEFAULT 'Once',
  p_valid_from DATE DEFAULT CURRENT_DATE,
  p_valid_to DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_membership_id UUID;
  v_assignment_id UUID;
  v_dur INT;
  v_unit account_cycle_unit_enum;
BEGIN
  SELECT bm.business_id, bm.membership_id INTO v_business_id, v_membership_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE a.agent_id = p_agent_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may assign areas' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM operating_areas
    WHERE operating_area_id = p_operating_area_id AND business_id = v_business_id
  ) THEN
    RAISE EXCEPTION 'Area does not belong to this business' USING ERRCODE = '42501';
  END IF;

  IF p_valid_from IS NULL THEN p_valid_from := CURRENT_DATE; END IF;
  IF p_valid_to IS NOT NULL AND p_valid_to < p_valid_from THEN
    RAISE EXCEPTION 'valid_to cannot be before valid_from' USING ERRCODE = '23514';
  END IF;

  -- Re-assign for the SAME (agent, area) pair: the live unique index
  -- uq_area_assignment_live forbids two open windows, so back-date this
  -- agent's prior open window on this area the day before the new one opens.
  -- Other agents on the area are untouched (BR-065 shared route), and this
  -- agent's windows on OTHER areas are untouched (an agent may cover more
  -- than one round).
  UPDATE agent_area_assignments
  SET valid_to = p_valid_from - 1
  WHERE operating_area_id = p_operating_area_id
    AND agent_id = p_agent_id
    AND removed_at IS NULL
    AND valid_to IS NULL;

  INSERT INTO agent_area_assignments (agent_id, operating_area_id, frequency, valid_from, valid_to)
  VALUES (p_agent_id, p_operating_area_id, p_frequency, p_valid_from, p_valid_to)
  RETURNING assignment_id INTO v_assignment_id;

  -- Seed the area's first Running Account Period (same computation the old
  -- client-side path used) so OW-012's Account Periods tab is not empty.
  IF NOT EXISTS (
    SELECT 1 FROM account_periods
    WHERE operating_area_id = p_operating_area_id AND status = 'Running'
  ) THEN
    SELECT account_cycle_duration, account_cycle_unit INTO v_dur, v_unit
    FROM operating_areas WHERE operating_area_id = p_operating_area_id;

    INSERT INTO account_periods (
      business_id, operating_area_id, agent_membership_id,
      business_start_date, planned_business_end_date, status
    ) VALUES (
      v_business_id, p_operating_area_id, v_membership_id, now(),
      now() + (v_dur || ' ' ||
        CASE v_unit WHEN 'Weeks' THEN 'week' WHEN 'Months' THEN 'month' ELSE 'day' END)::interval,
      'Running'
    );
  END IF;

  RETURN v_assignment_id;
END;
$$;

COMMENT ON FUNCTION app.assign_agent_area(UUID, UUID, area_assignment_frequency_enum, DATE, DATE) IS
  'OW-012/OW-000. Owner assigns an area to an agent with an optional window. Closes the area''s previous open window, inserts the new assignment, and seeds a Running Account Period if the area has none.';

GRANT EXECUTE ON FUNCTION app.assign_agent_area(UUID, UUID, area_assignment_frequency_enum, DATE, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. list_agent_areas — the agent's current and upcoming assignments.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.list_agent_areas(p_agent_id UUID)
RETURNS TABLE (
  assignment_id UUID,
  operating_area_id UUID,
  area_name TEXT,
  frequency area_assignment_frequency_enum,
  valid_from DATE,
  valid_to DATE
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT aaa.assignment_id, aaa.operating_area_id, oa.name::TEXT,
         aaa.frequency, aaa.valid_from, aaa.valid_to
  FROM agent_area_assignments aaa
  JOIN operating_areas oa ON oa.operating_area_id = aaa.operating_area_id
  WHERE aaa.agent_id = p_agent_id
    AND aaa.removed_at IS NULL
  ORDER BY aaa.valid_from DESC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION app.list_agent_areas(UUID) TO authenticated;

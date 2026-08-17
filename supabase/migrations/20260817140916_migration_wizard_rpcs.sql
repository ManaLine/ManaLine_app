-- Pre-existing-business migration, part B: the server side of the seven wizard
-- pages. Every write goes through an RPC so the client never has to know a
-- money rule; the client parses spreadsheets and nothing else.
--
-- NOTE: app.migration_profit_summary and app.profit_share_accrued are both
-- superseded later in this batch (20260817151200, 20260817151421) - plpgsql
-- bodies are not type-checked at CREATE time and both had a runtime fault that
-- only a real invocation found. The later files are authoritative.

-- ---------------------------------------------------------------------------
-- Opening snapshot
--
-- The cut-off model: the Owner declares what the book said on the cut-off date
-- (cash in hand, line balance, profit to date) and everything after that date
-- is real history. Declared and computed profit will not agree - a paper book
-- rounds, forgets and back-dates - so the difference is stored and carried
-- forward rather than silently reconciled away.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.migration_snapshots (
  snapshot_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id            uuid NOT NULL UNIQUE REFERENCES public.businesses(business_id) ON DELETE CASCADE,
  cutoff_date            date NOT NULL,
  opening_bf_amount      numeric(14,0) NOT NULL,
  declared_line_balance  numeric(14,0) NOT NULL,
  declared_profit        numeric(14,0) NOT NULL,
  computed_line_balance  numeric(14,0) NOT NULL,
  computed_profit        numeric(14,0) NOT NULL,
  profit_carry_forward   numeric(14,0) NOT NULL,
  recorded_by_person_id  bigint NOT NULL REFERENCES public.persons(person_id),
  created_at             timestamp without time zone NOT NULL DEFAULT now(),
  updated_at             timestamp without time zone NOT NULL DEFAULT now()
);

ALTER TABLE public.migration_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS migration_snapshots_owner ON public.migration_snapshots;
CREATE POLICY migration_snapshots_owner ON public.migration_snapshots
  FOR ALL USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.migration_snapshots TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Villages: suggest, never validate
--
-- lgd_villages is 768,529 rows of reference data. It suggests; the Owner
-- decides. 8.1% of PIN codes list two districts (post-2022 splits) and no
-- heuristic picks the right one, so the caller asks once per PIN and the
-- answer is stored on the location row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.suggest_villages(p_pincode text)
RETURNS TABLE(village text, mandal text, district text, state text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT DISTINCT v.village, v.mandal, v.district, v.state
  FROM lgd_villages v
  WHERE v.pincode = regexp_replace(COALESCE(p_pincode, ''), '[^0-9]', '', 'g')
  ORDER BY v.district, v.mandal, v.village;
$$;

GRANT EXECUTE ON FUNCTION app.suggest_villages(text) TO authenticated, service_role;

-- Owner-confirmed villages, then the areas that hold them. Both are
-- all-or-nothing: half an operating area is worse than none.
CREATE OR REPLACE FUNCTION app.migration_upsert_villages(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_index INT := 0;
  v_out json[] := '{}';
  v_location_id uuid;
  v_pin varchar;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to add villages for this business' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    v_pin := regexp_replace(COALESCE(v_row ->> 'pin_code', ''), '[^0-9]', '', 'g');

    IF length(v_pin) <> 6 THEN
      RAISE EXCEPTION 'Row %: PIN code must be 6 digits.', v_index USING ERRCODE = '23514';
    END IF;
    IF NULLIF(btrim(COALESCE(v_row ->> 'village', '')), '') IS NULL THEN
      RAISE EXCEPTION 'Row %: Village is required.', v_index USING ERRCODE = '23514';
    END IF;
    IF NULLIF(btrim(COALESCE(v_row ->> 'district', '')), '') IS NULL THEN
      RAISE EXCEPTION 'Row %: District is required - two districts can share one PIN, so it cannot be guessed.', v_index
        USING ERRCODE = '23514';
    END IF;

    SELECT l.location_id INTO v_location_id
      FROM app.add_location_if_missing(
             v_pin::varchar,
             btrim(v_row ->> 'village')::varchar,
             COALESCE(NULLIF(v_row ->> 'area_type', ''), 'Village')::location_area_type_enum,
             btrim(COALESCE(v_row ->> 'mandal', v_row ->> 'district'))::varchar,
             btrim(v_row ->> 'district')::varchar,
             btrim(COALESCE(v_row ->> 'state', ''))::varchar
           ) l;

    v_out := v_out || json_build_object(
      'row', v_index, 'pin_code', v_pin, 'village', btrim(v_row ->> 'village'),
      'location_id', v_location_id
    );
  END LOOP;

  RETURN json_build_object('villages', array_to_json(v_out), 'total', v_index);
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_upsert_villages(uuid, json) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.migration_create_areas(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_village json;
  v_index INT := 0;
  v_out json[] := '{}';
  v_area_id uuid;
  v_name varchar;
  v_location_id uuid;
  v_pin varchar;
  v_attached INT;
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

      IF NOT EXISTS (
        SELECT 1 FROM operating_area_locations
         WHERE operating_area_id = v_area_id AND location_id = v_location_id AND removed_at IS NULL
      ) THEN
        INSERT INTO operating_area_locations (operating_area_id, location_id, business_id)
        VALUES (v_area_id, v_location_id, p_business_id);
        v_attached := v_attached + 1;
      END IF;
    END LOOP;

    v_out := v_out || json_build_object(
      'row', v_index, 'name', v_name, 'operating_area_id', v_area_id, 'villages_attached', v_attached
    );
  END LOOP;

  RETURN json_build_object('areas', array_to_json(v_out), 'total', v_index);
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_create_areas(uuid, json) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Agents: attendance only
--
-- Salary and expenses are declared in the weekly account sheet, because that
-- is where the Owner's book records them. What the agents page contributes is
-- which days each agent actually worked.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.migration_record_attendance(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_index INT := 0;
  v_ok INT := 0;
  v_owner_membership uuid;
  v_membership uuid;
  v_date date;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT bm.membership_id INTO v_owner_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
   WHERE bm.business_id = p_business_id AND bm.person_id = b.owner_person_id
   ORDER BY (bm.role = 'Owner') DESC
   LIMIT 1;

  IF v_owner_membership IS NULL THEN
    RAISE EXCEPTION 'This business has no Owner membership to grant access days.' USING ERRCODE = 'P0002';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;

    SELECT bm.membership_id INTO v_membership
      FROM business_members bm
      JOIN persons p ON p.person_id = bm.person_id
     WHERE bm.business_id = p_business_id AND bm.role = 'Agent' AND p.mlid = v_row ->> 'mlid';

    IF v_membership IS NULL THEN
      RAISE EXCEPTION 'Row %: no Agent with MLID % in this business.', v_index, v_row ->> 'mlid'
        USING ERRCODE = 'P0002';
    END IF;

    v_date := (v_row ->> 'business_date')::date;

    IF NOT EXISTS (
      SELECT 1 FROM agent_access_days
       WHERE membership_id = v_membership AND business_date = v_date
    ) THEN
      INSERT INTO agent_access_days (
        membership_id, business_date, granted_by_membership_id, allowance_amount
      ) VALUES (
        v_membership, v_date, v_owner_membership,
        COALESCE((v_row ->> 'allowance_amount')::numeric, 0)
      );
      v_ok := v_ok + 1;
    END IF;
  END LOOP;

  RETURN json_build_object('recorded', v_ok, 'total', v_index);
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_record_attendance(uuid, json) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Profit, the way the Owner's own book computes it
--
--   Profit = SUM(interest + fee) - SUM(expenses) - (investor interest - withdrawal interest)
--
-- Validated twice against real books (2021-23 and 2026). app.business_profit
-- is the app's forward-looking figure and uses accrued investor interest; this
-- one uses what was actually PAID, because that is what a paper book records
-- and what the migration has to reconcile against.
--
-- Superseded by 20260817151421 (the collections join).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.migration_profit_summary(
  p_business_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_interest numeric := 0;
  v_fee numeric := 0;
  v_expenses numeric := 0;
  v_inv_interest numeric := 0;
  v_wd_interest numeric := 0;
  v_line_balance numeric := 0;
  v_collections numeric := 0;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(l.interest_amount), 0), COALESCE(SUM(l.processing_fee), 0),
         COALESCE(SUM(CASE WHEN l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')
                           THEN l.remaining_balance ELSE 0 END), 0)
    INTO v_interest, v_fee, v_line_balance
    FROM loans l
   WHERE l.business_id = p_business_id AND l.deleted_at IS NULL
     AND l.issue_business_date <= p_as_of;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
    FROM expenses e
   WHERE e.business_id = p_business_id AND e.deleted_at IS NULL AND e.business_date <= p_as_of;

  SELECT COALESCE(SUM(il.amount), 0) INTO v_inv_interest
    FROM investment_interest_ledger il
    JOIN investments i ON i.investment_id = il.investment_id
   WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
     AND il.entry_type = 'Payment' AND il.business_date <= p_as_of;

  SELECT COALESCE(SUM(w.interest_portion), 0) INTO v_wd_interest
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
   WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
     AND w.deleted_at IS NULL AND w.business_date <= p_as_of;

  SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
    FROM collections c
   WHERE c.business_id = p_business_id AND c.deleted_at IS NULL AND c.business_date <= p_as_of;

  RETURN json_build_object(
    'as_of', p_as_of,
    'interest', v_interest,
    'fee', v_fee,
    'expenses', v_expenses,
    'investor_interest', v_inv_interest,
    'withdrawal_interest', v_wd_interest,
    'profit', v_interest + v_fee - v_expenses - (v_inv_interest - v_wd_interest),
    'line_balance', v_line_balance,
    'collections', v_collections
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_profit_summary(uuid, date) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.record_opening_snapshot(
  p_business_id uuid,
  p_cutoff_date date,
  p_opening_bf numeric,
  p_declared_line_balance numeric,
  p_declared_profit numeric
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_summary json;
  v_computed_profit numeric;
  v_computed_lb numeric;
  v_carry numeric;
  v_person bigint := app.current_person_id();
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF p_cutoff_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'The cut-off date cannot be in the future.' USING ERRCODE = '23514';
  END IF;
  IF p_opening_bf < 0 THEN
    RAISE EXCEPTION 'Opening BF is cash counted on the cut-off date and cannot be negative.'
      USING ERRCODE = '23514';
  END IF;

  v_summary := app.migration_profit_summary(p_business_id, p_cutoff_date);
  v_computed_profit := (v_summary ->> 'profit')::numeric;
  v_computed_lb := (v_summary ->> 'line_balance')::numeric;
  v_carry := ROUND(p_declared_profit - v_computed_profit);

  INSERT INTO migration_snapshots (
    business_id, cutoff_date, opening_bf_amount, declared_line_balance, declared_profit,
    computed_line_balance, computed_profit, profit_carry_forward, recorded_by_person_id
  ) VALUES (
    p_business_id, p_cutoff_date, ROUND(p_opening_bf), ROUND(p_declared_line_balance),
    ROUND(p_declared_profit), ROUND(v_computed_lb), ROUND(v_computed_profit), v_carry, v_person
  )
  ON CONFLICT (business_id) DO UPDATE SET
    cutoff_date = EXCLUDED.cutoff_date,
    opening_bf_amount = EXCLUDED.opening_bf_amount,
    declared_line_balance = EXCLUDED.declared_line_balance,
    declared_profit = EXCLUDED.declared_profit,
    computed_line_balance = EXCLUDED.computed_line_balance,
    computed_profit = EXCLUDED.computed_profit,
    profit_carry_forward = EXCLUDED.profit_carry_forward,
    recorded_by_person_id = EXCLUDED.recorded_by_person_id,
    updated_at = now();

  -- Day one seeds from the declared opening, never from owner_bf_balance -
  -- seeding a derived running total from itself was the original defect.
  UPDATE businesses
     SET opening_bf_declared_amount = ROUND(p_opening_bf),
         opening_bf_declared_on = p_cutoff_date,
         business_started_at = COALESCE(business_started_at, p_cutoff_date::timestamp)
   WHERE business_id = p_business_id;

  PERFORM app.recompute_ledger_chain(p_business_id);

  RETURN json_build_object(
    'cutoff_date', p_cutoff_date,
    'opening_bf', ROUND(p_opening_bf),
    'declared_line_balance', ROUND(p_declared_line_balance),
    'computed_line_balance', ROUND(v_computed_lb),
    'line_balance_difference', ROUND(p_declared_line_balance - v_computed_lb),
    'declared_profit', ROUND(p_declared_profit),
    'computed_profit', ROUND(v_computed_profit),
    'profit_carry_forward', v_carry
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.record_opening_snapshot(uuid, date, numeric, numeric, numeric) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Weekly account sheet
--
-- One row per line of the Owner's weekly book. Four kinds, because those are
-- the four things that book records which the loan sheets do not: what was
-- spent, what an investor was paid, what an investor put in, and what an
-- investor took out. All-or-nothing per upload.
--
-- Superseded by 20260817151333, which declares the migration GUC so the BF
-- pre-flight guards do not refuse backdated history.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.import_weekly_account(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_index INT := 0;
  v_ok INT := 0;
  v_kind text;
  v_date date;
  v_amount numeric;
  v_owner_membership uuid;
  v_investor_id uuid;
  v_investment_id uuid;
  v_person bigint := app.current_person_id();
  v_principal numeric;
  v_interest numeric;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT bm.membership_id INTO v_owner_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
   WHERE bm.business_id = p_business_id AND bm.person_id = b.owner_person_id
   ORDER BY (bm.role = 'Owner') DESC
   LIMIT 1;

  IF v_owner_membership IS NULL THEN
    RAISE EXCEPTION 'This business has no Owner membership to record entries against.' USING ERRCODE = 'P0002';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    v_kind := btrim(COALESCE(v_row ->> 'kind', ''));
    v_date := (v_row ->> 'business_date')::date;
    v_amount := ROUND(COALESCE((v_row ->> 'amount')::numeric, 0));

    IF v_date IS NULL THEN
      RAISE EXCEPTION 'Row %: Date is required.', v_index USING ERRCODE = '23514';
    END IF;
    IF v_amount <= 0 THEN
      RAISE EXCEPTION 'Row %: Amount must be greater than zero.', v_index USING ERRCODE = '23514';
    END IF;

    IF v_kind IN ('Expense', 'Salary') THEN
      PERFORM app.record_expense(
        p_business_id,
        COALESCE(NULLIF(v_row ->> 'category', ''),
                 CASE WHEN v_kind = 'Salary' THEN 'Salary' ELSE 'General' END)::expense_category_enum,
        v_amount, v_owner_membership, v_date, NULLIF(v_row ->> 'remarks', '')
      );

    ELSIF v_kind IN ('Investor Interest', 'Investor Deposit', 'Investor Withdrawal') THEN
      SELECT i.investor_id INTO v_investor_id
        FROM investors i
        JOIN business_members bm ON bm.membership_id = i.membership_id
        JOIN persons p ON p.person_id = bm.person_id
       WHERE bm.business_id = p_business_id AND p.mlid = v_row ->> 'mlid';

      IF v_investor_id IS NULL THEN
        RAISE EXCEPTION 'Row %: no Investor with MLID % in this business.', v_index, v_row ->> 'mlid'
          USING ERRCODE = 'P0002';
      END IF;

      IF v_kind = 'Investor Deposit' THEN
        PERFORM app.record_investment(
          v_investor_id, v_amount,
          COALESCE((v_row ->> 'roi')::numeric, 0),
          COALESCE(NULLIF(v_row ->> 'interest_type', ''), 'Simple')::investment_interest_type_enum,
          v_date
        );
      ELSE
        SELECT investment_id INTO v_investment_id
          FROM investments
         WHERE investor_id = v_investor_id AND business_id = p_business_id
           AND deleted_at IS NULL AND effective_date <= v_date
         ORDER BY (status = 'Active') DESC, effective_date DESC
         LIMIT 1;

        IF v_investment_id IS NULL THEN
          RAISE EXCEPTION 'Row %: investor % has no investment on or before %.',
            v_index, v_row ->> 'mlid', v_date USING ERRCODE = 'P0002';
        END IF;

        IF v_kind = 'Investor Interest' THEN
          PERFORM app.record_investment_interest_payment(
            v_investment_id, v_amount, v_date, NULLIF(v_row ->> 'remarks', '')
          );
        ELSE
          v_interest := ROUND(COALESCE((v_row ->> 'interest_portion')::numeric, 0));
          v_principal := v_amount - v_interest;
          IF v_principal < 0 THEN
            RAISE EXCEPTION 'Row %: the interest portion cannot exceed the withdrawal.', v_index
              USING ERRCODE = '23514';
          END IF;

          INSERT INTO investment_withdrawals (
            investment_id, withdrawal_type, amount, principal_portion, interest_portion,
            business_date, approved_by_person_id, remarks
          ) VALUES (
            v_investment_id,
            CASE WHEN v_principal = 0 THEN 'Interest Only'
                 WHEN v_interest = 0 THEN 'Principal Partial'
                 ELSE 'Principal + Interest' END::withdrawal_type_enum,
            v_amount, v_principal, v_interest, v_date, v_person, NULLIF(v_row ->> 'remarks', '')
          );

          UPDATE investments
             SET principal_amount = GREATEST(principal_amount - v_principal, 0)
           WHERE investment_id = v_investment_id;
        END IF;
      END IF;

    ELSE
      RAISE EXCEPTION 'Row %: unknown entry type "%". Use Expense, Salary, Investor Interest, Investor Deposit or Investor Withdrawal.',
        v_index, v_kind USING ERRCODE = '23514';
    END IF;

    v_ok := v_ok + 1;
  END LOOP;

  RETURN json_build_object('imported', v_ok, 'total', v_index);
END;
$$;

GRANT EXECUTE ON FUNCTION app.import_weekly_account(uuid, json) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Profit share accrues at the investment's own ROI until it is paid.
-- Zero if declared and paid on the same day - no day, no accrual.
-- ROI is Rupees per 100 per MONTH; daily is that over a 30-day month.
--
-- Superseded by 20260817151200: ROUND() was handed a json ->> text operand.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.profit_share_accrued(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inv RECORD;
  v_days INT;
  v_base numeric;
BEGIN
  SELECT i.*, b.business_id AS b_id INTO v_inv
    FROM investments i JOIN businesses b ON b.business_id = i.business_id
   WHERE i.investment_id = p_investment_id AND i.deleted_at IS NULL;

  IF v_inv IS NULL THEN
    RETURN 0;
  END IF;
  IF NOT app.is_owner(v_inv.b_id) AND NOT app.is_active_investor(v_inv.b_id) THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;
  IF v_inv.profit_share_percent IS NULL OR v_inv.profit_share_effective_date IS NULL THEN
    RETURN 0;
  END IF;

  v_days := GREATEST(p_as_of - v_inv.profit_share_effective_date, 0);
  IF v_days = 0 THEN
    RETURN 0;
  END IF;

  v_base := ROUND(
    app.migration_profit_summary(v_inv.b_id, p_as_of)::json ->> 'profit'
  )::numeric * v_inv.profit_share_percent / 100;

  RETURN CEIL(v_base * (v_inv.roi_rate / 100) / 30 * v_days);
END;
$$;

GRANT EXECUTE ON FUNCTION app.profit_share_accrued(uuid, date) TO authenticated, service_role;

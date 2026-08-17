-- Two holes found reviewing part B against the rest of the app.
--
-- 1. The lock. bulk_import_identities and migrate_loan both refuse to run once
--    businesses.migration_locked is true; the weekly-account, attendance and
--    snapshot imports did not. That matters more for the weekly sheet than the
--    others, because it is the one that sets app.migration_import and so skips
--    the BF pre-flight guards - post-lock it would have been a way to write
--    unguarded backdated expenses forever.
--
-- 2. A withdrawal that takes the last of the principal has to close the
--    investment. There is no trigger for it (the schema comment says so
--    explicitly, and investor_state.dart's approveWithdrawalRequest does it in
--    the app layer); the migration path left the investment Active with a zero
--    principal, which is a state nothing else in the app produces.
CREATE OR REPLACE FUNCTION app.migration_assert_open(p_business_id uuid) RETURNS void
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_locked BOOLEAN;
BEGIN
  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_assert_open(uuid) TO authenticated, service_role;

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
  PERFORM app.migration_assert_open(p_business_id);

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
  v_left numeric;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  PERFORM app.migration_assert_open(p_business_id);

  SELECT bm.membership_id INTO v_owner_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
   WHERE bm.business_id = p_business_id AND bm.person_id = b.owner_person_id
   ORDER BY (bm.role = 'Owner') DESC
   LIMIT 1;

  IF v_owner_membership IS NULL THEN
    RAISE EXCEPTION 'This business has no Owner membership to record entries against.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.migration_import', 'on', true);

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

          -- principal_amount is the single combined running balance, and
          -- nothing closes an investment for you - same app-layer rule
          -- investor_state.dart's approveWithdrawalRequest follows.
          SELECT GREATEST(principal_amount - v_principal, 0) INTO v_left
            FROM investments WHERE investment_id = v_investment_id FOR UPDATE;

          UPDATE investments
             SET principal_amount = v_left,
                 status = CASE WHEN v_left <= 0 THEN 'Closed'::investment_status_enum ELSE status END
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
  PERFORM app.migration_assert_open(p_business_id);

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

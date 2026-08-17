-- A weekly account sheet is history: that money moved months or years ago.
-- The BF pre-flight guards exist to stop a LIVE overspend, and applied to a
-- backdated entry they simply refuse the truth - an Owner whose book records a
-- 3,000 salary in week 4 cannot be told there is no cash for it today.
--
-- The guard is skipped only while app.migration_import_active(), which is a
-- transaction-local GUC that only the migration RPCs set. The running-total
-- decrement is skipped with it: BF is derived (app.recompute_business_bf), the
-- expenses trigger rebuilds the day ledger, and a manual decrement on top of a
-- recompute would double count.
CREATE OR REPLACE FUNCTION app.record_expense(
  p_business_id uuid,
  p_category expense_category_enum,
  p_amount numeric,
  p_membership_id uuid,
  p_business_date date,
  p_remarks text DEFAULT NULL::text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_expense_id UUID;
  v_role business_member_role_enum;
  v_owner_bf DECIMAL(14,0);
  v_assignment_id UUID;
  v_agent_bf DECIMAL(14,0);
  v_migrating BOOLEAN := app.migration_import_active();
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(p_membership_id, 'can_record_expenses', p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record expenses in this business' USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Expense amount must be positive' USING ERRCODE = '23514';
  END IF;

  SELECT role INTO v_role FROM business_members WHERE membership_id = p_membership_id;
  IF v_role = 'Owner' THEN
    IF NOT v_migrating THEN
      SELECT owner_bf_balance INTO v_owner_bf
      FROM businesses WHERE business_id = p_business_id FOR UPDATE;
      IF v_owner_bf < p_amount THEN
        RAISE EXCEPTION 'Owner BF is only %, cannot pay a % expense', v_owner_bf, p_amount USING ERRCODE = '23514';
      END IF;
      UPDATE businesses SET owner_bf_balance = owner_bf_balance - p_amount
      WHERE business_id = p_business_id;
    END IF;
  ELSIF v_role = 'Agent' THEN
    IF NOT v_migrating THEN
      SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_agent_bf
      FROM agent_bf_assignments
      WHERE membership_id = p_membership_id
      ORDER BY business_date DESC NULLS LAST
      LIMIT 1
      FOR UPDATE;
      IF v_assignment_id IS NULL THEN
        RAISE EXCEPTION 'No BF assignment for this agent - the Owner must grant BF first' USING ERRCODE = 'P0002';
      END IF;
      IF v_agent_bf < p_amount THEN
        RAISE EXCEPTION 'Agent BF is only %, cannot pay a % expense', v_agent_bf, p_amount USING ERRCODE = '23514';
      END IF;
      UPDATE agent_bf_assignments
      SET agent_bf_current = agent_bf_current - p_amount, updated_at = now()
      WHERE assignment_id = v_assignment_id;
    END IF;
  ELSE
    RAISE EXCEPTION 'Expenses can only be paid by the Owner or an Agent' USING ERRCODE = '42501';
  END IF;

  INSERT INTO expenses (business_id, category, amount, recorded_by_membership_id, business_date, remarks)
  VALUES (p_business_id, p_category, p_amount, p_membership_id, p_business_date, p_remarks)
  RETURNING expense_id INTO v_expense_id;

  RETURN v_expense_id;
END;
$$;

-- The weekly sheet declares itself a migration import for the same reason the
-- identity import does.
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

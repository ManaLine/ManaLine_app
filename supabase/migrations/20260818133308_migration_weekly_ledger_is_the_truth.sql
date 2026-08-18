-- The weekly account sheet becomes the truth for a migrated period.
--
-- Validated against the real 2026 book: 12 weeks, 2-1-26 to 20-3-26, every week
-- satisfying
--   closing = opening + collection + interest + fee + investor_in
--           - loans_gross - expenses - investor_out
-- every closing equal to the next opening, and a final BF of Rs 100. Deriving
-- that same BF from the imported transactions produced Rs 4,350, which is why
-- this exists: for dates inside the migrated span the sheet is imported, not
-- recomputed.
--
-- A "week" is the SCHEDULE'S working days ending on the account date - this
-- business works two days a week and submits the account on the second. It is
-- not a 7-day calendar window, and the importer never re-dates a row to make
-- one fit.

ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS migrated_through_date date;

COMMENT ON COLUMN public.businesses.migrated_through_date IS
  'Last account date imported from a weekly book. day_ledger rows on or before this are declared, not derived.';

CREATE TABLE IF NOT EXISTS public.migration_weeks (
  week_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id           uuid NOT NULL REFERENCES public.businesses(business_id) ON DELETE CASCADE,
  account_date          date NOT NULL,
  opening_bf            numeric(14,0) NOT NULL,
  collection            numeric(14,0) NOT NULL DEFAULT 0,
  interest              numeric(14,0) NOT NULL DEFAULT 0,
  fee                   numeric(14,0) NOT NULL DEFAULT 0,
  investor_in           numeric(14,0) NOT NULL DEFAULT 0,
  investor_in_interest  numeric(14,0) NOT NULL DEFAULT 0,
  loans_gross_out       numeric(14,0) NOT NULL DEFAULT 0,
  expenses              numeric(14,0) NOT NULL DEFAULT 0,
  investor_out          numeric(14,0) NOT NULL DEFAULT 0,
  investor_out_interest numeric(14,0) NOT NULL DEFAULT 0,
  cheeti                numeric(14,0) NOT NULL DEFAULT 0,
  closing_bf            numeric(14,0) NOT NULL,
  expense_lines         json,
  created_at            timestamp without time zone NOT NULL DEFAULT now(),
  UNIQUE (business_id, account_date)
);

ALTER TABLE public.migration_weeks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS migration_weeks_owner ON public.migration_weeks;
CREATE POLICY migration_weeks_owner ON public.migration_weeks
  FOR ALL USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.migration_weeks TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The freeze
--
-- Without this, importing a single backdated collection fires
-- tg_recompute_day_ledger, which rebuilds that day from transactions and
-- overwrites the declared closing - and the whole chain after it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_day_ledger(p_business_id uuid, p_business_date date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_frozen_through DATE;
    v_opening      DECIMAL(14,0);
    v_collections  DECIMAL(14,0);
    v_loans        DECIMAL(14,0);
    v_deposits     DECIMAL(14,0);
    v_withdrawals  DECIMAL(14,0);
    v_expenses     DECIMAL(14,0);
    v_cheti_paid   DECIMAL(14,0);
    v_cheti_recv   DECIMAL(14,0);
    v_short        DECIMAL(14,0);
    v_excess       DECIMAL(14,0);
    v_closing      DECIMAL(14,0);
BEGIN
    SELECT migrated_through_date INTO v_frozen_through
      FROM businesses WHERE business_id = p_business_id;

    -- Declared, not derived. The first live day after the span opens on the
    -- last migrated closing, so the chain continues without a seam.
    IF v_frozen_through IS NOT NULL AND p_business_date <= v_frozen_through THEN
        RETURN;
    END IF;

    SELECT closing_balance INTO v_opening
      FROM day_ledger
     WHERE business_id = p_business_id
       AND business_date < p_business_date
     ORDER BY business_date DESC
     LIMIT 1;

    IF v_opening IS NULL THEN
        SELECT COALESCE(opening_bf_declared_amount, 0) INTO v_opening
          FROM businesses WHERE business_id = p_business_id;
    END IF;
    v_opening := COALESCE(v_opening, 0);

    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE l.business_id = p_business_id
       AND c.business_date = p_business_date
       AND c.deleted_at IS NULL
       AND l.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount_given), 0) INTO v_loans
      FROM loans
     WHERE business_id = p_business_id
       AND issue_business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(principal_amount), 0) INTO v_deposits
      FROM investments
     WHERE business_id = p_business_id
       AND effective_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(w.amount), 0) INTO v_withdrawals
      FROM investment_withdrawals w
      JOIN investments i ON i.investment_id = w.investment_id
     WHERE i.business_id = p_business_id
       AND w.business_date = p_business_date
       AND w.deleted_at IS NULL
       AND i.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount), 0) INTO v_expenses
      FROM expenses
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(net_paid), 0) INTO v_cheti_paid
      FROM cheti_payments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(availed_amount), 0) INTO v_cheti_recv
      FROM chetis
     WHERE business_id = p_business_id
       AND availed_date = p_business_date
       AND NOT availed_pre_migration
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Short'), 0),
           COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Excess'), 0)
      INTO v_short, v_excess
      FROM settlement_adjustments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    v_closing := v_opening + v_collections - v_loans + v_deposits
               - v_withdrawals - v_expenses - v_cheti_paid + v_cheti_recv;

    INSERT INTO day_ledger (
        business_id, business_date, opening_balance, total_collections,
        total_loan_distribution, investor_deposits, investor_withdrawals,
        total_expenses, cheti_paid, cheti_received, short_amount,
        excess_amount, closing_balance
    ) VALUES (
        p_business_id, p_business_date, v_opening, v_collections,
        v_loans, v_deposits, v_withdrawals,
        v_expenses, v_cheti_paid, v_cheti_recv, v_short,
        v_excess, v_closing
    )
    ON CONFLICT (business_id, business_date) DO UPDATE SET
        opening_balance         = EXCLUDED.opening_balance,
        total_collections       = EXCLUDED.total_collections,
        total_loan_distribution = EXCLUDED.total_loan_distribution,
        investor_deposits       = EXCLUDED.investor_deposits,
        investor_withdrawals    = EXCLUDED.investor_withdrawals,
        total_expenses          = EXCLUDED.total_expenses,
        cheti_paid              = EXCLUDED.cheti_paid,
        cheti_received          = EXCLUDED.cheti_received,
        short_amount            = EXCLUDED.short_amount,
        excess_amount           = EXCLUDED.excess_amount,
        closing_balance         = EXCLUDED.closing_balance;
END;
$$;

-- ---------------------------------------------------------------------------
-- The weekly importer
--
-- Writes migration_weeks and one declared day_ledger row per account date, and
-- NOTHING else. It deliberately does not create expense, investment or
-- withdrawal rows: the Investors page already creates the investments and the
-- Customers page the loans, so materialising them here too would double count
-- the same money. The week's own figures live in migration_weeks and are what
-- app.migration_profit_summary reads for the migrated span.
--
-- NOTE: the `expenses_total` key test was applied here as `v_row ? '...'` and
-- corrected in 20260818133559 - `?` is a jsonb operator and p_rows is json.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.import_weekly_account(p_business_id uuid, p_rows json)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_line json;
  v_index INT := 0;
  v_date date;
  v_open numeric; v_coll numeric; v_int numeric; v_fee numeric;
  v_in numeric; v_in_int numeric; v_out numeric; v_out_int numeric;
  v_loans numeric; v_exp numeric; v_cheeti numeric; v_close numeric;
  v_calc numeric;
  v_prev_close numeric := NULL;
  v_prev_date date := NULL;
  v_first_open numeric := NULL;
  v_first_date date := NULL;
  v_last_close numeric := NULL;
  v_last_date date := NULL;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  PERFORM app.migration_assert_open(p_business_id);

  PERFORM set_config('app.migration_import', 'on', true);

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;

    v_date  := (v_row ->> 'account_date')::date;
    IF v_date IS NULL THEN
      RAISE EXCEPTION 'Week %: the account date is required.', v_index USING ERRCODE = '23514';
    END IF;
    IF v_prev_date IS NOT NULL AND v_date <= v_prev_date THEN
      RAISE EXCEPTION 'Week % (%): the weeks must be in date order.', v_index, v_date
        USING ERRCODE = '23514';
    END IF;

    v_open    := ROUND(COALESCE((v_row ->> 'opening_bf')::numeric, 0));
    v_coll    := ROUND(COALESCE((v_row ->> 'collection')::numeric, 0));
    v_int     := ROUND(COALESCE((v_row ->> 'interest')::numeric, 0));
    v_fee     := ROUND(COALESCE((v_row ->> 'fee')::numeric, 0));
    v_in      := ROUND(COALESCE((v_row ->> 'investor_in')::numeric, 0));
    v_in_int  := ROUND(COALESCE((v_row ->> 'investor_in_interest')::numeric, 0));
    v_out     := ROUND(COALESCE((v_row ->> 'investor_out')::numeric, 0));
    v_out_int := ROUND(COALESCE((v_row ->> 'investor_out_interest')::numeric, 0));
    v_loans   := ROUND(COALESCE((v_row ->> 'loans_gross_out')::numeric, 0));
    v_cheeti  := ROUND(COALESCE((v_row ->> 'cheeti')::numeric, 0));
    v_close   := ROUND(COALESCE((v_row ->> 'closing_bf')::numeric, 0));

    v_exp := 0;
    FOR v_line IN SELECT * FROM json_array_elements(COALESCE(v_row -> 'expenses', '[]'::json)) LOOP
      v_exp := v_exp + ROUND(COALESCE((v_line ->> 'amount')::numeric, 0));
    END LOOP;
    IF (v_row -> 'expenses_total') IS NOT NULL THEN
      IF ROUND((v_row ->> 'expenses_total')::numeric) <> v_exp THEN
        RAISE EXCEPTION 'Week % (%): the expense lines add up to % but the total says %.',
          v_index, v_date, v_exp, ROUND((v_row ->> 'expenses_total')::numeric)
          USING ERRCODE = '23514';
      END IF;
    END IF;

    -- The identity. Loans go out at GROSS repayment and the withheld interest
    -- and fee come back in on the same line, which is how the book balances.
    v_calc := v_open + v_coll + v_int + v_fee + v_in - v_loans - v_exp - v_out - v_cheeti;
    IF v_calc <> v_close THEN
      RAISE EXCEPTION 'Week % (%): this week does not balance. Opening % + collection % + interest % + fee % + investor in % - loans % - expenses % - investor out % - cheeti % = %, but the closing BF says %.',
        v_index, v_date, v_open, v_coll, v_int, v_fee, v_in, v_loans, v_exp, v_out, v_cheeti, v_calc, v_close
        USING ERRCODE = '23514';
    END IF;

    -- One week's closing is the next week's opening. A break means a week is
    -- missing or mistyped, and importing it would carry the error forward.
    IF v_prev_close IS NOT NULL AND v_open <> v_prev_close THEN
      RAISE EXCEPTION 'Week % (%): opens at % but the previous week (%) closed at %.',
        v_index, v_date, v_open, v_prev_date, v_prev_close USING ERRCODE = '23514';
    END IF;

    INSERT INTO migration_weeks (
      business_id, account_date, opening_bf, collection, interest, fee,
      investor_in, investor_in_interest, loans_gross_out, expenses,
      investor_out, investor_out_interest, cheeti, closing_bf, expense_lines
    ) VALUES (
      p_business_id, v_date, v_open, v_coll, v_int, v_fee,
      v_in, v_in_int, v_loans, v_exp,
      v_out, v_out_int, v_cheeti, v_close, v_row -> 'expenses'
    )
    ON CONFLICT (business_id, account_date) DO UPDATE SET
      opening_bf = EXCLUDED.opening_bf, collection = EXCLUDED.collection,
      interest = EXCLUDED.interest, fee = EXCLUDED.fee,
      investor_in = EXCLUDED.investor_in, investor_in_interest = EXCLUDED.investor_in_interest,
      loans_gross_out = EXCLUDED.loans_gross_out, expenses = EXCLUDED.expenses,
      investor_out = EXCLUDED.investor_out, investor_out_interest = EXCLUDED.investor_out_interest,
      cheeti = EXCLUDED.cheeti, closing_bf = EXCLUDED.closing_bf,
      expense_lines = EXCLUDED.expense_lines;

    -- The declared day. total_loan_distribution carries the book's GROSS
    -- figure, not amount_given: inside the span this row is a record of what
    -- the book said, not a recomputation of it.
    INSERT INTO day_ledger (
      business_id, business_date, opening_balance, total_collections,
      total_loan_distribution, investor_deposits, investor_withdrawals,
      total_expenses, cheti_paid, cheti_received, short_amount, excess_amount,
      closing_balance
    ) VALUES (
      p_business_id, v_date, v_open, v_coll + v_int + v_fee,
      v_loans, v_in, v_out, v_exp, v_cheeti, 0, 0, 0, v_close
    )
    ON CONFLICT (business_id, business_date) DO UPDATE SET
      opening_balance = EXCLUDED.opening_balance,
      total_collections = EXCLUDED.total_collections,
      total_loan_distribution = EXCLUDED.total_loan_distribution,
      investor_deposits = EXCLUDED.investor_deposits,
      investor_withdrawals = EXCLUDED.investor_withdrawals,
      total_expenses = EXCLUDED.total_expenses,
      cheti_paid = EXCLUDED.cheti_paid,
      closing_balance = EXCLUDED.closing_balance;

    IF v_first_date IS NULL THEN
      v_first_date := v_date; v_first_open := v_open;
    END IF;
    v_prev_close := v_close; v_prev_date := v_date;
    v_last_close := v_close; v_last_date := v_date;
  END LOOP;

  IF v_index = 0 THEN
    RAISE EXCEPTION 'There are no weeks in this file.' USING ERRCODE = '23514';
  END IF;

  UPDATE businesses
     SET migrated_through_date = GREATEST(COALESCE(migrated_through_date, v_last_date), v_last_date),
         opening_bf_declared_amount = COALESCE(opening_bf_declared_amount, v_first_open),
         opening_bf_declared_on = COALESCE(opening_bf_declared_on, v_first_date),
         business_started_at = COALESCE(business_started_at, v_first_date::timestamp),
         owner_bf_balance = v_last_close
   WHERE business_id = p_business_id;

  RETURN json_build_object(
    'weeks', v_index,
    'from', v_first_date,
    'through', v_last_date,
    'opening_bf', v_first_open,
    'closing_bf', v_last_close
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.import_weekly_account(uuid, json) TO authenticated, service_role;

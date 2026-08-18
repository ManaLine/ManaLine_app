-- Phase 2: profit from the book, the shareholder list, and the two loan-level
-- rules the customers grid needs.

-- ---------------------------------------------------------------------------
-- Profit, sourced the way the Owner's own account sheet sources it
--
-- Interest comes from the loans, because loan-level interest reconciles to the
-- book EXACTLY (720,600 on the 2026 book). Fee does NOT - the book's fee column
-- is 52,900 against 64,900 on the loans, a 12,000 difference that is two fees
-- the Owner never entered - so fee, expenses and investor interest come from
-- the weekly sheet for the migrated span. Both fee figures are returned so the
-- difference is reported rather than reconciled away.
--
-- Target on the 2026 book: 720,600 + 52,900 - 184,500 - (77,332 - 7,750)
--                        = 519,418, which is the PROFIT cell in their sheet.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.migration_profit_summary(
  p_business_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_span date;
  v_interest numeric := 0;
  v_fee_loans numeric := 0;
  v_fee_book numeric := 0;
  v_expenses numeric := 0;
  v_inv_interest numeric := 0;
  v_wd_interest numeric := 0;
  v_line_balance numeric := 0;
  v_collections numeric := 0;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(migrated_through_date, '-infinity'::date) INTO v_span
    FROM businesses WHERE business_id = p_business_id;

  SELECT COALESCE(SUM(l.interest_amount), 0), COALESCE(SUM(l.processing_fee), 0),
         COALESCE(SUM(CASE WHEN l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')
                           THEN l.remaining_balance ELSE 0 END), 0)
    INTO v_interest, v_fee_loans, v_line_balance
    FROM loans l
   WHERE l.business_id = p_business_id AND l.deleted_at IS NULL
     AND l.issue_business_date <= p_as_of;

  -- Inside the span the book states the figure; outside it the tables do.
  SELECT COALESCE(SUM(w.fee), 0), COALESCE(SUM(w.expenses), 0),
         COALESCE(SUM(w.investor_in_interest), 0), COALESCE(SUM(w.investor_out_interest), 0)
    INTO v_fee_book, v_expenses, v_inv_interest, v_wd_interest
    FROM migration_weeks w
   WHERE w.business_id = p_business_id AND w.account_date <= p_as_of;

  v_fee_book := v_fee_book + COALESCE((
    SELECT SUM(l.processing_fee) FROM loans l
     WHERE l.business_id = p_business_id AND l.deleted_at IS NULL
       AND l.issue_business_date > v_span AND l.issue_business_date <= p_as_of), 0);

  v_expenses := v_expenses + COALESCE((
    SELECT SUM(e.amount) FROM expenses e
     WHERE e.business_id = p_business_id AND e.deleted_at IS NULL
       AND e.business_date > v_span AND e.business_date <= p_as_of), 0);

  v_inv_interest := v_inv_interest + COALESCE((
    SELECT SUM(il.amount) FROM investment_interest_ledger il
     JOIN investments i ON i.investment_id = il.investment_id
    WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
      AND il.entry_type = 'Payment'
      AND il.business_date > v_span AND il.business_date <= p_as_of), 0);

  v_wd_interest := v_wd_interest + COALESCE((
    SELECT SUM(w.interest_portion) FROM investment_withdrawals w
     JOIN investments i ON i.investment_id = w.investment_id
    WHERE i.business_id = p_business_id AND i.deleted_at IS NULL AND w.deleted_at IS NULL
      AND w.business_date > v_span AND w.business_date <= p_as_of), 0);

  SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
    FROM collections c
    JOIN loans l ON l.loan_id = c.loan_id
   WHERE l.business_id = p_business_id AND c.deleted_at IS NULL AND c.business_date <= p_as_of;

  RETURN json_build_object(
    'as_of', p_as_of,
    'migrated_through', NULLIF(v_span, '-infinity'::date),
    'interest', v_interest,
    'fee', v_fee_book,
    'fee_on_loans', v_fee_loans,
    'fee_difference', v_fee_loans - v_fee_book,
    'expenses', v_expenses,
    'investor_interest', v_inv_interest,
    'withdrawal_interest', v_wd_interest,
    'profit', v_interest + v_fee_book - v_expenses - (v_inv_interest - v_wd_interest),
    'line_balance', v_line_balance,
    'collections', v_collections
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Shareholders
--
-- Separate from investors and agents on purpose: in the real book, 2 of the 5
-- profit shareholders hold no investment at all. A share accrues at the
-- investment ROI from the declaration date until it is paid, and is 0 when both
-- fall on the same day.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.migration_shareholders (
  shareholder_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id      uuid NOT NULL REFERENCES public.businesses(business_id) ON DELETE CASCADE,
  person_id        bigint REFERENCES public.persons(person_id),
  full_name        varchar(150) NOT NULL,
  share_percent    numeric(5,2) NOT NULL CHECK (share_percent > 0 AND share_percent <= 100),
  declared_on      date NOT NULL,
  declared_profit  numeric(14,0) NOT NULL,
  share_amount     numeric(14,0) NOT NULL,
  roi_rate         numeric(6,3),
  paid_on          date,
  amount_received  numeric(14,0),
  created_at       timestamp without time zone NOT NULL DEFAULT now(),
  UNIQUE (business_id, full_name, declared_on)
);

ALTER TABLE public.migration_shareholders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS migration_shareholders_owner ON public.migration_shareholders;
CREATE POLICY migration_shareholders_owner ON public.migration_shareholders
  FOR ALL USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.migration_shareholders TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app.import_shareholders(
  p_business_id uuid,
  p_declared_on date,
  p_declared_profit numeric,
  p_rows json
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row json;
  v_index INT := 0;
  v_pct_total numeric := 0;
  v_amount numeric;
  v_name text;
  v_accrued numeric;
  v_out json[] := '{}';
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  PERFORM app.migration_assert_open(p_business_id);

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    v_name := NULLIF(btrim(COALESCE(v_row ->> 'full_name', '')), '');
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Row %: the shareholder name is required.', v_index USING ERRCODE = '23514';
    END IF;

    v_pct_total := v_pct_total + COALESCE((v_row ->> 'share_percent')::numeric, 0);
    v_amount := ROUND(COALESCE(
      (v_row ->> 'share_amount')::numeric,
      p_declared_profit * (v_row ->> 'share_percent')::numeric / 100));

    -- Same day declared and paid is no accrual at all.
    v_accrued := CASE
      WHEN (v_row ->> 'paid_on') IS NULL OR (v_row ->> 'roi_rate') IS NULL THEN NULL
      ELSE CEIL(v_amount * ((v_row ->> 'roi_rate')::numeric / 100) / 30
                * GREATEST((v_row ->> 'paid_on')::date - p_declared_on, 0))
    END;

    INSERT INTO migration_shareholders (
      business_id, person_id, full_name, share_percent, declared_on,
      declared_profit, share_amount, roi_rate, paid_on, amount_received
    ) VALUES (
      p_business_id, (v_row ->> 'person_id')::bigint, v_name,
      (v_row ->> 'share_percent')::numeric, p_declared_on,
      ROUND(p_declared_profit), v_amount,
      (v_row ->> 'roi_rate')::numeric,
      (v_row ->> 'paid_on')::date,
      ROUND((v_row ->> 'amount_received')::numeric)
    )
    ON CONFLICT (business_id, full_name, declared_on) DO UPDATE SET
      share_percent = EXCLUDED.share_percent,
      declared_profit = EXCLUDED.declared_profit,
      share_amount = EXCLUDED.share_amount,
      roi_rate = EXCLUDED.roi_rate,
      paid_on = EXCLUDED.paid_on,
      amount_received = EXCLUDED.amount_received,
      person_id = EXCLUDED.person_id;

    v_out := v_out || json_build_object(
      'row', v_index, 'full_name', v_name, 'share_amount', v_amount,
      'accrued_to_paid_on', v_accrued,
      'amount_received', ROUND((v_row ->> 'amount_received')::numeric)
    );
  END LOOP;

  IF v_pct_total > 100 THEN
    RAISE EXCEPTION 'The shares add up to %%%, which is more than the whole profit.', v_pct_total
      USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object(
    'shareholders', array_to_json(v_out),
    'percent_total', v_pct_total,
    'declared_profit', ROUND(p_declared_profit),
    'computed_profit', (app.migration_profit_summary(p_business_id, p_declared_on) ->> 'profit')::numeric,
    'carry_forward', ROUND(p_declared_profit)
      - (app.migration_profit_summary(p_business_id, p_declared_on) ->> 'profit')::numeric
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.import_shareholders(uuid, date, numeric, json) TO authenticated, service_role;

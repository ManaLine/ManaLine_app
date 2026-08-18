-- How this business actually computes interest over a period, verified against
-- the calculator they use (JMK Easy Apps, "Village Interest Calculator") on
-- the Owner's own handset:
--
--   75,000 @ 1.5, 20-03-2026 -> 31-03-2026  = 0m 11d -> 413
--   75,000 @ 1.5, 20-03-2026 -> 23-05-2026  = 2m  3d -> 2,363
--
-- WHOLE CALENDAR MONTHS first, then the leftover days at one thirtieth of the
-- monthly rate. Not days/30 throughout: that gives 2,400 for the second case
-- and is what this codebase had. The two agree only inside a single month,
-- which is why an 11-day test could not tell them apart.
--
-- ROI stays Rupees per 100 per MONTH, and money still rounds up to whole
-- rupees (both examples land on .5 and the app rounds them up).
CREATE OR REPLACE FUNCTION app.mana_interest(
  p_principal numeric,
  p_roi_rate numeric,
  p_from date,
  p_to date
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE
  v_age    interval;
  v_months int;
  v_days   int;
  v_month  numeric;
BEGIN
  IF p_principal IS NULL OR p_roi_rate IS NULL OR p_from IS NULL OR p_to IS NULL THEN
    RETURN 0;
  END IF;
  IF p_to <= p_from THEN
    RETURN 0;   -- declared and paid the same day is no interest at all
  END IF;

  v_age    := age(p_to::timestamp, p_from::timestamp);
  v_months := EXTRACT(YEAR FROM v_age)::int * 12 + EXTRACT(MONTH FROM v_age)::int;
  v_days   := EXTRACT(DAY FROM v_age)::int;
  v_month  := p_principal * p_roi_rate / 100;

  RETURN CEIL(v_month * v_months + v_month / 30 * v_days);
END;
$$;

GRANT EXECUTE ON FUNCTION app.mana_interest(numeric, numeric, date, date) TO authenticated, anon, service_role;

-- Profit share accrues the same way as any other money here.
CREATE OR REPLACE FUNCTION app.profit_share_accrued(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inv RECORD;
  v_profit numeric;
  v_base numeric;
BEGIN
  SELECT i.investment_id, i.business_id, i.roi_rate,
         i.profit_share_percent, i.profit_share_effective_date
    INTO v_inv
    FROM investments i
   WHERE i.investment_id = p_investment_id AND i.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF NOT app.is_owner(v_inv.business_id) AND NOT app.is_active_investor(v_inv.business_id) THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;
  IF v_inv.profit_share_percent IS NULL OR v_inv.profit_share_effective_date IS NULL THEN
    RETURN 0;
  END IF;

  v_profit := (app.migration_profit_summary(v_inv.business_id, p_as_of) ->> 'profit')::numeric;
  v_base := v_profit * v_inv.profit_share_percent / 100;
  IF v_base <= 0 THEN
    RETURN 0;
  END IF;

  RETURN app.mana_interest(v_base, v_inv.roi_rate,
                           v_inv.profit_share_effective_date, p_as_of);
END;
$$;

-- And the shareholder import, which is where the Owner sees it first.
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
  v_computed numeric;
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

    -- Whole months, then leftover days. Same rule the Owner's own calculator
    -- applies, and 0 when declared and paid fall on the same day.
    v_accrued := CASE
      WHEN (v_row ->> 'paid_on') IS NULL OR (v_row ->> 'roi_rate') IS NULL THEN NULL
      ELSE app.mana_interest(v_amount, (v_row ->> 'roi_rate')::numeric,
                             p_declared_on, (v_row ->> 'paid_on')::date)
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
      'expected_total', CASE WHEN v_accrued IS NULL THEN NULL ELSE v_amount + v_accrued END,
      'amount_received', ROUND((v_row ->> 'amount_received')::numeric),
      -- Reported, never reconciled away: a hand-entered payout that does not
      -- match the rule is the Owner's to explain, not this function's to hide.
      'difference', CASE
        WHEN v_accrued IS NULL OR (v_row ->> 'amount_received') IS NULL THEN NULL
        ELSE ROUND((v_row ->> 'amount_received')::numeric) - (v_amount + v_accrued)
      END
    );
  END LOOP;

  IF v_pct_total > 100 THEN
    RAISE EXCEPTION 'The shares add up to %%%, which is more than the whole profit.', v_pct_total
      USING ERRCODE = '23514';
  END IF;

  v_computed := (app.migration_profit_summary(p_business_id, p_declared_on) ->> 'profit')::numeric;

  RETURN json_build_object(
    'shareholders', array_to_json(v_out),
    'percent_total', v_pct_total,
    'declared_profit', ROUND(p_declared_profit),
    'computed_profit', v_computed,
    'carry_forward', ROUND(p_declared_profit) - v_computed
  );
END;
$$;

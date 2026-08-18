-- Investor interest accrued the same wrong way the profit shares did: daily
-- rate times days, throughout. The Owner's book does whole calendar months
-- first, then the leftover days at a thirtieth of the monthly rate, and its
-- investor-interest column proves it:
--
--   KBR    1,000,000 @1.5  02-01 -> 20-03  2m18d   39,000   (days/30: 38,500)
--   KSMR      26,000 @1.5  16-01 -> 20-03  2m 4d      832   (days/30:    823)
--   KSMR     500,000 @1.5  06-02 -> 20-03  1m14d   11,000   (days/30: 10,750)
--   TSR    1,000,000 @1.5  20-02 -> 20-03  1m 0d   15,000   (days/30: 14,500)
--
-- Four of five to the rupee. This feeds app.business_profit, the investor
-- balances and IW-003, so it was drifting everywhere at once.
--
-- The YEARLY COMPOUND step is deliberately left on actual calendar days
-- (365/366). That is a separately locked convention - see CLAUDE.md, "Yearly
-- compounding uses actual calendar days, not hardcoded 360" - and no evidence
-- in the book contradicts it, so it is not being changed on the strength of
-- simple-interest data.
--
-- Column names are preserved exactly; only the accrual arithmetic changes.
CREATE OR REPLACE FUNCTION app.investment_interest_snapshot(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
) RETURNS TABLE(
  principal numeric,
  original_principal numeric,
  roi_rate numeric,
  interest_type text,
  daily_interest numeric,
  days_elapsed integer,
  accrued_interest numeric,
  interest_paid_to_date numeric,
  total_interest_earned numeric,
  available_balance numeric,
  pending_compounding_events integer,
  last_compounding_date date
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inv RECORD;
  v_principal   numeric;
  v_anchor      date;
  v_base        date;
  v_daily       numeric;
  v_year_int    numeric;
  v_year_days   integer;
  v_days        integer;
  v_accrued     numeric;
  v_paid        numeric;
  v_pending     integer := 0;
BEGIN
  SELECT i.* INTO v_inv
  FROM investments i WHERE i.investment_id = p_investment_id;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (app.is_own_investment_row(p_investment_id) OR app.is_owner(v_inv.business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;

  v_principal := v_inv.principal_amount;

  IF v_inv.interest_type = 'Yearly Compound' THEN
    v_anchor := COALESCE(v_inv.last_compounding_date, v_inv.effective_date);
    WHILE (v_anchor + INTERVAL '12 months')::date <= p_as_of LOOP
      v_year_days := (v_anchor + INTERVAL '12 months')::date - v_anchor;
      v_anchor   := (v_anchor + INTERVAL '12 months')::date;
      v_daily    := app.investment_daily_interest(v_principal, v_inv.roi_rate);
      v_year_int := CEIL(v_daily * v_year_days);
      v_principal := v_principal + v_year_int;
      v_pending  := v_pending + 1;
    END LOOP;
  ELSE
    v_anchor := v_inv.effective_date;
  END IF;

  v_base := GREATEST(v_anchor, COALESCE(v_inv.last_interest_payment_date, v_anchor));
  v_days := GREATEST(p_as_of - v_base, 0);
  v_daily := app.investment_daily_interest(v_principal, v_inv.roi_rate);

  -- Whole months, then the leftover days. days_elapsed stays the plain day
  -- count because that is what the screens label it as.
  v_accrued := app.mana_interest(v_principal, v_inv.roi_rate, v_base, p_as_of);

  SELECT COALESCE(SUM(l.amount), 0) INTO v_paid
  FROM investment_interest_ledger l
  WHERE l.investment_id = p_investment_id AND l.entry_type = 'Payment';

  RETURN QUERY SELECT
    v_principal,
    v_inv.original_principal_amount,
    v_inv.roi_rate,
    v_inv.interest_type::text,
    v_daily,
    v_days,
    v_accrued,
    v_paid,
    (v_principal - v_inv.original_principal_amount) + v_accrued + v_paid,
    v_principal + v_accrued,
    v_pending,
    v_inv.last_compounding_date;
END;
$$;

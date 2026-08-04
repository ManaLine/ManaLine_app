-- Fix: yearly compounding used hardcoded 360 days instead of actual calendar
-- days (365 or 366 for leap years). Month = 30 days (daily rate unchanged),
-- year = actual days in the 12-month period.
--
-- BEFORE: v_year_int = CEIL(daily × 360)
--   For ₹10L @ 1.5/100/month: yearly = CEIL(500 × 360) = ₹1,80,000
-- AFTER:  v_year_int = CEIL(daily × actual_days_in_year)
--   For ₹10L @ 1.5/100/month, non-leap year: CEIL(500 × 365) = ₹1,82,500
--
-- The daily rate (monthly / 30) is unchanged — it is the documented
-- convention for deriving a daily rate from a monthly ROI (CALC BR-234).
-- The accrual (partial period) already uses actual days and is unchanged.

-- -----------------------------------------------------------------------
-- 1. Snapshot: the live read model (writes nothing)
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.investment_interest_snapshot(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
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
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      -- FIX: use actual days in the 12-month period (365 or 366 for leap
      -- years) instead of hardcoded 360.
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
  v_accrued := CEIL(v_daily * v_days);

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
$function$;

COMMENT ON FUNCTION app.investment_interest_snapshot(uuid, date) IS
  'CALC BR-234 live read model. Writes nothing; simulates un-materialised compounding so displays are correct regardless of whether apply_investment_compounding has run. Month = 30 days (daily rate); year = actual calendar days (365/366).';

-- -----------------------------------------------------------------------
-- 2. Compounding writer — materialises due anniversaries
-- -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.apply_investment_compounding(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_inv RECORD;
  v_principal numeric;
  v_anchor    date;
  v_daily     numeric;
  v_year_int  numeric;
  v_year_days integer;
  v_events    integer := 0;
BEGIN
  SELECT i.* INTO v_inv FROM investments i
  WHERE i.investment_id = p_investment_id FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may apply compounding' USING ERRCODE = '42501';
  END IF;

  IF v_inv.interest_type <> 'Yearly Compound' THEN
    RETURN 0;
  END IF;
  IF v_inv.status <> 'Active' THEN
    RETURN 0;
  END IF;

  v_principal := v_inv.principal_amount;
  v_anchor    := COALESCE(v_inv.last_compounding_date, v_inv.effective_date);

  WHILE (v_anchor + INTERVAL '12 months')::date <= p_as_of LOOP
    -- FIX: use actual days in the 12-month period instead of hardcoded 360.
    v_year_days := (v_anchor + INTERVAL '12 months')::date - v_anchor;
    v_anchor   := (v_anchor + INTERVAL '12 months')::date;
    v_daily    := app.investment_daily_interest(v_principal, v_inv.roi_rate);
    v_year_int := CEIL(v_daily * v_year_days);
    v_principal := v_principal + v_year_int;
    v_events   := v_events + 1;

    INSERT INTO investment_interest_ledger (
      investment_id, entry_type, amount, business_date, owner_verified, remarks
    ) VALUES (
      p_investment_id, 'Compounding Event', v_year_int, v_anchor, TRUE,
      'Yearly compounding: ' || v_year_int || ' added to principal over '
        || v_year_days || ' days (CALC BR-234)'
    );
  END LOOP;

  IF v_events > 0 THEN
    UPDATE investments
    SET principal_amount = v_principal,
        last_compounding_date = v_anchor
    WHERE investment_id = p_investment_id;
  END IF;

  RETURN v_events;
END;
$function$;

COMMENT ON FUNCTION app.apply_investment_compounding(uuid, date) IS
  'CALC BR-234 / BR-053. Idempotent: guarded by last_compounding_date. Month = 30 days (daily rate); year = actual calendar days (365/366).';

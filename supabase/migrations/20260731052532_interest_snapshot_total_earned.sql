-- Adds original_principal and total_interest_earned to the snapshot.
--
-- WHY: "Accrued" means different things depending on interest_type, which
-- reads as a bug on screen even though the maths is right. For Simple,
-- principal never absorbs interest so Accrued is cumulative. For Yearly
-- Compound it RESETS at each anniversary, because prior years' interest
-- has already become Principal (Appendix A, Case B: "current partial year
-- only — prior years' interest is already folded into Principal per
-- BR-052"). An Owner looking at 11,80,000 principal and 1,24,490 accrued
-- cannot see where the first year's 1,80,000 went.
--
-- total_interest_earned is that missing figure:
--   (principal - original_principal)   compounded into capital
--   + accrued_interest                 current period, unpaid
--   + interest_paid_to_date            already paid out in cash
--
-- It is REPORTING ONLY and must never be used as a withdrawal cap. An
-- "Interest Only" withdrawal is still capped at accrued_interest, because
-- compounded interest is withdrawable as Principal and not as interest —
-- that distinction is the whole reason the field is scoped this way.
--
-- Return type changes, so this is DROP + CREATE rather than REPLACE.
DROP FUNCTION IF EXISTS app.investment_interest_snapshot(uuid, date);

CREATE FUNCTION app.investment_interest_snapshot(
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
      v_anchor   := (v_anchor + INTERVAL '12 months')::date;
      v_daily    := app.investment_daily_interest(v_principal, v_inv.roi_rate);
      v_year_int := CEIL(v_daily * 360);
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
  'CALC BR-234 live read model. Writes nothing. accrued_interest is the current period only for Yearly Compound (BR-052) and is the withdrawal cap; total_interest_earned is reporting only.';

GRANT EXECUTE ON FUNCTION app.investment_interest_snapshot(uuid, date) TO authenticated;

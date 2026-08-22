-- Money earns interest for the time it was actually in.
--
-- The accrual was app.mana_interest(current principal, roi, base, as_of): one
-- span, at whatever the principal happens to be NOW. So a withdrawal rewrote
-- history. Karri Bhaskara Reddy put in Rs 10,00,000 on 2 January and took
-- Rs 9,00,000 back out across February and March; the moment those withdrawals
-- were recorded, the whole eleven weeks re-accrued as though only Rs 1,00,000
-- had ever been there -- his interest falling from Rs 39,000 to about
-- Rs 3,900, and the business's investor payable with it.
--
-- Nothing was wrong with mana_interest. Against this book it is exact: KBR
-- Rs 39,000, KSMR Rs 832 and Rs 11,000, TSR Rs 15,000, all matching the
-- Owner's own figures to the rupee. It was being handed the wrong principal.
--
-- The accrual now walks the withdrawals in date order and accrues each stretch
-- on the principal standing during it. The walk starts from the principal as
-- it was at the base date -- the current principal plus everything withdrawn
-- since -- because principal_amount is already net of them.
--
-- Against the live book this lands at Rs 24,83,982 against the Owner's
-- Rs 24,85,582. The Rs 1,600 left is theirs, not the formula's: Rs 600 is an
-- interest settlement they wrote by hand on a withdrawal, Rs 1,000 is a period
-- they rounded up. Before this change the same figure was out by Rs 28,000.
--
-- Yearly Compound is left alone above: it compounds on anniversaries, none of
-- which these investments have reached, and compounding across a withdrawal is
-- its own question. The segmentation below applies to the accrual either way.
CREATE OR REPLACE FUNCTION app.investment_interest_snapshot(
  p_investment_id uuid, p_as_of date DEFAULT CURRENT_DATE)
RETURNS TABLE(principal numeric, original_principal numeric, roi_rate numeric,
              interest_type text, daily_interest numeric, days_elapsed integer,
              accrued_interest numeric, interest_paid_to_date numeric,
              total_interest_earned numeric, available_balance numeric,
              pending_compounding_events integer, last_compounding_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
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
  v_running     numeric;
  v_seg_start   date;
  v_w           RECORD;
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

  -- What was standing at the base date: principal_amount is already net of
  -- every withdrawal, so add back the ones that happened after it.
  SELECT v_principal + COALESCE(SUM(w.principal_portion), 0) INTO v_running
    FROM investment_withdrawals w
   WHERE w.investment_id = p_investment_id
     AND w.deleted_at IS NULL
     AND w.business_date > v_base
     AND w.business_date <= p_as_of;

  -- Each stretch earns on the principal standing during it.
  v_accrued := 0;
  v_seg_start := v_base;
  FOR v_w IN
    SELECT w.business_date, w.principal_portion
      FROM investment_withdrawals w
     WHERE w.investment_id = p_investment_id
       AND w.deleted_at IS NULL
       AND w.business_date > v_base
       AND w.business_date <= p_as_of
     ORDER BY w.business_date
  LOOP
    v_accrued := v_accrued
               + app.mana_interest(v_running, v_inv.roi_rate, v_seg_start, v_w.business_date);
    v_running := v_running - v_w.principal_portion;
    v_seg_start := v_w.business_date;
  END LOOP;
  v_accrued := v_accrued
             + app.mana_interest(v_running, v_inv.roi_rate, v_seg_start, p_as_of);

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

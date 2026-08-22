-- Use the book's own interest for the span it covers, derive after it.
--
-- Same shape as the rest of the migration: declared up to the cut-off, derived
-- from there on. Where declared_interest_to_cutoff is set, the accrual is that
-- figure plus whatever has accrued since the cut-off; where it is NULL --
-- anything never migrated, or a week whose totals could not be attributed to
-- one investment -- nothing changes and the segmented walk runs as before.
--
-- Asking for a date BEFORE the cut-off still derives: the declared figure is
-- stated at the cut-off and says nothing about a Tuesday in February.
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
  v_span        date;
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

  SELECT migrated_through_date INTO v_span
    FROM businesses WHERE business_id = v_inv.business_id;

  IF v_inv.declared_interest_to_cutoff IS NOT NULL
     AND v_span IS NOT NULL
     AND p_as_of >= v_span THEN
    -- The book for its own span, the app for everything after it.
    v_accrued := v_inv.declared_interest_to_cutoff
               + app.mana_interest(v_principal, v_inv.roi_rate,
                                   GREATEST(v_base, v_span), p_as_of);
  ELSE
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
  END IF;

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

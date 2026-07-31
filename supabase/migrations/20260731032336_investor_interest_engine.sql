-- MANA LINE — Investor Interest Engine (CALC BR-233 / BR-234)
--
-- Implements docs/15_Calculation_Engine.md §3. Until now NOTHING in this
-- system computed investor interest: no SQL function, no Dart, and the
-- Owner's investor screens hardcoded `interestAccrued: 0`. The
-- investment_interest_ledger table was read in three places and written by
-- nobody.
--
-- ROUNDING — CONFIRMED with the Owner 2026-07-31. §3's ROUNDING RULE wins
-- over Appendix A's 2-decimal worked example, which contradicts it. Every
-- calculated amount CEILINGS to the whole rupee at the point it is
-- calculated, and for Yearly Compound that rounding compounds forward:
-- each year's New Principal is already rounded before it becomes the next
-- year's Old Principal. This is also the only reading the schema can hold
-- — every money column is numeric(14,0), so paise cannot be stored at all.
--
-- CONSEQUENCE FOR THE SPEC'S OWN FIXTURE: Appendix A Case A still
-- reproduces EXACTLY (₹50.00/day, ₹94,800 accrued — no rounding is even
-- needed there). Case B no longer matches from year 3 onward, because
-- 139,240 × 1.5/100/30 = 69.62/day ceilings to 70. Recomputed Case B under
-- the confirmed rule, which is the fixture to test against:
--   Yr1 100,000 -> daily 50  -> +18,000 -> 118,000
--   Yr2 118,000 -> daily 59  -> +21,240 -> 139,240
--   Yr3 139,240 -> daily 70  -> +25,200 -> 164,440
--   Yr4 164,440 -> daily 83  -> +29,880 -> 194,320
--   Yr5 194,320 -> daily 98  -> +35,280 -> 229,600
--   +70 days at daily 115 = 8,050 accrued; available = 237,650
--
-- DESIGN — two functions, deliberately split:
--   * investment_interest_snapshot() is STABLE and writes nothing. It
--     simulates any compounding that SHOULD have fired but has not been
--     materialised yet, so a display is always correct even if the
--     materialiser has never run. Mirrors the Line Score principle
--     (GLOBAL BR-210): derived values are recalculated, not trusted from
--     storage.
--   * apply_investment_compounding() is the only writer. It materialises
--     due anniversaries into investment_interest_ledger and moves
--     investments.principal_amount forward. Idempotent — guarded by
--     last_compounding_date, so running it twice in a day is a no-op.
-- Both must always agree. That is the correctness property to protect.

-- --------------------------------------------------------------------
-- 1. Daily interest — the one place the formula lives.
--    CALC BR-234: Daily Interest = Principal × (ROI ÷ 100) ÷ 30
--    30-day month convention, ceiling to whole rupee.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.investment_daily_interest(
  p_principal numeric,
  p_roi_rate numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CEIL(COALESCE(p_principal, 0) * (COALESCE(p_roi_rate, 0) / 100.0) / 30.0);
$function$;

COMMENT ON FUNCTION app.investment_daily_interest(numeric, numeric) IS
  'CALC BR-234. ROI is rupees per 100 of principal per month (CALC BR-233). 30-day month convention. Ceilings to whole rupee per the §3 ROUNDING RULE.';

-- --------------------------------------------------------------------
-- 2. Live snapshot — never writes.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.investment_interest_snapshot(
  p_investment_id uuid,
  p_as_of date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  principal numeric,
  roi_rate numeric,
  interest_type text,
  daily_interest numeric,
  days_elapsed integer,
  accrued_interest numeric,
  interest_paid_to_date numeric,
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

  -- Investor sees their own; Owner sees any in their business.
  IF NOT (app.is_own_investment_row(p_investment_id) OR app.is_owner(v_inv.business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;

  v_principal := v_inv.principal_amount;

  -- Yearly Compound: roll forward any anniversary that has passed but is
  -- not yet materialised. Rounding compounds forward, per §3.
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
    -- Simple: principal is untouched by interest (CALC BR-234); it moves
    -- only via BR-170 partial withdrawal or new capital.
    v_anchor := v_inv.effective_date;
  END IF;

  -- Accrual runs from the later of the last compounding anchor and the
  -- last interest payment (CALC BR-234 / BR-051 "calculated until payment
  -- date").
  v_base := GREATEST(v_anchor, COALESCE(v_inv.last_interest_payment_date, v_anchor));
  v_days := GREATEST(p_as_of - v_base, 0);
  v_daily := app.investment_daily_interest(v_principal, v_inv.roi_rate);
  v_accrued := CEIL(v_daily * v_days);

  SELECT COALESCE(SUM(l.amount), 0) INTO v_paid
  FROM investment_interest_ledger l
  WHERE l.investment_id = p_investment_id AND l.entry_type = 'Payment';

  RETURN QUERY SELECT
    v_principal,
    v_inv.roi_rate,
    v_inv.interest_type::text,
    v_daily,
    v_days,
    v_accrued,
    v_paid,
    v_principal + v_accrued,
    v_pending,
    v_inv.last_compounding_date;
END;
$function$;

COMMENT ON FUNCTION app.investment_interest_snapshot(uuid, date) IS
  'CALC BR-234 live read model. Writes nothing; simulates un-materialised compounding so displays are correct regardless of whether apply_investment_compounding has run.';

-- --------------------------------------------------------------------
-- 3. The only writer. Materialises due compounding events.
-- --------------------------------------------------------------------
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
  v_events    integer := 0;
BEGIN
  SELECT i.* INTO v_inv FROM investments i
  WHERE i.investment_id = p_investment_id FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;

  -- Owner-only: this moves principal. BR-055 — the system calculates, the
  -- Owner verifies. An investor cannot trigger their own compounding.
  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may apply compounding' USING ERRCODE = '42501';
  END IF;

  IF v_inv.interest_type <> 'Yearly Compound' THEN
    RETURN 0;   -- Simple interest never compounds (CALC BR-234 / BR-052).
  END IF;
  IF v_inv.status <> 'Active' THEN
    RETURN 0;
  END IF;

  v_principal := v_inv.principal_amount;
  v_anchor    := COALESCE(v_inv.last_compounding_date, v_inv.effective_date);

  WHILE (v_anchor + INTERVAL '12 months')::date <= p_as_of LOOP
    v_anchor   := (v_anchor + INTERVAL '12 months')::date;
    v_daily    := app.investment_daily_interest(v_principal, v_inv.roi_rate);
    v_year_int := CEIL(v_daily * 360);
    v_principal := v_principal + v_year_int;
    v_events   := v_events + 1;

    INSERT INTO investment_interest_ledger (
      investment_id, entry_type, amount, business_date, owner_verified, remarks
    ) VALUES (
      p_investment_id, 'Compounding Event', v_year_int, v_anchor, TRUE,
      'Yearly compounding: ' || v_year_int || ' added to principal (CALC BR-234)'
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
  'CALC BR-234 / BR-053. Idempotent: guarded by last_compounding_date, so a second run on the same day is a no-op.';

-- --------------------------------------------------------------------
-- 4. Record an interest PAYMENT (BR-051/BR-055).
--    Owner-verified payout; moves last_interest_payment_date so accrual
--    restarts from the payment date rather than double-paying.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_investment_interest_payment(
  p_investment_id uuid,
  p_amount numeric,
  p_business_date date DEFAULT CURRENT_DATE,
  p_remarks text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_inv RECORD;
  v_ledger_id uuid;
BEGIN
  SELECT i.* INTO v_inv FROM investments i
  WHERE i.investment_id = p_investment_id FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may record an interest payment' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Interest payment must be greater than zero' USING ERRCODE = '23514';
  END IF;

  INSERT INTO investment_interest_ledger (
    investment_id, entry_type, amount, business_date, owner_verified, remarks
  ) VALUES (
    p_investment_id, 'Payment', CEIL(p_amount), p_business_date, TRUE, p_remarks
  ) RETURNING interest_ledger_id INTO v_ledger_id;

  UPDATE investments
  SET last_interest_payment_date = p_business_date
  WHERE investment_id = p_investment_id;

  RETURN v_ledger_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.investment_daily_interest(numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION app.investment_interest_snapshot(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.apply_investment_compounding(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION app.record_investment_interest_payment(uuid, numeric, date, text) TO authenticated;

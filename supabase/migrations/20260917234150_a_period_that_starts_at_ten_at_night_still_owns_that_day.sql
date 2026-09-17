-- app.locked_period_reason missed the first day of every settled period.
--
-- account_periods.business_start_date is a TIMESTAMP, not a date -- the live
-- Approved period begins at 2026-08-18 22:57:53. Comparing a business DATE
-- against it casts the date to midnight, so 18 Aug 00:00 sorts before a period
-- that opened at ten that night and the guard returned NULL. A collection
-- taken on the first day of a settled account could still be deleted, and
-- would still rewrite it.
--
-- Caught by testing the boundary rather than the middle. The mid-period date
-- refused correctly on the first try, which is exactly the result that would
-- have ended the checking.
--
-- Both bounds are cast to ::date now. A period does not half-own the day it
-- opens on: the account either covers that business day or it does not, and
-- the clock time an agent happened to press Start is not a fact about the
-- book.

CREATE OR REPLACE FUNCTION app.locked_period_reason(
  p_business_id uuid,
  p_date        date
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_agent text; v_from date; v_to date;
BEGIN
  IF p_date IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM day_ledger d
              WHERE d.business_id = p_business_id
                AND d.business_date = p_date
                AND d.status = 'Closed') THEN
    RETURN format('%s has been closed. Reopen the day before changing it.',
                  to_char(p_date, 'DD Mon YYYY'));
  END IF;

  -- A period an agent has handed in and an Owner may already have signed.
  -- 'Running' and 'Overdue' are still open and are not locked.
  --
  -- ::date on both bounds. Without it the period's own first day escapes,
  -- because business_start_date carries the clock time the account was opened.
  SELECT p.full_name, ap.business_start_date::date,
         COALESCE(ap.actual_end_date, ap.planned_business_end_date)::date
    INTO v_agent, v_from, v_to
    FROM account_periods ap
    JOIN business_members bm ON bm.membership_id = ap.agent_membership_id
    JOIN persons p ON p.person_id = bm.person_id
   WHERE ap.business_id = p_business_id
     AND ap.status IN ('Submitted', 'Approved', 'Locked')
     AND p_date >= ap.business_start_date::date
     AND p_date <= COALESCE(ap.actual_end_date,
                            ap.planned_business_end_date)::date
   LIMIT 1;

  IF v_agent IS NOT NULL THEN
    RETURN format(
      '%s is part of a settled account (%s, %s to %s). Return that settlement first.',
      to_char(p_date, 'DD Mon YYYY'), v_agent,
      to_char(v_from, 'DD Mon'), to_char(v_to, 'DD Mon'));
  END IF;

  RETURN NULL;
END;
$function$;

DO $$
DECLARE v_first TEXT; v_mid TEXT; v_out TEXT; v_bid uuid;
BEGIN
  SELECT ap.business_id INTO v_bid FROM account_periods ap
   WHERE ap.status IN ('Submitted','Approved','Locked') LIMIT 1;

  IF v_bid IS NOT NULL THEN
    SELECT app.locked_period_reason(v_bid, ap.business_start_date::date),
           app.locked_period_reason(v_bid, ap.business_start_date::date + 1),
           app.locked_period_reason(
             v_bid,
             COALESCE(ap.actual_end_date, ap.planned_business_end_date)::date + 30)
      INTO v_first, v_mid, v_out
      FROM account_periods ap
     WHERE ap.business_id = v_bid
       AND ap.status IN ('Submitted','Approved','Locked')
     LIMIT 1;

    IF v_first IS NULL THEN
      RAISE EXCEPTION 'the first day of a settled period is still unguarded';
    END IF;
    IF v_mid IS NULL THEN
      RAISE EXCEPTION 'a mid-period day is unguarded';
    END IF;
    IF v_out IS NOT NULL THEN
      RAISE EXCEPTION 'a day well outside the period was refused: %', v_out;
    END IF;
  END IF;
END $$;

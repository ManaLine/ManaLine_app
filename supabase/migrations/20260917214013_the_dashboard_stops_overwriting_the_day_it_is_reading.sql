-- app.refresh_day_ledger was a second, older, incomplete implementation of
-- app.recompute_day_ledger -- and it WRITES. Every Owner dashboard load called
-- it for today, so it overwrote the row it was about to display.
--
-- Found while closing the deleted_at gap in agent_expected_closing, by asking
-- which other functions read a soft-deletable money table without mentioning
-- deleted_at. This one came back, and it was much worse than the gap I was
-- looking for.
--
-- THREE DEFECTS, all in the same UPDATE:
--
--   1. total_collections summed ONLY payment_mode = 'Cash'. Every other mode
--      was dropped. This became sharp today: the collection form now offers
--      GPay, PhonePe and Paytm, so an online payment would be recorded
--      correctly by the trigger and then erased from the day's Vasool the next
--      time the Owner opened their dashboard.
--
--   2. No deleted_at filter on collections, loans, investments, withdrawals or
--      expenses. Reversed entries counted as real ones.
--
--   3. closing_balance omitted cheti_paid, cheti_received, short and excess
--      entirely -- four columns recompute_day_ledger includes. On any day
--      carrying a cheti instalment or a settlement short, the closing it wrote
--      was simply a different number from the one the ledger's own rules
--      produce.
--
-- Measured against the live book before changing anything, comparing what it
-- would write against what recompute_day_ledger had already produced:
--
--   13 Mar 2026  collections 2,67,140 -> 63,640    closing 52,740 -> -1,50,760
--   20 Mar 2026  collections 2,45,540 -> 1,55,140  closing    100 ->   -90,300
--   28 Aug 2026  collections 2,73,240 -> 2,39,340  closing 4,99,160 -> 4,65,260
--
-- The negative closings are migrated weekly accounts: app.import_weekly_account
-- writes aggregate figures with no per-row collections behind them, and this
-- function recomputed from rows that were never there. recompute_day_ledger
-- does not do that, because it reads businesses.migrated_through_date and
-- leaves the frozen span alone.
--
-- THE LIVE DAMAGE WAS BOUNDED, and saying so matters more than making this
-- sound worse than it was: the only caller passes manaBusinessDate(), so just
-- today's row was ever at risk, never the history above. Today's row on the
-- live book has no collections yet, so nothing is currently wrong. This is a
-- trap that had not yet sprung -- and Tranche O's online modes are what would
-- have sprung it.
--
-- THE FIX IS DELETION, NOT REPAIR. Patching three defects would leave two
-- implementations of one calculation, which is how they drifted apart in the
-- first place. recompute_day_ledger is the one the triggers use on all eight
-- source tables, it filters deleted_at throughout, it carries cheti and
-- short/excess, and it respects the migrated span. So refresh_day_ledger keeps
-- only what is its own -- the Owner check and the closed-day refusal -- and
-- delegates the arithmetic.
--
-- THE DEFAULT IS PRESERVED. p_business_date carries DEFAULT CURRENT_DATE, and
-- dropping it raises 42P13 "cannot remove parameter defaults from existing
-- function". Keeping it also keeps the identity arguments unchanged, so this
-- is a genuine CREATE OR REPLACE and not the DROP-then-CREATE case -- the
-- overload count is asserted below regardless.

CREATE OR REPLACE FUNCTION app.refresh_day_ledger(
  p_business_id   uuid,
  p_business_date date DEFAULT CURRENT_DATE
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_status day_ledger_status_enum;
  v_exists BOOLEAN;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may refresh the day ledger'
      USING ERRCODE = '42501';
  END IF;

  SELECT TRUE, status INTO v_exists, v_status
    FROM day_ledger
   WHERE business_id = p_business_id AND business_date = p_business_date;

  -- Nothing to refresh. Unchanged behaviour: this returned quietly when the
  -- row was absent, and the dashboard relies on that -- it calls
  -- open_business_day first, but a failure there must not turn into an
  -- exception here.
  IF NOT COALESCE(v_exists, FALSE) THEN
    RETURN;
  END IF;

  IF v_status = 'Closed' THEN
    RAISE EXCEPTION 'This business day is closed. Reopen it before recalculating.'
      USING ERRCODE = '23514';
  END IF;

  -- The one implementation. It reads the same eight source tables the triggers
  -- do, filters deleted_at on every one, counts every payment mode rather than
  -- Cash alone, includes cheti and short/excess in the closing, and leaves the
  -- migrated span frozen.
  PERFORM app.recompute_day_ledger(p_business_id, p_business_date);
END;
$function$;

DO $$
DECLARE v_n INT; v_src TEXT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'refresh_day_ledger';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'refresh_day_ledger has % overloads', v_n;
  END IF;

  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'refresh_day_ledger';

  -- It must no longer compute anything of its own.
  IF v_src ~* 'UPDATE\s+day_ledger' THEN
    RAISE EXCEPTION 'refresh_day_ledger still writes day_ledger directly';
  END IF;
  IF v_src !~* 'recompute_day_ledger' THEN
    RAISE EXCEPTION 'refresh_day_ledger no longer delegates';
  END IF;
  IF v_src ~* 'payment_mode' THEN
    RAISE EXCEPTION 'refresh_day_ledger still has its own collections sum';
  END IF;
END $$;

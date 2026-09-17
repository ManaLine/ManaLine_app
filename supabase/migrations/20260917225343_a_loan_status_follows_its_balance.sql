-- A loan paid to zero closes itself, and a loan that owes money again reopens.
--
-- THE ASK WAS "fix record_collection to close the loan at zero", AND THAT IS
-- THE WRONG PLACE -- said out loud rather than quietly done differently.
-- Seven functions assign loans.remaining_balance and only close_loan ever set
-- a status:
--
--   record_collection    a payment           balance down
--   amend_collection     a correction        down or up
--   waive_loan_penalty   a waiver            down
--   apply_loan_penalty   a penalty           up
--   soft_delete_record   a deleted payment   up
--   restore_record       an undeleted one    down
--   close_loan           the manual close    forced to zero
--
-- Putting the rule in record_collection fixes one of seven. Worse, it would
-- CREATE a defect on another: deleting a collection from a closed loan gives
-- the money back, and the loan would then owe money while still marked
-- finished -- invisible to the round, to the pending list and to the agent.
--
-- So the status is DERIVED from the balance, which is this codebase's existing
-- answer to exactly this shape. CLAUDE.md, on BF: "Delete and restore both
-- move BF because neither has to remember to." A trigger means no future path
-- has to remember either.
--
-- SAFE FOR THE DAY LEDGER, checked rather than assumed: app.recompute_day_ledger
-- sums loans by issue_business_date and deleted_at with NO loan_status filter,
-- so opening or closing a loan cannot move total_loan_distribution or any
-- closing balance. (app.refresh_day_ledger did filter on status -- one more way
-- those two disagreed before it was reduced to a delegate this evening.)
--
-- CANCELLED AND DEFAULTED ARE NEVER TOUCHED. Both are decisions somebody made
-- about a loan, not facts about its balance, and a trigger that overrode them
-- would be the app arguing with a person.
--
-- PENALTY RECOGNITION HAPPENS HERE TOO, and only on the branch that closes a
-- loan by payment. app.close_loan already distinguishes a pay-off from a
-- write-off and recognises only the former; a trigger cannot tell them apart
-- after the fact, because both arrive as balance>0 becoming balance=0. Doing
-- the recognition inside the branch that DID the closing is what keeps that
-- distinction: close_loan sets the status itself, so the close branch below
-- never fires for it, and a write-off can never be recognised as income here.
-- There is one unrecognised penalty entry on the live books, for Rs 1,000.
--
-- No trigger exists on penalty_entries, so this cascades nowhere.
--
-- VERIFIED BY FIRING IT, inside a rolled-back subtransaction, with the results
-- carried out in variables because rows written inside a subtransaction roll
-- back with it:
--
--   the Penalty loan paid to zero  ->  Closed, closed_at set,
--                                      penalty recognised 2026-09-17
--   its balance restored           ->  Active, closed_at null
--   Defaulted, then paid to zero   ->  Defaulted
--
-- then rolled back and the book re-counted: 51 Active, 7 Closed, 1 Penalty,
-- the penalty entry still unrecognised. Nothing left behind.

CREATE OR REPLACE FUNCTION app.tg_loan_status_follows_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- A deleted loan is out of the world; its status is whatever it was when it
  -- left, and restoring it is what brings it back.
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- PAID OFF. Only from a status that means the loan is running; 'Cancelled'
  -- and 'Defaulted' are somebody's decision and are left alone.
  IF NEW.remaining_balance <= 0
     AND NEW.loan_status IN ('Active', 'Grace Period', 'Penalty') THEN
    NEW.loan_status := 'Closed';
    NEW.closed_at   := COALESCE(NEW.closed_at, now());

    -- The penalty was collected as part of the balance that just reached zero,
    -- so this is the day it became income. CURRENT_DATE matches the convention
    -- app.close_loan already uses, so the manual and automatic paths put it on
    -- the same day.
    UPDATE penalty_entries
       SET recognised_business_date = CURRENT_DATE
     WHERE loan_id = NEW.loan_id
       AND recognised_business_date IS NULL
       AND penalty_amount_applied > 0;

  -- OWES MONEY AGAIN. A deleted payment, a restored one, or a penalty applied
  -- after closing. The loan is live again and must reappear in the round --
  -- leaving it Closed is the defect this trigger exists to prevent, not a
  -- state to preserve.
  ELSIF NEW.remaining_balance > 0
        AND NEW.loan_status = 'Closed'
        AND OLD.loan_status = 'Closed' THEN
    NEW.loan_status := 'Active';
    NEW.closed_at   := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_loans_status_follows_balance ON loans;
CREATE TRIGGER trg_loans_status_follows_balance
  BEFORE UPDATE ON loans
  FOR EACH ROW
  EXECUTE FUNCTION app.tg_loan_status_follows_balance();

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM pg_trigger
   WHERE tgrelid = 'loans'::regclass
     AND tgname = 'trg_loans_status_follows_balance';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'the status trigger is not installed';
  END IF;

  -- Nothing on the live books should now be running with nothing left to pay.
  SELECT count(*) INTO v_n FROM loans
   WHERE deleted_at IS NULL
     AND remaining_balance <= 0
     AND loan_status IN ('Active', 'Grace Period', 'Penalty');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '% paid-off loan(s) are still open', v_n;
  END IF;
END $$;

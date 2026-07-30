-- =============================================================================
-- 0055 — Penalty lifecycle: overdue gate, recognition on payoff, daily figure
-- =============================================================================
-- Implements the Owner-confirmed penalty flow end to end. 0054 built the
-- atomic apply/waive pair; this migration adds the three rules that were
-- missing from it, all of them confirmed explicitly rather than inferred:
--
--   1. APPLY IS GATED ON THE LOAN BEING FULLY OVERDUE. A penalty may only
--      be applied once the loan's own end of term — the LAST installment's
--      due_date — plus grace_period_days has elapsed. Not per-installment:
--      a single missed installment mid-term is not enough. Server-side hard
--      rejection, deliberately the same posture as the BR-043/219
--      zero-difference gate in close_business_day: no override parameter.
--
--   2. APPLY MOVES NOTHING BUT THE CUSTOMER'S BALANCE. penalty_entries +
--      loans.remaining_balance, and nothing else — no day_ledger, no
--      businesses.owner_bf_balance, no agent_bf_assignments. Already true
--      of 0054's apply_loan_penalty and preserved here; stated because it
--      is a deliberate rule, not an omission.
--
--   3. PENALTY INCOME IS RECOGNISED ONLY WHEN THE CUSTOMER ACTUALLY PAYS
--      IT OFF. The recognition event is the Owner closing a loan whose
--      remaining_balance was ALREADY zero when they closed it — i.e. the
--      customer paid it down. A write-off (the close call itself forcing
--      the balance to zero), and therefore Defaulted and Cancelled loans,
--      recognise nothing. That distinction needs no new flag: whether the
--      balance was zero BEFORE the close call separates a payoff from a
--      write-off using data already on the row.
--
-- WHERE THE DAILY FIGURE LIVES — and why it is not a day_ledger column.
-- The obvious shape would be day_ledger.penalty_collected. Rejected for a
-- concrete reason: nothing in this codebase ever INSERTs a day_ledger row.
-- Every access in the Dart layer is a read, record_book_state.dart's own
-- header states day_ledger "is system-derived and never directly written by
-- any client call except remarks", and the subsystem that populates it does
-- not exist yet. A penalty recognised on a date with no day_ledger row
-- would have had nowhere to go, and fabricating the row means inventing
-- values for seven NOT NULL financial columns — which would also make
-- day_closure_state.dart's precheck report activity on a day that had none.
--
-- So the source of truth is penalty_entries.recognised_business_date, and
-- the per-day figure is derived from it by
-- app.penalty_collected_by_day(). One source, no row to create, nothing to
-- keep in sync, and no risk of drifting from the penalty rows it describes.
--
-- Per the confirmed design the figure sits BESIDE collections rather than
-- inside them: it is never subtracted from day_ledger.total_collections and
-- never added to closing_balance. The penalty rupees physically arrive in a
-- normal collection and are already counted once in the cash flow;
-- recognition classifies that money as penalty income, it does not move it.
-- Carving it out of total_collections was considered and rejected — it
-- would require asserting which day's payment contained the penalty (the
-- rupee-level tagging this design deliberately avoids) and could drive a
-- day's total_collections negative when the final payment is smaller than
-- the penalty being recognised.
--
-- RECOGNITION DATE is the loan's close date, not the final payment date.
-- Chosen so that a day already closed through day_closures never has its
-- figures shift underneath the Owner afterwards — the reopen-with-reason
-- audit trail on that table says settled days are meant to stay settled.
-- Safe precisely because penalty_collected stays out of closing_balance, so
-- attributing it to the close date cannot break any cash reconciliation.
-- -----------------------------------------------------------------------------

ALTER TABLE penalty_entries
  ADD COLUMN IF NOT EXISTS recognised_business_date DATE NULL;

COMMENT ON COLUMN penalty_entries.recognised_business_date IS
  'NULL until the penalty is actually paid off. Set to the loan''s close date by app.close_loan when the loan is closed with a balance that was ALREADY zero (a genuine payoff). Stays NULL forever on write-off / Defaulted / Cancelled loans, which recognise no penalty income. This column is the single source of truth for the daily "Penalty Collected" figure — see app.penalty_collected_by_day and the 0055 header for why it is not a day_ledger column.';

CREATE INDEX IF NOT EXISTS idx_penalty_entries_recognised
  ON penalty_entries(recognised_business_date)
  WHERE recognised_business_date IS NOT NULL;

-- -----------------------------------------------------------------------------
-- app.loan_penalty_eligible_from — the overdue threshold, exposed so the UI
-- can show WHEN a penalty becomes available instead of only discovering the
-- rejection after the Owner has typed an amount.
--
-- Returns the first date on which a penalty may be applied: the last
-- installment's due_date + grace_period_days, plus one day. The "+1" makes
-- the gate mean "grace has fully elapsed" — on the last day of grace the
-- customer is still within it. Flip the interval here if the intended
-- reading is "on the day grace expires"; this is the only place the
-- boundary is defined, and the gate below reads it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.loan_penalty_eligible_from(p_loan_id UUID)
RETURNS DATE
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_last_due DATE;
  v_grace INT;
BEGIN
  SELECT l.grace_period_days, (SELECT MAX(s.due_date) FROM loan_schedule s WHERE s.loan_id = l.loan_id)
  INTO v_grace, v_last_due
  FROM loans l WHERE l.loan_id = p_loan_id;

  IF v_last_due IS NULL THEN
    RETURN NULL;  -- no schedule rows: term end is unknowable, caller must reject
  END IF;
  RETURN v_last_due + v_grace + 1;
END;
$$;

COMMENT ON FUNCTION app.loan_penalty_eligible_from(UUID) IS
  'First date a penalty may be applied to this loan: last loan_schedule.due_date + loans.grace_period_days + 1 day. NULL when the loan has no schedule rows at all (term end unknowable — app.apply_loan_penalty rejects rather than guessing). Single definition of the overdue boundary; the apply gate reads it.';

GRANT EXECUTE ON FUNCTION app.loan_penalty_eligible_from(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.apply_loan_penalty — recreated to add rule 1 (the overdue hard gate).
-- Everything else is unchanged from 0054: same signature, same atomic
-- penalty_entries insert + remaining_balance increase, same authorization.
-- The gate is evaluated against the EFFECTIVE business date (p_business_date
-- when supplied, else today) so a backdated entry is judged on the date it
-- claims to have happened, not on today.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.apply_loan_penalty(
  p_loan_id UUID,
  p_penalty_option penalty_option_enum,
  p_penalty_amount DECIMAL(14,0),
  p_business_date DATE DEFAULT NULL,
  p_penalty_value DECIMAL(14,0) DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_loan_status loan_status_enum;
  v_balance DECIMAL(14,0);
  v_business_date DATE := COALESCE(p_business_date, CURRENT_DATE);
  v_eligible_from DATE;
  v_penalty_id UUID;
BEGIN
  IF NOT app.can_apply_penalty_on_loan(p_loan_id) THEN
    RAISE EXCEPTION 'Not authorized to apply a penalty on this loan' USING ERRCODE = '42501';
  END IF;
  IF p_penalty_amount IS NULL OR p_penalty_amount <= 0 THEN
    RAISE EXCEPTION 'Penalty amount must be greater than zero' USING ERRCODE = '23514';
  END IF;

  SELECT loan_status, remaining_balance INTO v_loan_status, v_balance
  FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_loan_status IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan_status IN ('Closed', 'Cancelled') THEN
    RAISE EXCEPTION 'Cannot apply a penalty to a % loan', v_loan_status USING ERRCODE = '23514';
  END IF;

  -- Rule 1, first half: "loan not paid". A fully-repaid loan that simply
  -- has not been closed yet is not a penalty case, even once its term has
  -- elapsed — applying one would resurrect a debt the customer has settled.
  IF v_balance <= 0 THEN
    RAISE EXCEPTION 'Loan is fully repaid — no penalty can be applied' USING ERRCODE = '23514';
  END IF;

  -- Rule 1, second half: fully overdue — due date AND grace period crossed.
  v_eligible_from := app.loan_penalty_eligible_from(p_loan_id);
  IF v_eligible_from IS NULL THEN
    RAISE EXCEPTION 'Cannot assess overdue status: this loan has no repayment schedule'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_business_date < v_eligible_from THEN
    RAISE EXCEPTION 'Loan is not yet past its due date plus grace period — a penalty may be applied from % onwards', v_eligible_from
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO penalty_entries (
    loan_id, penalty_option, penalty_value, penalty_amount_applied,
    applied_by_person_id, business_date
  ) VALUES (
    p_loan_id, p_penalty_option, COALESCE(p_penalty_value, p_penalty_amount), p_penalty_amount,
    app.current_person_id(), v_business_date
  ) RETURNING penalty_id INTO v_penalty_id;

  -- The ONLY side effect beyond the entry itself (rule 2). No day_ledger,
  -- no owner_bf_balance, no agent BF — the penalty is the customer's debt
  -- and becomes the business's income only when it is actually paid.
  UPDATE loans
  SET remaining_balance = remaining_balance + p_penalty_amount, updated_at = now()
  WHERE loan_id = p_loan_id;

  RETURN v_penalty_id;
END;
$$;

COMMENT ON FUNCTION app.apply_loan_penalty(UUID, penalty_option_enum, DECIMAL, DATE, DECIMAL) IS
  'OW-007 Apply Penalty. Hard-gated on the loan being past its LAST installment due_date + grace_period_days (app.loan_penalty_eligible_from) — no override parameter, same posture as the BR-043/219 close gate. Atomically inserts penalty_entries and adds the amount to loans.remaining_balance, and touches nothing else: penalty income is recognised later, at payoff, by app.close_loan. Gated on Owner-of-business OR Agent-covers-customer + can_apply_penalty (OFF by default, BR-236).';

GRANT EXECUTE ON FUNCTION app.apply_loan_penalty(UUID, penalty_option_enum, DECIMAL, DATE, DECIMAL) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.close_loan — replaces the raw client-side UPDATE in
-- loan_details_state.dart, because closing a loan is now also the penalty
-- recognition event and the two must not be separable.
--
-- Behaviour deliberately preserved from the code it replaces: closing a
-- non-write-off loan that still carries an outstanding balance is ALLOWED,
-- because OW-007 offers exactly that (its dialog reads "Close this loan?
-- Outstanding balance is X", and the write-off variant is only offered on
-- Defaulted loans). Such a close simply recognises no penalty, since the
-- balance was not zero. This function does not tighten that rule — it only
-- refuses to treat it as a payoff.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.close_loan(
  p_loan_id UUID,
  p_write_off BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_status loan_status_enum;
  v_balance DECIMAL(14,0);
  v_was_paid_off BOOLEAN;
  v_recognised DECIMAL(14,0) := 0;
  v_recognised_date DATE := NULL;
BEGIN
  SELECT business_id, loan_status, remaining_balance
  INTO v_business_id, v_status, v_balance
  FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;
  -- Owner-only, matching the pre-existing effective permission: loans RLS
  -- (0015) grants Agents SELECT and INSERT but no UPDATE, so the raw client
  -- update this replaces was already Owner-only in practice.
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may close a loan' USING ERRCODE = '42501';
  END IF;
  IF v_status IN ('Closed', 'Cancelled') THEN
    RAISE EXCEPTION 'Loan is already %', v_status USING ERRCODE = '23505';
  END IF;

  -- THE recognition test (rule 3): was the balance already zero before this
  -- call touched anything? Zero means the customer paid it down, penalty
  -- included. A write-off is the call itself zeroing a non-zero balance,
  -- and recognises nothing.
  v_was_paid_off := (v_balance = 0) AND NOT p_write_off;

  UPDATE loans SET
    loan_status = 'Closed',
    closed_at = now(),
    remaining_balance = CASE WHEN p_write_off THEN 0 ELSE remaining_balance END,
    updated_at = now()
  WHERE loan_id = p_loan_id;

  IF v_was_paid_off THEN
    v_recognised_date := CURRENT_DATE;
    UPDATE penalty_entries
    SET recognised_business_date = v_recognised_date
    WHERE loan_id = p_loan_id
      AND recognised_business_date IS NULL
      AND penalty_amount_applied > 0;

    -- Sum AFTER the update so the figure returned is exactly what was just
    -- recognised. penalty_amount_applied already reflects any waiver or
    -- reduction (app.waive_loan_penalty rewrites it to the new effective
    -- amount), so a fully waived penalty contributes 0 and is skipped by
    -- the > 0 filter above rather than needing a separate exclusion.
    SELECT COALESCE(SUM(penalty_amount_applied), 0) INTO v_recognised
    FROM penalty_entries
    WHERE loan_id = p_loan_id AND recognised_business_date = v_recognised_date;
  END IF;

  RETURN json_build_object(
    'loan_id', p_loan_id,
    'status', 'Closed',
    'written_off', p_write_off,
    'penalty_recognised', v_recognised,
    'recognised_business_date', v_recognised_date
  );
END;
$$;

COMMENT ON FUNCTION app.close_loan(UUID, BOOLEAN) IS
  'OW-007 Close Loan / Write-off, and the penalty recognition event. Recognises penalty income (stamping penalty_entries.recognised_business_date with today) ONLY when the loan is closed with a balance that was already zero — a genuine payoff. p_write_off zeroes a non-zero balance and recognises nothing, which is also what makes Defaulted and Cancelled loans recognise nothing. Closing with an outstanding balance and no write-off remains permitted (OW-007 offers it) and simply recognises nothing.';

GRANT EXECUTE ON FUNCTION app.close_loan(UUID, BOOLEAN) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.penalty_collected_by_day — the daily account figure.
-- Derived from penalty_entries, never stored on day_ledger (see header).
-- Returns only dates that actually have recognised penalties; a day with
-- none is simply absent, and the caller renders zero. NULL bounds mean
-- unbounded, matching fetchLedgerRows' optional date filters.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.penalty_collected_by_day(
  p_business_id UUID,
  p_from DATE DEFAULT NULL,
  p_to DATE DEFAULT NULL
)
RETURNS TABLE(business_date DATE, penalty_collected DECIMAL(14,0))
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT pe.recognised_business_date, SUM(pe.penalty_amount_applied)
  FROM penalty_entries pe
  JOIN loans l ON l.loan_id = pe.loan_id
  WHERE l.business_id = p_business_id
    AND pe.recognised_business_date IS NOT NULL
    AND (p_from IS NULL OR pe.recognised_business_date >= p_from)
    AND (p_to IS NULL OR pe.recognised_business_date <= p_to)
  GROUP BY pe.recognised_business_date
  ORDER BY pe.recognised_business_date DESC;
END;
$$;

COMMENT ON FUNCTION app.penalty_collected_by_day(UUID, DATE, DATE) IS
  'OW-009 Daily Record Book "Penalty Collected" per business day, summed from penalty_entries.recognised_business_date. Deliberately additive alongside day_ledger.total_collections rather than carved out of it: the penalty rupees are already counted once in the cash flow that reconciles against day_closures, and this classifies them as income without moving them. Days with no recognised penalty are omitted from the result.';

GRANT EXECUTE ON FUNCTION app.penalty_collected_by_day(UUID, DATE, DATE) TO authenticated;

-- =============================================================================
-- 0054 — Penalty + Day Closure RPCs (the last three BLOCKED-on-RPC call sites)
-- =============================================================================
-- Closes the three RPCs the Dart layer has been raising UnimplementedError
-- for, by name, with the expected param lists spelled out in its own
-- comments: apply_loan_penalty (loan_details_state.dart), close_business_day
-- and record_day_closure_adjustment (day_closure_state.dart).
--
-- Two additions beyond that literal list, both to avoid shipping half a
-- feature:
--
--   * waive_loan_penalty — OW-007 calls waiveOrReducePenalty() from the
--     button directly beside Apply Penalty, and it raised the same
--     UnimplementedError naming this same RPC. Applying a penalty with no
--     way to reverse it is not a shippable state, and the reversal has the
--     identical atomicity requirement (undo the remaining_balance delta in
--     the same transaction as the flag).
--
--   * day_closure_expected — day_closure_state.dart's precheck() carries an
--     explicit warning that it fakes the per-method Expected split by
--     dumping day_ledger.closing_balance into expectedCash and zeroing UPI/
--     Bank/Cheque, and says the real split "needs to come from the (also
--     blocked) close_business_day RPC instead". Adding the derivation as a
--     separate STABLE function as well as using it inside
--     close_business_day means the advisory client-side precheck and the
--     authoritative server-side gate agree BY CONSTRUCTION. Without this,
--     the UI's Difference=0 check and the server's would disagree on any
--     business taking non-cash payments, and the Owner would hit a hard
--     rejection on a screen that had just shown them a green zero.
--
-- SCHEMA CHANGE (settlement_adjustments.business_id): day_closure_state.dart
-- flagged this table as "structurally unscopable" for a Day-Closure-created
-- adjustment, and it was right — settlement_adjustments reaches business_id
-- only via settlement_id or agent_id, a Day Closure difference has neither,
-- and 0017's settlement_adjustments_owner_all policy tests exactly those two
-- paths. A row with both NULL would insert and then be invisible to every
-- role including the Owner who created it. Resolved the way that comment's
-- first option describes: a nullable business_id column plus a third policy
-- branch. Nullable, not NOT NULL, because every existing row legitimately
-- has no business_id of its own and gets it through the agent/settlement
-- path — backfilling would be inventing data.
-- -----------------------------------------------------------------------------

ALTER TABLE settlement_adjustments
  ADD COLUMN IF NOT EXISTS business_id UUID NULL REFERENCES businesses(business_id);

COMMENT ON COLUMN settlement_adjustments.business_id IS
  'Added 0054. Set ONLY for adjustments that belong to a business day rather than to an agent settlement (OW-011 Day Closure Difference Analyzer), where settlement_id and agent_id are both NULL and there is otherwise no path to a business_id at all — see 0054 header. Existing agent/settlement-scoped rows leave this NULL and remain reachable through their own path.';

CREATE INDEX IF NOT EXISTS idx_settlement_adjustments_business_date
  ON settlement_adjustments(business_id, business_date);

-- Third access branch. Written as a policy replacement rather than an extra
-- policy so the intent stays readable as one rule: an Owner may reach an
-- adjustment through its agent, through its settlement, OR through its own
-- business_id.
DROP POLICY IF EXISTS settlement_adjustments_owner_all ON settlement_adjustments;
CREATE POLICY settlement_adjustments_owner_all ON settlement_adjustments
  FOR ALL
  USING (
    (agent_id IS NOT NULL AND EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = settlement_adjustments.agent_id AND app.is_owner(bm.business_id)))
    OR (settlement_id IS NOT NULL AND EXISTS (SELECT 1 FROM account_settlements s JOIN agents a ON a.agent_id = s.agent_id JOIN business_members bm ON bm.membership_id = a.membership_id WHERE s.settlement_id = settlement_adjustments.settlement_id AND app.is_owner(bm.business_id)))
    OR (settlement_adjustments.business_id IS NOT NULL AND app.is_owner(settlement_adjustments.business_id))
  )
  WITH CHECK (
    (agent_id IS NOT NULL AND EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = settlement_adjustments.agent_id AND app.is_owner(bm.business_id)))
    OR (settlement_id IS NOT NULL AND EXISTS (SELECT 1 FROM account_settlements s JOIN agents a ON a.agent_id = s.agent_id JOIN business_members bm ON bm.membership_id = a.membership_id WHERE s.settlement_id = settlement_adjustments.settlement_id AND app.is_owner(bm.business_id)))
    OR (settlement_adjustments.business_id IS NOT NULL AND app.is_owner(settlement_adjustments.business_id))
  );

-- -----------------------------------------------------------------------------
-- app.can_apply_penalty_on_loan — shared gate for apply/waive.
-- Owner of the loan's business, or an Agent who covers the customer AND
-- holds can_apply_penalty (0005: BOOLEAN NOT NULL DEFAULT FALSE, i.e. OFF
-- by default per BR-236 — this is deliberately not inferred from any
-- broader permission).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.can_apply_penalty_on_loan(p_loan_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_customer_id UUID;
BEGIN
  SELECT business_id, customer_id INTO v_business_id, v_customer_id
  FROM loans WHERE loan_id = p_loan_id;
  IF v_business_id IS NULL THEN
    RETURN FALSE;
  END IF;
  IF app.is_owner(v_business_id) THEN
    RETURN TRUE;
  END IF;
  RETURN app.agent_covers_customer(v_customer_id) AND EXISTS (
    SELECT 1 FROM customers c
    JOIN business_members bm ON bm.membership_id = c.assigned_agent_membership_id
    JOIN agent_permissions ap ON ap.permission_profile_id = bm.permission_profile_id
    WHERE c.customer_id = v_customer_id
      AND bm.person_id = app.current_person_id()
      AND ap.can_apply_penalty = TRUE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.can_apply_penalty_on_loan(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.apply_loan_penalty
--
-- penalty_entries.penalty_value is NOT NULL and documented as "flat Rs or %
-- as per option", but OW-007's dialog only ever collects one number — a
-- resolved rupee amount — for all three penalty_option values. So for
-- 'Flat Amount' value and applied amount are genuinely the same figure,
-- while for the two '%' options the percentage RATE IS NOT CAPTURED
-- ANYWHERE by the current UI. p_penalty_value is accepted here so a caller
-- that does have the rate can record it truthfully, and defaults to the
-- applied amount otherwise. FLAGGED rather than fabricating a rate by
-- back-solving the amount against the installment/balance: that would
-- produce a number nobody entered and would silently disagree with whatever
-- the Owner actually calculated.
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
  v_penalty_id UUID;
BEGIN
  IF NOT app.can_apply_penalty_on_loan(p_loan_id) THEN
    RAISE EXCEPTION 'Not authorized to apply a penalty on this loan' USING ERRCODE = '42501';
  END IF;
  IF p_penalty_amount IS NULL OR p_penalty_amount <= 0 THEN
    RAISE EXCEPTION 'Penalty amount must be greater than zero' USING ERRCODE = '23514';
  END IF;

  SELECT loan_status INTO v_loan_status FROM loans WHERE loan_id = p_loan_id FOR UPDATE;
  IF v_loan_status IS NULL THEN
    RAISE EXCEPTION 'Loan not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan_status = 'Closed' THEN
    RAISE EXCEPTION 'Cannot apply a penalty to a Closed loan' USING ERRCODE = '23514';
  END IF;

  INSERT INTO penalty_entries (
    loan_id, penalty_option, penalty_value, penalty_amount_applied,
    applied_by_person_id, business_date
  ) VALUES (
    p_loan_id, p_penalty_option, COALESCE(p_penalty_value, p_penalty_amount), p_penalty_amount,
    app.current_person_id(), COALESCE(p_business_date, CURRENT_DATE)
  ) RETURNING penalty_id INTO v_penalty_id;

  UPDATE loans
  SET remaining_balance = remaining_balance + p_penalty_amount, updated_at = now()
  WHERE loan_id = p_loan_id;

  RETURN v_penalty_id;
END;
$$;

COMMENT ON FUNCTION app.apply_loan_penalty(UUID, penalty_option_enum, DECIMAL, DATE, DECIMAL) IS
  'OW-007 Apply Penalty. Atomically inserts penalty_entries and adds the same amount to loans.remaining_balance, per penalty_amount_applied''s own column comment ("resolved Rs amount added to remaining_balance") — the insert+update pair this replaces could half-apply on a dropped connection. Gated on Owner-of-business OR Agent-covers-customer + can_apply_penalty (OFF by default, BR-236). p_penalty_value: see 0054 header — the current UI does not capture a percentage rate for the two % options.';

GRANT EXECUTE ON FUNCTION app.apply_loan_penalty(UUID, penalty_option_enum, DECIMAL, DATE, DECIMAL) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.waive_loan_penalty
--
-- Sets penalty_amount_applied to the NEW effective amount (0 on a full
-- waive, p_reduced_amount on a reduction) and reverses exactly that delta
-- out of loans.remaining_balance, so the column keeps meaning what its
-- comment says it means — the amount currently added to remaining_balance.
--
-- FLAGGED CONSEQUENCE: the originally-applied figure is therefore not
-- preserved anywhere. There is no penalty history/adjustment table in this
-- schema (penalty_entries is the only penalty table, and it has no
-- original_amount column), so the choice was between a consistent pair
-- (amount matches the balance, original lost) and a preserved original that
-- silently disagrees with remaining_balance. Chose consistency. If the
-- original matters for BR-215 Line Score auditing, that needs a real
-- history column/table, not a reinterpretation of this one —
-- is_waived_or_reduced still records THAT it happened.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.waive_loan_penalty(
  p_penalty_id UUID,
  p_waive BOOLEAN,
  p_reduced_amount DECIMAL(14,0) DEFAULT NULL
)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_loan_id UUID;
  v_current DECIMAL(14,0);
  v_waived BOOLEAN;
  v_new_amount DECIMAL(14,0);
  v_delta DECIMAL(14,0);
BEGIN
  SELECT loan_id, penalty_amount_applied, is_waived_or_reduced
  INTO v_loan_id, v_current, v_waived
  FROM penalty_entries WHERE penalty_id = p_penalty_id FOR UPDATE;

  IF v_loan_id IS NULL THEN
    RAISE EXCEPTION 'Penalty entry not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.can_apply_penalty_on_loan(v_loan_id) THEN
    RAISE EXCEPTION 'Not authorized to waive a penalty on this loan' USING ERRCODE = '42501';
  END IF;
  IF v_waived THEN
    RAISE EXCEPTION 'This penalty has already been waived or reduced' USING ERRCODE = '23514';
  END IF;

  IF p_waive THEN
    v_new_amount := 0;
  ELSE
    IF p_reduced_amount IS NULL THEN
      RAISE EXCEPTION 'A reduced amount is required when not waiving in full' USING ERRCODE = '23514';
    END IF;
    IF p_reduced_amount < 0 OR p_reduced_amount >= v_current THEN
      RAISE EXCEPTION 'Reduced amount must be between 0 and the current penalty amount (%)', v_current
        USING ERRCODE = '23514';
    END IF;
    v_new_amount := p_reduced_amount;
  END IF;

  v_delta := v_current - v_new_amount;

  UPDATE penalty_entries
  SET penalty_amount_applied = v_new_amount, is_waived_or_reduced = TRUE
  WHERE penalty_id = p_penalty_id;

  UPDATE loans
  SET remaining_balance = remaining_balance - v_delta, updated_at = now()
  WHERE loan_id = v_loan_id;

  RETURN v_delta;
END;
$$;

COMMENT ON FUNCTION app.waive_loan_penalty(UUID, BOOLEAN, DECIMAL) IS
  'OW-007 Waive/Reduce Penalty. Returns the rupee amount reversed out of loans.remaining_balance. Marks is_waived_or_reduced (BR-215 Line Score Recovery Bonus eligibility) in the same transaction. See 0054 header: the originally-applied amount is not preserved — no penalty history table exists to hold it.';

GRANT EXECUTE ON FUNCTION app.waive_loan_penalty(UUID, BOOLEAN, DECIMAL) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.day_closure_expected — authoritative per-method Expected figures.
--
-- day_ledger tracks ONE closing_balance, with no per-payment-method split,
-- which is why the client-side precheck could only approximate. The real
-- split does exist, one level down: collection_payment_splits.payment_mode
-- (Cash / UPI / Bank Transfer / Cheque, 0008) per collection.
--
-- Derivation, stated explicitly because it is a modelling decision and not
-- something the schema dictates:
--   expected_cash   = opening_balance + cash collections
--                     - loan distribution - expenses
--                     + investor deposits - investor withdrawals
--   expected_upi    = UPI collections
--   expected_bank   = Bank Transfer collections
--   expected_cheque = Cheque collections
-- i.e. only cash physically passes through the till, so the non-cash
-- outflows (loans handed out, expenses paid) and the investor movements are
-- charged against cash; UPI/Bank/Cheque are pass-through totals for the
-- day. If 15_Calculation_Engine.md specifies a different treatment — in
-- particular if loan distribution or expenses can be paid by non-cash
-- methods — this function is the single place to correct it, and both the
-- precheck and the close gate follow automatically.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.day_closure_expected(p_business_id UUID, p_business_date DATE)
RETURNS TABLE(
  expected_cash   DECIMAL(14,0),
  expected_upi    DECIMAL(14,0),
  expected_bank   DECIMAL(14,0),
  expected_cheque DECIMAL(14,0),
  ledger_status   TEXT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_ledger RECORD;
  v_cash DECIMAL(14,0);
  v_upi DECIMAL(14,0);
  v_bank DECIMAL(14,0);
  v_cheque DECIMAL(14,0);
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_ledger FROM day_ledger
  WHERE business_id = p_business_id AND business_date = p_business_date;
  IF v_ledger IS NULL THEN
    RAISE EXCEPTION 'No day_ledger row exists for % on %', p_business_id, p_business_date
      USING ERRCODE = 'P0002';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cash' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'UPI' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Bank Transfer' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cheque' THEN s.amount END), 0)
  INTO v_cash, v_upi, v_bank, v_cheque
  FROM collection_payment_splits s
  JOIN collections c ON c.collection_id = s.collection_id
  JOIN loans l ON l.loan_id = c.loan_id
  WHERE l.business_id = p_business_id AND c.business_date = p_business_date;

  RETURN QUERY SELECT
    v_ledger.opening_balance + v_cash
      - v_ledger.total_loan_distribution - v_ledger.total_expenses
      + v_ledger.investor_deposits - v_ledger.investor_withdrawals,
    v_upi,
    v_bank,
    v_cheque,
    v_ledger.status::TEXT;
END;
$$;

COMMENT ON FUNCTION app.day_closure_expected(UUID, DATE) IS
  'OW-011 per-method Expected figures, derived from collection_payment_splits since day_ledger has no per-method columns. Used by BOTH the advisory client precheck and the authoritative close_business_day gate so the two cannot disagree. Derivation is documented in the 0054 source — cash bears the non-cash outflows, UPI/Bank/Cheque are pass-through collection totals.';

GRANT EXECUTE ON FUNCTION app.day_closure_expected(UUID, DATE) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.close_business_day
--
-- Owner-only (day_closures.closed_by_person_id is documented "Owner only").
-- Re-derives Expected server-side, enforces the BR-043/219 zero-difference
-- hard gate with no override path, and does the day_closures write plus the
-- day_ledger status flip in one transaction.
--
-- Doubles as the "Close Again" path the original stub's §8.6.1 alias note
-- describes: detected from the existing day_closures row's reopened_at
-- rather than from a client-supplied flag. Re-closing UPDATEs that row (a
-- second row would break the one-closure-per-business-day reading of this
-- table and make fetchClosureDetail's .single() throw).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.close_business_day(
  p_business_id UUID,
  p_business_date DATE,
  p_physical_cash DECIMAL(14,0),
  p_upi_balance DECIMAL(14,0),
  p_bank_balance DECIMAL(14,0),
  p_cheque_balance DECIMAL(14,0),
  p_remarks TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_exp RECORD;
  v_expected_total DECIMAL(14,0);
  v_actual_total DECIMAL(14,0);
  v_difference DECIMAL(14,0);
  v_pending_drafts INT;
  v_closure_id UUID;
  v_existing_closure UUID;
  v_existing_reopened TIMESTAMP;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may close a business day' USING ERRCODE = '42501';
  END IF;

  -- Lock the ledger row first: it is the one row every concurrent close
  -- attempt for this business day must contend on.
  PERFORM 1 FROM day_ledger
  WHERE business_id = p_business_id AND business_date = p_business_date
  FOR UPDATE;

  SELECT * INTO v_exp FROM app.day_closure_expected(p_business_id, p_business_date);

  SELECT closure_id, reopened_at INTO v_existing_closure, v_existing_reopened
  FROM day_closures
  WHERE business_id = p_business_id AND business_date = p_business_date
  FOR UPDATE;

  IF v_existing_closure IS NOT NULL AND v_existing_reopened IS NULL THEN
    RAISE EXCEPTION 'This business day is already closed — reopen it first (BR-221)'
      USING ERRCODE = '23505';
  END IF;

  -- Server-authoritative repeat of the client precheck's blocking issue.
  -- Same collection_drafts proxy the Dart side documents (no business_date
  -- column on that table; created_at by calendar day is the closest
  -- available signal) — flagged there, mirrored here rather than silently
  -- letting the server be more permissive than the screen.
  SELECT COUNT(*) INTO v_pending_drafts
  FROM collection_drafts cd
  JOIN business_members bm ON bm.membership_id = cd.created_by_membership_id
  WHERE bm.business_id = p_business_id
    AND cd.status = 'Draft'
    AND cd.created_at::DATE = p_business_date;

  IF v_pending_drafts > 0 THEN
    RAISE EXCEPTION 'Cannot close: % pending unsaved draft(s) for this business day', v_pending_drafts
      USING ERRCODE = '23514';
  END IF;

  v_expected_total := v_exp.expected_cash + v_exp.expected_upi + v_exp.expected_bank + v_exp.expected_cheque;
  v_actual_total := p_physical_cash + p_upi_balance + p_bank_balance + p_cheque_balance;
  v_difference := v_actual_total - v_expected_total;

  -- BR-043/219 hard gate. Deliberately no force/override parameter: the
  -- Owner's route past a real difference is the Difference Analyzer
  -- (record_day_closure_adjustment) followed by another close attempt, not
  -- a flag on this call.
  IF v_difference <> 0 THEN
    RAISE EXCEPTION 'Cannot close: Expected % vs Actual % leaves a difference of % — must be zero (BR-043/219)',
      v_expected_total, v_actual_total, v_difference
      USING ERRCODE = '23514';
  END IF;

  IF v_existing_closure IS NOT NULL THEN
    UPDATE day_closures SET
      physical_cash = p_physical_cash,
      upi_balance = p_upi_balance,
      bank_balance = p_bank_balance,
      cheque_balance = p_cheque_balance,
      expected_cash = v_exp.expected_cash,
      expected_upi = v_exp.expected_upi,
      expected_bank = v_exp.expected_bank,
      expected_cheque = v_exp.expected_cheque,
      difference = v_difference,
      closed_by_person_id = app.current_person_id(),
      closed_at = now(),
      reopened_at = NULL,
      reopen_reason = NULL
    WHERE closure_id = v_existing_closure
    RETURNING closure_id INTO v_closure_id;
  ELSE
    INSERT INTO day_closures (
      business_id, business_date, physical_cash, upi_balance, bank_balance, cheque_balance,
      expected_cash, expected_upi, expected_bank, expected_cheque, difference, closed_by_person_id
    ) VALUES (
      p_business_id, p_business_date, p_physical_cash, p_upi_balance, p_bank_balance, p_cheque_balance,
      v_exp.expected_cash, v_exp.expected_upi, v_exp.expected_bank, v_exp.expected_cheque,
      v_difference, app.current_person_id()
    ) RETURNING closure_id INTO v_closure_id;
  END IF;

  -- day_ledger.closing_balance is deliberately NOT overwritten with the
  -- counted total: the gate above already proved they are equal, so writing
  -- it would be a no-op that looks like a recalculation. Only status and the
  -- optional remarks change here. short_amount/excess_amount likewise stay
  -- untouched — they can only be non-zero for a difference this function
  -- refuses to close on.
  UPDATE day_ledger SET
    status = 'Closed',
    remarks = COALESCE(p_remarks, remarks)
  WHERE business_id = p_business_id AND business_date = p_business_date;

  RETURN json_build_object(
    'closure_id', v_closure_id,
    'business_date', p_business_date,
    'difference', v_difference,
    'closing_balance', v_actual_total,
    'status', 'Closed'
  );
END;
$$;

COMMENT ON FUNCTION app.close_business_day(UUID, DATE, DECIMAL, DECIMAL, DECIMAL, DECIMAL, TEXT) IS
  'OW-011 Close Business Day. Re-derives Expected via app.day_closure_expected, enforces the BR-043/219 zero-difference hard gate (no override parameter exists by design), and performs the day_closures write + day_ledger status flip atomically. Also serves the Close Again path, detected from the existing row''s reopened_at — re-closing updates that row rather than inserting a second one for the same business day.';

GRANT EXECUTE ON FUNCTION app.close_business_day(UUID, DATE, DECIMAL, DECIMAL, DECIMAL, DECIMAL, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.record_day_closure_adjustment — Difference Analyzer Short/Excess row.
-- Writes the business_id added at the top of this migration, which is what
-- makes the row readable afterwards. applied_to is Owner-controlled and
-- never automatic (BR-069), so it is a required parameter with no default.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_day_closure_adjustment(
  p_business_id UUID,
  p_business_date DATE,
  p_adjustment_type adjustment_type_enum,
  p_amount DECIMAL(14,0),
  p_applied_to adjustment_applied_to_enum,
  p_target_customer_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_adjustment_id UUID;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may record a day closure adjustment' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Adjustment amount must be greater than zero' USING ERRCODE = '23514';
  END IF;

  IF p_applied_to = 'Customer Pending Settlement' AND p_target_customer_id IS NULL THEN
    RAISE EXCEPTION 'target_customer_id is required when applied_to is Customer Pending Settlement'
      USING ERRCODE = '23514';
  END IF;

  -- A customer named here must actually belong to this business, or the
  -- adjustment would point across a tenancy boundary.
  IF p_target_customer_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM customers c
    JOIN business_members bm ON bm.membership_id = c.membership_id
    WHERE c.customer_id = p_target_customer_id AND bm.business_id = p_business_id
  ) THEN
    RAISE EXCEPTION 'Target customer does not belong to this business' USING ERRCODE = '23514';
  END IF;

  INSERT INTO settlement_adjustments (
    business_id, adjustment_type, amount, applied_to, target_customer_id, business_date
  ) VALUES (
    p_business_id, p_adjustment_type, p_amount, p_applied_to, p_target_customer_id, p_business_date
  ) RETURNING adjustment_id INTO v_adjustment_id;

  RETURN v_adjustment_id;
END;
$$;

COMMENT ON FUNCTION app.record_day_closure_adjustment(UUID, DATE, adjustment_type_enum, DECIMAL, adjustment_applied_to_enum, UUID) IS
  'OW-011 Difference Analyzer Short/Excess adjustment. settlement_id and agent_id are both NULL for a business-day adjustment — the business_id column added in 0054 is what keeps the row visible to the Owner who created it (see 0054 header for why a raw insert was impossible before). resolved defaults FALSE: recording the adjustment does not itself resolve it.';

GRANT EXECUTE ON FUNCTION app.record_day_closure_adjustment(UUID, DATE, adjustment_type_enum, DECIMAL, adjustment_applied_to_enum, UUID) TO authenticated;

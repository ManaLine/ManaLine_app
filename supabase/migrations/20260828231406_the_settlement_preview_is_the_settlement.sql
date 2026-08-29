-- Total Amount read Rs 0 on a screen whose home said Rs 5,08,930.
--
-- The preview was computed on the phone: opening_bf (0, and never updated
-- since the float was granted) plus collections inside the period's PLANNED
-- dates (18 to 21 August, so none of the last week's), minus loans and
-- expenses in the same dead window. Zero from three directions at once.
--
-- The deeper problem is that it was a second implementation of the same sum.
-- The file even says so: "explicitly a best-effort estimate, not a guaranteed
-- match for whatever submit_agent_settlement produces". An estimate is a
-- reasonable thing to show for a queue length. It is not a reasonable thing
-- to show as the amount of money somebody is about to hand over.
--
-- One function, used by the screen to show and by the submit to record.
--
-- On what is green and what is red: this is a CASH reconciliation, and it
-- adds up. Interest and processing fee are deliberately not lines in it --
-- they are withheld at disbursement (amount_given = repayment - interest -
-- fee), so they never pass through the agent's hands as cash, and the
-- interest a customer repays is already inside the collection figure.
-- Listing them again as income would double count and the total would stop
-- matching the money in the tin. They are returned separately, marked as
-- earnings rather than movements, so a screen can show them without adding
-- them up.
CREATE OR REPLACE FUNCTION app.settlement_preview(p_agent_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_membership_id UUID;
  v_business_id UUID;
  v_period_id UUID;
  v_start DATE;
  v_end DATE;
  v_opening DECIMAL(14,0) := 0;
  v_cash DECIMAL(14,0) := 0;
  v_upi DECIMAL(14,0) := 0;
  v_bank DECIMAL(14,0) := 0;
  v_cheque DECIMAL(14,0) := 0;
  v_loans DECIMAL(14,0) := 0;
  v_expenses DECIMAL(14,0) := 0;
  v_in DECIMAL(14,0) := 0;
  v_out DECIMAL(14,0) := 0;
  v_interest DECIMAL(14,0) := 0;
  v_fees DECIMAL(14,0) := 0;
  v_held DECIMAL(14,0) := 0;
BEGIN
  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'No such agent' USING ERRCODE = 'P0002';
  END IF;

  SELECT bm.business_id INTO v_business_id
    FROM business_members bm WHERE bm.membership_id = v_membership_id;

  IF NOT app.membership_belongs_to_current_person(v_membership_id)
     AND NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Not your account' USING ERRCODE = '42501';
  END IF;

  SELECT ap.account_period_id, ap.business_start_date::date
    INTO v_period_id, v_start
    FROM account_periods ap
   WHERE ap.agent_membership_id = v_membership_id AND ap.status = 'Running'
   ORDER BY ap.business_start_date DESC
   LIMIT 1;

  -- No open period: the figures still describe what is held, which is what
  -- the screen exists to show.
  v_start := COALESCE(v_start, CURRENT_DATE);
  v_end := GREATEST(CURRENT_DATE, v_start);

  SELECT COALESCE(opening_bf, 0), COALESCE(agent_bf_current, 0)
    INTO v_opening, v_held
    FROM agent_bf_assignments
   WHERE membership_id = v_membership_id
   ORDER BY business_date DESC NULLS LAST, created_at DESC
   LIMIT 1;
  v_opening := COALESCE(v_opening, 0);
  v_held := COALESCE(v_held, 0);

  SELECT COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cash'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'UPI'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Bank Transfer'), 0),
         COALESCE(SUM(s.amount) FILTER (WHERE s.payment_mode = 'Cheque'), 0)
    INTO v_cash, v_upi, v_bank, v_cheque
    FROM collections c
    JOIN collection_payment_splits s ON s.collection_id = c.collection_id
   WHERE c.collected_by_membership_id = v_membership_id
     AND c.deleted_at IS NULL
     AND c.business_date BETWEEN v_start AND v_end;

  SELECT COALESCE(SUM(l.amount_given), 0),
         COALESCE(SUM(l.interest_amount), 0),
         COALESCE(SUM(l.processing_fee), 0)
    INTO v_loans, v_interest, v_fees
    FROM loans l
   WHERE l.collection_agent_membership_id = v_membership_id
     AND l.deleted_at IS NULL
     AND l.issue_business_date BETWEEN v_start AND v_end;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
    FROM expenses e
   WHERE e.recorded_by_membership_id = v_membership_id
     AND e.deleted_at IS NULL
     AND e.business_date BETWEEN v_start AND v_end;

  SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.to_agent_id = p_agent_id), 0),
         COALESCE(SUM(t.amount) FILTER (WHERE t.from_agent_id = p_agent_id), 0)
    INTO v_in, v_out
    FROM cash_transfers t
   WHERE (t.from_agent_id = p_agent_id OR t.to_agent_id = p_agent_id)
     AND t.from_agent_confirmed_at IS NOT NULL
     AND t.to_agent_confirmed_at IS NOT NULL
     AND t.business_date BETWEEN v_start AND v_end;

  RETURN json_build_object(
    'account_period_id', v_period_id,
    'period_from', v_start,
    'period_to', v_end,
    -- The lines that add up, in the order they are read.
    'opening_bf', v_opening,
    'cash_collected', v_cash,
    'upi_collected', v_upi,
    'bank_collected', v_bank,
    'cheque_collected', v_cheque,
    'transfers_in', v_in,
    'loans_issued', v_loans,
    'expenses', v_expenses,
    'transfers_out', v_out,
    -- What the agent is holding, derived from the live float rather than
    -- from the sum above -- the two agree, and where they ever disagree the
    -- float is the money and the sum is the story.
    'total_held', v_held,
    -- Earned, not moved. Never added into the total; see the header.
    'interest_earned', v_interest,
    'processing_fees', v_fees
  );
END;
$$;

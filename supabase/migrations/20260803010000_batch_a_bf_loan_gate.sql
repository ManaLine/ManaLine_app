-- =============================================================================
-- BATCH A (1/6) — BF model: money-rpc scoping helper + loan-issue gate
-- =============================================================================
-- This is the first of six new migrations written as part of the "Batch A"
-- money fix. They were agreed one-by-one with the Owner in review. Each
-- migration is independent (applies cleanly on top of whatever came before).
--
-- WHAT THIS FILE DOES (plain language):
--   1. Gives the "is this caller a permitted agent?" check an optional third
--      argument: the BUSINESS the money must move in. Without it, an agent
--      of business A could act on loans of business B using their A
--      membership. The loan-issue and collection RPCs now pass the business.
--   2. Fixes create_loan_with_bf_check (the "issue a loan" function):
--        a. the agent must be permitted in THIS business (not just any);
--        b. the loan's "amount given" must be a real positive number — a
--           loan with repayment smaller than interest+fee would otherwise
--           create a NEGATIVE amount and add cash to the agent's BF by
--           mistake;
--        c. if the agent's BF (cash in hand) is too small, return a clear
--           "INSUFFICIENT_FLOAT" answer instead of a scary database error,
--           so the app can show "ask Owner to add BF" and save the entry
--           as a draft;
--        d. deduct the agent's BF from the ONE exact BF row we checked,
--           not every row that happens to share the same date (a bug that
--           could deduct twice).
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Extended helper: own_active_agent_membership_permits(membership, perm, business?)
--    The old two-argument version is kept — it is still used by self-scoped
--    checks (draft ownership) where the business is implied by the membership
--    itself. The new three-argument version is the one money-moving RPCs must
--    use so a membership is only honoured in its OWN business.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.own_active_agent_membership_permits(
  p_membership_id UUID,
  p_permission_column TEXT,
  p_business_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members bm
    WHERE bm.membership_id = p_membership_id
      AND bm.person_id = app.current_person_id()
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
      AND (p_business_id IS NULL OR bm.business_id = p_business_id)
      AND app.agent_permission(bm.business_id, p_permission_column)
  );
$$;

COMMENT ON FUNCTION app.own_active_agent_membership_permits(UUID, TEXT, UUID) IS
  'Fails-closed check: is the caller an ACTIVE Agent, in the given business (when supplied), with the given permission? NULL business keeps the old self-scoped behaviour for non-money checks.';

-- ---------------------------------------------------------------------------
-- 2. create_loan_with_bf_check — redefined (same name, same 14 inputs, same
--    JSON answer as the 0024 version) with the four fixes above.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.create_loan_with_bf_check(
  p_customer_id UUID,
  p_business_id UUID,
  p_repayment_amount DECIMAL(14,0),
  p_interest_amount DECIMAL(14,0),
  p_processing_fee DECIMAL(14,0),
  p_repayment_type repayment_frequency_enum,
  p_duration_value INT,
  p_installment_amount DECIMAL(14,0),
  p_grace_period_days INT,
  p_collection_agent_membership_id UUID,
  p_effective_date DATE,
  p_live_photo_url TEXT,
  p_template_id UUID DEFAULT NULL,
  p_penalty_template_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT;
  v_amount_given DECIMAL(14,0);
  v_bf_current DECIMAL(14,0);
  v_assignment_id UUID;           -- the exact BF row we validated against
  v_loan_id UUID;
  v_loan_number VARCHAR(30);
  v_interval INTERVAL;
  i INT;
BEGIN
  v_person_id := app.current_person_id();

  -- Authorization: Owner of THIS business, or an agent permitted in THIS
  -- business. (The third helper argument is the cross-business fix.)
  IF NOT app.is_owner(p_business_id) AND NOT app.own_active_agent_membership_permits(p_collection_agent_membership_id, 'can_issue_loans', p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to issue loans for this business' USING ERRCODE = '42501';
  END IF;

  -- The loan's "amount given" (cash handed to the customer) must be a real
  -- positive number. Without this a repayment smaller than interest+fee
  -- would produce a NEGATIVE amount_given, which the BF deduction below
  -- would turn into cash ADDED to the agent — a loan that mints money.
  v_amount_given := p_repayment_amount - p_interest_amount - p_processing_fee;
  IF p_repayment_amount <= 0 OR p_interest_amount < 0 OR p_processing_fee < 0
     OR v_amount_given <= 0 THEN
    RAISE EXCEPTION 'Loan amounts invalid: repayment must be larger than interest + processing fee' USING ERRCODE = '23514';
  END IF;
  IF p_duration_value <= 0 OR p_installment_amount <= 0 OR p_grace_period_days < 0 THEN
    RAISE EXCEPTION 'Loan terms invalid: duration and installment must be positive, grace cannot be negative' USING ERRCODE = '23514';
  END IF;

  -- Read the agent's current cash (BF) AND the exact row it lives on,
  -- locked so two loans cannot both spend the same cash.
  SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_bf_current
  FROM agent_bf_assignments
  WHERE membership_id = p_collection_agent_membership_id
  ORDER BY business_date DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  -- Not enough cash in hand: say so clearly (the app saves a draft and
  -- asks the Owner to top the agent up) instead of raising a raw error.
  IF v_bf_current IS NULL OR v_bf_current < v_amount_given THEN
    RETURN json_build_object(
      'passed', false,
      'failure_reason', 'INSUFFICIENT_FLOAT',
      'float_current', COALESCE(v_bf_current, 0),
      'required', v_amount_given
    );
  END IF;

  v_loan_number := 'LN-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO loans (
    loan_number, customer_id, business_id, template_id, repayment_amount, interest_amount,
    processing_fee, repayment_type, duration_value, installment_amount, grace_period_days,
    penalty_template_note, remaining_balance, collection_agent_membership_id, effective_date,
    loan_status, issue_business_date, live_photo_url
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, p_template_id, p_repayment_amount, p_interest_amount,
    p_processing_fee, p_repayment_type, p_duration_value, p_installment_amount, p_grace_period_days,
    p_penalty_template_note, p_repayment_amount, p_collection_agent_membership_id, p_effective_date,
    'Active', p_effective_date, p_live_photo_url
  ) RETURNING loan_id INTO v_loan_id;

  -- Generate the installment schedule (one row per repayment, simple
  -- equal-installment generator, same as before).
  v_interval := CASE p_repayment_type
    WHEN 'Daily' THEN INTERVAL '1 day'
    WHEN 'Weekly' THEN INTERVAL '7 days'
    WHEN 'Monthly' THEN INTERVAL '1 month'
  END;

  FOR i IN 1..p_duration_value LOOP
    INSERT INTO loan_schedule (loan_id, installment_number, due_date, installment_amount, status)
    VALUES (v_loan_id, i, (p_effective_date + (v_interval * i))::DATE, p_installment_amount, 'Pending');
  END LOOP;

  -- Deduct the cash handed out from the ONE BF row we validated against.
  -- (The old code deducted every row sharing the latest date — a loan
  -- could subtract twice.)
  UPDATE agent_bf_assignments
  SET agent_bf_current = agent_bf_current - v_amount_given, updated_at = now()
  WHERE assignment_id = v_assignment_id;

  RETURN json_build_object('passed', true, 'loan_id', v_loan_id, 'loan_number', v_loan_number);
END;
$$;

COMMENT ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) IS
  'OW-005/AG-007 loan issuance. Gated on the issuing AGENT''s cash-in-hand (agent_bf_current), business-scoped. Returns {passed:false,failure_reason:''INSUFFICIENT_FLOAT''} when the agent lacks cash — the app saves a draft and the Owner tops up via app.grant_agent_bf. Guarantor insert stays client-side after this RPC returns.';

GRANT EXECUTE ON FUNCTION app.create_loan_with_bf_check(UUID, UUID, DECIMAL, DECIMAL, DECIMAL, repayment_frequency_enum, INT, DECIMAL, INT, UUID, DATE, TEXT, UUID, TEXT) TO authenticated;

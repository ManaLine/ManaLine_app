-- =============================================================================
-- BATCH A (5/6) — cash transfers now actually move the cash, and only
-- between agents of the same business
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   A cash transfer is one agent giving cash to another on the same team.
--   Until now the transfer was only a RECORD (both sides tick "yes") — the
--   cash itself never moved between their balances, so one agent could
--   "hand over" money and still be owed it at hand-over time.
--
--   1. initiate_cash_transfer: the sender is always whoever is logged in
--      (never trusted from the phone), must belong to the SAME business as
--      the receiver, must be sending a positive amount, and must actually
--      have that much cash in hand right now.
--   2. confirm_cash_transfer: records the confirming side. Only when BOTH
--      sides have confirmed does the cash actually move — sender's float
--      down, receiver's float up — and that happens exactly once.
--   3. A transfer amount can never be zero or negative.
-- -----------------------------------------------------------------------------

-- Transfer amounts must be real money.
ALTER TABLE cash_transfers
  ADD CONSTRAINT chk_cash_transfers_amount_positive CHECK (amount > 0);

-- ---------------------------------------------------------------------------
-- 1. initiate_cash_transfer — same inputs as before, now with the checks.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.initiate_cash_transfer(p_to_agent_id UUID, p_amount DECIMAL(14,0), p_business_date DATE)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_from_agent_id UUID;
  v_from_membership_id UUID;
  v_from_business_id UUID;
  v_to_business_id UUID;
  v_bf DECIMAL(14,0);
  v_transfer_id UUID;
BEGIN
  -- The sender is the logged-in person's ACTIVE agent membership — always
  -- resolved server-side, never taken from the phone.
  SELECT a.agent_id, bm.membership_id, bm.business_id
    INTO v_from_agent_id, v_from_membership_id, v_from_business_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE bm.person_id = app.current_person_id()
    AND bm.role = 'Agent'
    AND bm.membership_status = 'Active'
  LIMIT 1;

  IF v_from_agent_id IS NULL THEN
    RAISE EXCEPTION 'Caller is not an agent' USING ERRCODE = '42501';
  END IF;
  IF v_from_agent_id = p_to_agent_id THEN
    RAISE EXCEPTION 'Cannot transfer to self' USING ERRCODE = '23514';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive' USING ERRCODE = '23514';
  END IF;

  -- Both agents must serve the SAME business.
  SELECT bm.business_id INTO v_to_business_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE a.agent_id = p_to_agent_id;
  IF v_to_business_id IS NULL OR v_to_business_id <> v_from_business_id THEN
    RAISE EXCEPTION 'Transfers are only allowed between agents of the same business' USING ERRCODE = '42501';
  END IF;

  -- The sender must have the cash in hand right now.
  SELECT agent_bf_current INTO v_bf
  FROM agent_bf_assignments
  WHERE membership_id = v_from_membership_id
  ORDER BY business_date DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;
  IF v_bf IS NULL OR v_bf < p_amount THEN
    RAISE EXCEPTION 'Insufficient BF to transfer: available % < required %', COALESCE(v_bf, 0), p_amount USING ERRCODE = '23514';
  END IF;

  INSERT INTO cash_transfers (from_agent_id, to_agent_id, amount, business_date, from_agent_confirmed_at)
  VALUES (v_from_agent_id, p_to_agent_id, p_amount, p_business_date, now())
  RETURNING transfer_id INTO v_transfer_id;

  RETURN v_transfer_id;
END;
$$;

COMMENT ON FUNCTION app.initiate_cash_transfer(UUID, DECIMAL, DATE) IS
  'AG-007. Starts a transfer. Sender resolved server-side from the logged-in person, same-business enforced, sender must have the cash. Returns the new transfer_id.';

GRANT EXECUTE ON FUNCTION app.initiate_cash_transfer(UUID, DECIMAL, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. confirm_cash_transfer — same inputs; the cash moves on the second tick.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.confirm_cash_transfer(p_transfer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_caller_agent_id UUID;
  v_from UUID;
  v_to UUID;
  v_amount DECIMAL(14,0);
  v_from_confirmed BOOLEAN;
  v_to_confirmed BOOLEAN;
  v_from_membership UUID;
  v_to_membership UUID;
  v_from_assignment UUID;
  v_to_assignment UUID;
  v_from_float DECIMAL(14,0);
  v_transfer_business_date DATE;
BEGIN
  -- The confirming side is whoever is logged in.
  SELECT a.agent_id INTO v_caller_agent_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE bm.person_id = app.current_person_id()
    AND bm.role = 'Agent'
    AND bm.membership_status = 'Active'
  LIMIT 1;

  -- Lock the transfer so two confirmations cannot both be the "second" one.
  SELECT from_agent_id, to_agent_id, amount, business_date,
         from_agent_confirmed_at IS NOT NULL, to_agent_confirmed_at IS NOT NULL
    INTO v_from, v_to, v_amount, v_transfer_business_date, v_from_confirmed, v_to_confirmed
  FROM cash_transfers
  WHERE transfer_id = p_transfer_id
  FOR UPDATE;

  IF v_from IS NULL THEN
    RAISE EXCEPTION 'Transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_caller_agent_id IS NULL OR (v_caller_agent_id <> v_from AND v_caller_agent_id <> v_to) THEN
    RAISE EXCEPTION 'Not a party to this transfer' USING ERRCODE = '42501';
  END IF;

  -- Tick this side's confirmation. A repeat tap from a side that has
  -- already confirmed is a no-op (RETURN) so the cash can never move twice.
  IF v_caller_agent_id = v_from THEN
    IF v_from_confirmed THEN RETURN; END IF;
    UPDATE cash_transfers SET from_agent_confirmed_at = now() WHERE transfer_id = p_transfer_id;
    v_from_confirmed := true;
  ELSIF v_caller_agent_id = v_to THEN
    IF v_to_confirmed THEN RETURN; END IF;
    UPDATE cash_transfers SET to_agent_confirmed_at = now() WHERE transfer_id = p_transfer_id;
    v_to_confirmed := true;
  END IF;

  -- Only now, with BOTH ticks on the locked row, does the cash move —
  -- sender's float down, receiver's float up, exactly once.
  IF v_from_confirmed AND v_to_confirmed THEN
    SELECT bm.membership_id INTO v_from_membership
    FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id
    WHERE a.agent_id = v_from;
    SELECT bm.membership_id INTO v_to_membership
    FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id
    WHERE a.agent_id = v_to;

    -- The sender must still have the cash at this moment.
    SELECT assignment_id, agent_bf_current INTO v_from_assignment, v_from_float
    FROM agent_bf_assignments
    WHERE membership_id = v_from_membership
    ORDER BY business_date DESC NULLS LAST
    LIMIT 1
    FOR UPDATE;
    IF v_from_assignment IS NULL OR v_from_float < v_amount THEN
      RAISE EXCEPTION 'Insufficient BF to complete the transfer' USING ERRCODE = '23514';
    END IF;

    -- Credit the receiver; create their BF row first if they have none.
    SELECT assignment_id INTO v_to_assignment
    FROM agent_bf_assignments
    WHERE membership_id = v_to_membership
    ORDER BY business_date DESC NULLS LAST
    LIMIT 1
    FOR UPDATE;
    IF v_to_assignment IS NULL THEN
      INSERT INTO agent_bf_assignments (membership_id, business_date, opening_bf, agent_bf_current, confirmed_by_agent)
      VALUES (v_to_membership, v_transfer_business_date, 0, v_amount, false);
    ELSE
      UPDATE agent_bf_assignments
      SET agent_bf_current = agent_bf_current + v_amount, updated_at = now()
      WHERE assignment_id = v_to_assignment;
    END IF;

    UPDATE agent_bf_assignments
    SET agent_bf_current = agent_bf_current - v_amount, updated_at = now()
    WHERE assignment_id = v_from_assignment;
  END IF;
END;
$$;

COMMENT ON FUNCTION app.confirm_cash_transfer(UUID) IS
  'AG-007. Resolves which side the caller is server-side. The cash moves (sender float down, receiver float up) only on the second confirmation, guarded by the locked row so it happens exactly once.';

GRANT EXECUTE ON FUNCTION app.confirm_cash_transfer(UUID) TO authenticated;

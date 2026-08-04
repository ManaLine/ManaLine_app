-- =============================================================================
-- BATCH A (3/6) — Owner BF top-up + expense recording + non-negative guard
-- =============================================================================
-- WHAT THIS FILE DOES (plain language):
--   1. grant_agent_bf: when an agent runs out of cash, the Owner moves money
--      from the Owner's own balance into the agent's cash (BF). The Owner
--      cannot give money they do not have, so the Owner's balance is checked
--      first.
--   2. record_expense: recording a business expense deducts it from whoever
--      paid it — the Owner's balance if the Owner paid, the agent's BF if an
--      agent paid. (Until now expenses were plain direct inserts with no
--      cash deduction at all, so an agent's expense never reduced what they
--      owe the Owner.)
--   3. HARD RULES: BF can never go below zero for an Owner or an agent.
--      Every RPC above checks before deducting; these CHECK constraints are
--      the database's last line of defence if some future code forgets.
-- -----------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. grant_agent_bf — Owner moves their own cash into an agent's BF.
--    Returns the agent's new float so the app can show it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.grant_agent_bf(p_agent_membership_id UUID, p_amount DECIMAL(14,0))
RETURNS DECIMAL(14,0)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_owner_bf DECIMAL(14,0);
  v_assignment_id UUID;
  v_agent_bf DECIMAL(14,0);
BEGIN
  -- The membership must exist, and only the Owner of its business may grant.
  v_business_id := app.business_id_for_membership(p_agent_membership_id);
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Membership not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may grant BF' USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Top-up amount must be positive' USING ERRCODE = '23514';
  END IF;

  -- Lock the Owner's balance and make sure it covers the top-up.
  SELECT owner_bf_balance INTO v_owner_bf
  FROM businesses WHERE business_id = v_business_id FOR UPDATE;
  IF v_owner_bf < p_amount THEN
    RAISE EXCEPTION 'Owner BF is only %, cannot top up %', v_owner_bf, p_amount USING ERRCODE = '23514';
  END IF;

  -- Add to the agent's current float; create a BF row first if the agent
  -- has never been granted one (they need one to lend and collect).
  SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_agent_bf
  FROM agent_bf_assignments
  WHERE membership_id = p_agent_membership_id
  ORDER BY business_date DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_assignment_id IS NULL THEN
    INSERT INTO agent_bf_assignments (membership_id, business_date, opening_bf, agent_bf_current, confirmed_by_agent)
    VALUES (p_agent_membership_id, CURRENT_DATE, 0, p_amount, false)
    RETURNING assignment_id INTO v_assignment_id;
    v_agent_bf := p_amount;
  ELSE
    v_agent_bf := v_agent_bf + p_amount;
    UPDATE agent_bf_assignments
    SET agent_bf_current = v_agent_bf, updated_at = now()
    WHERE assignment_id = v_assignment_id;
  END IF;

  -- Move the money: Owner down, Agent up — one transaction.
  UPDATE businesses SET owner_bf_balance = owner_bf_balance - p_amount
  WHERE business_id = v_business_id;

  RETURN v_agent_bf;
END;
$$;

COMMENT ON FUNCTION app.grant_agent_bf(UUID, DECIMAL) IS
  'M3 top-up. Owner moves their own cash (owner_bf_balance) into an agent''s BF. Gated on the Owner having the cash. Returns the agent''s new float.';

GRANT EXECUTE ON FUNCTION app.grant_agent_bf(UUID, DECIMAL) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2a. can_record_expenses — the permission column itself. The workforce
--     screen (ow_002) already toggles this flag, but the agent_permissions
--     table had no such column — the toggle would have errored. Expenses
--     RLS previously guessed at can_perform_day_settlement instead. Both
--     now line up on the real BR-236-style flag, OFF by default.
-- ---------------------------------------------------------------------------
-- IF NOT EXISTS: both columns were already added by the earlier
-- "permissions tab / toggle the server does not hold" fix, so a bare
-- ADD COLUMN aborts this migration on any database that has it.
ALTER TABLE agent_permissions
  ADD COLUMN IF NOT EXISTS can_record_expenses BOOLEAN NOT NULL DEFAULT FALSE,
  -- Same fix for can_migrate_records: the workforce screen toggles it, but
  -- the column never existed in the table either.
  ADD COLUMN IF NOT EXISTS can_migrate_records BOOLEAN NOT NULL DEFAULT FALSE;

-- Align the expenses INSERT policy with the new flag (was the guessed
-- can_perform_day_settlement).
DROP POLICY IF EXISTS expenses_agent_insert_own ON expenses;
CREATE POLICY expenses_agent_insert_own ON expenses
  FOR INSERT
  WITH CHECK (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_record_expenses')
    AND recorded_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

-- ---------------------------------------------------------------------------
-- 2. record_expense — records the expense AND deducts it from the payer's
--    own cash, so an agent's expenses reduce what they owe at hand-over.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.record_expense(
  p_business_id UUID,
  p_category expense_category_enum,
  p_amount DECIMAL(14,0),
  p_membership_id UUID,
  p_business_date DATE,
  p_remarks TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_expense_id UUID;
  v_role business_member_role_enum;
  v_owner_bf DECIMAL(14,0);
  v_assignment_id UUID;
  v_agent_bf DECIMAL(14,0);
BEGIN
  -- The Owner, or an agent of THIS business holding the can_record_expenses
  -- permission (BR-236 pattern, OFF by default).
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(p_membership_id, 'can_record_expenses', p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record expenses in this business' USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Expense amount must be positive' USING ERRCODE = '23514';
  END IF;

  -- Deduct the cash from whoever paid it, exactly like a collection credits it.
  SELECT role INTO v_role FROM business_members WHERE membership_id = p_membership_id;
  IF v_role = 'Owner' THEN
    SELECT owner_bf_balance INTO v_owner_bf
    FROM businesses WHERE business_id = p_business_id FOR UPDATE;
    IF v_owner_bf < p_amount THEN
      RAISE EXCEPTION 'Owner BF is only %, cannot pay a % expense', v_owner_bf, p_amount USING ERRCODE = '23514';
    END IF;
    UPDATE businesses SET owner_bf_balance = owner_bf_balance - p_amount
    WHERE business_id = p_business_id;
  ELSIF v_role = 'Agent' THEN
    SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_agent_bf
    FROM agent_bf_assignments
    WHERE membership_id = p_membership_id
    ORDER BY business_date DESC NULLS LAST
    LIMIT 1
    FOR UPDATE;
    IF v_assignment_id IS NULL THEN
      RAISE EXCEPTION 'No BF assignment for this agent — the Owner must grant BF first' USING ERRCODE = 'P0002';
    END IF;
    IF v_agent_bf < p_amount THEN
      RAISE EXCEPTION 'Agent BF is only %, cannot pay a % expense', v_agent_bf, p_amount USING ERRCODE = '23514';
    END IF;
    UPDATE agent_bf_assignments
    SET agent_bf_current = agent_bf_current - p_amount, updated_at = now()
    WHERE assignment_id = v_assignment_id;
  ELSE
    RAISE EXCEPTION 'Expenses can only be paid by the Owner or an Agent' USING ERRCODE = '42501';
  END IF;

  INSERT INTO expenses (business_id, category, amount, recorded_by_membership_id, business_date, remarks)
  VALUES (p_business_id, p_category, p_amount, p_membership_id, p_business_date, p_remarks)
  RETURNING expense_id INTO v_expense_id;

  RETURN v_expense_id;
END;
$$;

COMMENT ON FUNCTION app.record_expense(UUID, expense_category_enum, DECIMAL, UUID, DATE, TEXT) IS
  'Records an expense and deducts it from the payer''s own cash (Owner BF or agent float) in the same transaction. Gated on the payer having the cash.';

GRANT EXECUTE ON FUNCTION app.record_expense(UUID, expense_category_enum, DECIMAL, UUID, DATE, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. HARD RULES — BF can never go negative. (Backstop to the RPC checks.)
-- ---------------------------------------------------------------------------
ALTER TABLE businesses
  ADD CONSTRAINT chk_businesses_owner_bf_nonneg CHECK (owner_bf_balance >= 0);

ALTER TABLE agent_bf_assignments
  ADD CONSTRAINT chk_agent_bf_current_nonneg CHECK (agent_bf_current >= 0);

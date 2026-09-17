-- app.agent_expected_closing counted deleted rows. Named as still-open when
-- the collections half of it was fixed earlier today, and fixed now.
--
-- FOUR GAPS, NOT THE TWO I FIRST COUNTED. loans and expenses were the obvious
-- pair; cash_transfers carries deleted_at too and is read twice, once in each
-- direction. All four are soft-deletable from the app -- DeletableEntity lists
-- loan, expense and cash_transfer -- so every one of these is reachable by an
-- Owner pressing Delete, not a theoretical hole.
--
-- WHICH WAY IT WAS WRONG. This function ends with
--   expected_cash_closing := opening + cash - disbursed - expenses + in - out
-- so a deleted loan or a deleted expense still counted makes the expected
-- closing too LOW, and a deleted incoming transfer makes it too low as well.
-- The agent then appears to be holding cash nobody can account for: BR-237's
-- whole purpose is that figure, and a settlement measured against it would
-- have shown an excess that did not exist and asked somebody to explain it.
--
-- NO LIVE FIGURE CHANGES TODAY. Counted before writing this: zero deleted
-- loans and zero deleted expenses across every book. This closes a hole rather
-- than repairing a number, and claiming otherwise would overstate it -- the
-- same thing was true of the collections fix earlier and is worth saying twice
-- rather than letting a commit imply money moved.
--
-- loan_status <> 'Cancelled' STAYS, beside the new filter rather than instead
-- of it. A cancelled loan and a deleted one are different states: one was
-- called off, the other was struck from the book, and neither is cash that
-- left the agent's pocket. Dropping either test would let the other's rows
-- back in.
--
-- Signature unchanged, so CREATE OR REPLACE is correct and creates no second
-- overload. Asserted below anyway.

CREATE OR REPLACE FUNCTION app.agent_expected_closing(p_agent_id uuid, p_business_date date)
 RETURNS TABLE(opening_bf numeric, cash_collected numeric, upi_collected numeric, bank_collected numeric, cheque_collected numeric, loans_disbursed numeric, expenses numeric, transfers_in numeric, transfers_out numeric, expected_cash_closing numeric)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_membership_id UUID;
  v_business_id UUID;
  v_open  DECIMAL(14,0) := 0;
  v_cash  DECIMAL(14,0) := 0;
  v_upi   DECIMAL(14,0) := 0;
  v_bank  DECIMAL(14,0) := 0;
  v_chq   DECIMAL(14,0) := 0;
  v_disb  DECIMAL(14,0) := 0;
  v_exp   DECIMAL(14,0) := 0;
  v_in    DECIMAL(14,0) := 0;
  v_out   DECIMAL(14,0) := 0;
BEGIN
  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT bm.business_id INTO v_business_id
  FROM business_members bm WHERE bm.membership_id = v_membership_id;

  -- The agent themselves, or the Owner of their business.
  IF NOT (app.is_owner(v_business_id)
          OR EXISTS (SELECT 1 FROM agents a
                     WHERE a.agent_id = p_agent_id AND a.person_id = app.current_person_id())) THEN
    RAISE EXCEPTION 'Not authorized for this agent' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(b.opening_bf, 0) INTO v_open
  FROM agent_bf_assignments b
  WHERE b.membership_id = v_membership_id
    AND (b.business_date IS NULL OR b.business_date <= p_business_date)
  ORDER BY COALESCE(b.business_date::TIMESTAMP, b.created_at) DESC
  LIMIT 1;
  v_open := COALESCE(v_open, 0);

  SELECT
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cash' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = ANY(app.online_payment_modes()) THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Bank Transfer' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cheque' THEN s.amount END), 0)
  INTO v_cash, v_upi, v_bank, v_chq
  FROM collection_payment_splits s
  JOIN collections c ON c.collection_id = s.collection_id
  WHERE c.collected_by_membership_id = v_membership_id
    AND c.business_date = p_business_date
    AND c.deleted_at IS NULL;

  SELECT COALESCE(SUM(l.amount_given), 0) INTO v_disb
  FROM loans l
  WHERE l.collection_agent_membership_id = v_membership_id
    AND l.issue_business_date = p_business_date
    AND l.loan_status <> 'Cancelled'
    AND l.deleted_at IS NULL;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_exp
  FROM expenses e
  WHERE e.recorded_by_membership_id = v_membership_id
    AND e.business_date = p_business_date
    AND e.deleted_at IS NULL;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_in
  FROM cash_transfers t
  WHERE t.to_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL
    AND t.deleted_at IS NULL;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_out
  FROM cash_transfers t
  WHERE t.from_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL
    AND t.deleted_at IS NULL;

  RETURN QUERY SELECT
    v_open, v_cash, v_upi, v_bank, v_chq, v_disb, v_exp, v_in, v_out,
    v_open + v_cash - v_disb - v_exp + v_in - v_out;
END;
$function$;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'agent_expected_closing';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'agent_expected_closing has % overloads', v_n;
  END IF;

  -- Every soft-deletable table this function reads is now filtered. Counted
  -- from the body itself so a later edit that drops one is caught here rather
  -- than on somebody's settlement screen.
  SELECT (length(p.prosrc) - length(replace(p.prosrc, 'deleted_at IS NULL', '')))
         / length('deleted_at IS NULL')
    INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'agent_expected_closing';
  IF v_n <> 5 THEN
    RAISE EXCEPTION
      'expected 5 deleted_at filters (collections, loans, expenses, two '
      'transfer directions); found %', v_n;
  END IF;
END $$;

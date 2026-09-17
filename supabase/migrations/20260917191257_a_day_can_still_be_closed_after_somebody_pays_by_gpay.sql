-- Two functions bucketed collections by payment_mode = 'UPI' exactly, and
-- payment_mode_enum gained GPay, PhonePe and Paytm an hour ago. Without this,
-- adding those values would have shipped a blocker.
--
-- app.day_closure_expected feeds the Owner's Day Closure, and
-- app.close_business_day REFUSES TO CLOSE when expected <> actual:
--   'Cannot close: Expected % vs Actual % leaves a difference'
-- A single GPay collection would fall into no bucket, leave expected short by
-- its amount, and the day could not be closed at all -- by anybody, until
-- somebody found this.
--
-- app.agent_expected_closing feeds BR-237, what an agent is expected to hand
-- over. The same payment would be missing from their expected online figure,
-- so the agent would read as holding money nobody could account for.
--
-- Found by a guard written for the Dart copies of this list, which then
-- pointed at a third consumer -- day_closure_state.dart -- and that led here.
-- CLAUDE.md's rule earned its place again: "Before changing anything shared,
-- list its consumers. If the list is longer than one, every entry gets checked
-- or gets said out loud." The list was five, and grepping the obvious name
-- found two.
--
-- ONE DEFINITION OF ONLINE, in app.online_payment_modes(), so this is the last
-- time the set is written down in SQL. It mirrors manaOnlinePaymentModes in
-- lib/shared/payment_modes.dart, and test/payment_mode_vocabulary_test.dart
-- holds the Dart side to the enum.
--
-- SECOND DEFECT, FIXED HERE BECAUSE IT IS THE SAME SELECT: neither function
-- filtered c.deleted_at. Both were counting splits belonging to REVERSED
-- collections -- 612 of 862 collections on the live book are soft-deleted --
-- while day_ledger.total_collections, the figure day_closure_expected compares
-- against, excludes them. The two sides of the comparison were reading
-- different sets of payments. Every other query in this codebase that touches
-- collections filters deleted_at; these two were the exception.
--
-- Checked before and after: zero split rows currently hang off a deleted
-- collection, so this corrects no live figure today. It closes a hole rather
-- than repairing a number, and saying otherwise would overstate it.
--
-- STILL OPEN, DELIBERATELY NOT TOUCHED: app.agent_expected_closing counts
-- loans and expenses without checking their deleted_at either. Same class of
-- defect, different tables, and not on the path this migration exists to fix.
-- Named here rather than quietly widened.
--
-- Column names are unchanged -- expected_upi, upi_collected -- because they
-- are the RETURNS TABLE signature two Dart readers bind to, and renaming them
-- is a DROP and a coordinated client change, not a repair. They now mean every
-- online mode.

CREATE OR REPLACE FUNCTION app.online_payment_modes()
RETURNS payment_mode_enum[]
LANGUAGE sql IMMUTABLE
AS $function$
  -- Page 5: "© - Cash / ℗ - Online Payment (Gpay,Phonepe, Paytm)". UPI is
  -- here because that is exactly what it meant before the app could ask which
  -- app. A cheque and a branch transfer are not online and keep their own
  -- lines.
  SELECT ARRAY['GPay','PhonePe','Paytm','UPI']::payment_mode_enum[];
$function$;

GRANT EXECUTE ON FUNCTION app.online_payment_modes() TO anon, authenticated;

CREATE OR REPLACE FUNCTION app.day_closure_expected(p_business_id uuid, p_business_date date)
 RETURNS TABLE(expected_cash numeric, expected_upi numeric, expected_bank numeric, expected_cheque numeric, ledger_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    COALESCE(SUM(CASE WHEN s.payment_mode = ANY(app.online_payment_modes()) THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Bank Transfer' THEN s.amount END), 0),
    COALESCE(SUM(CASE WHEN s.payment_mode = 'Cheque' THEN s.amount END), 0)
  INTO v_cash, v_upi, v_bank, v_cheque
  FROM collection_payment_splits s
  JOIN collections c ON c.collection_id = s.collection_id
  JOIN loans l ON l.loan_id = c.loan_id
  WHERE l.business_id = p_business_id
    AND c.business_date = p_business_date
    AND c.deleted_at IS NULL;

  RETURN QUERY SELECT
    v_ledger.opening_balance + v_cash
      - v_ledger.total_loan_distribution - v_ledger.total_expenses
      + v_ledger.investor_deposits - v_ledger.investor_withdrawals,
    v_upi,
    v_bank,
    v_cheque,
    v_ledger.status::TEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION app.agent_expected_closing(p_agent_id uuid, p_business_date date)
 RETURNS TABLE(opening_bf numeric, cash_collected numeric, upi_collected numeric, bank_collected numeric, cheque_collected numeric, loans_disbursed numeric, expenses numeric, transfers_in numeric, transfers_out numeric, expected_cash_closing numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
    AND l.loan_status <> 'Cancelled';

  SELECT COALESCE(SUM(e.amount), 0) INTO v_exp
  FROM expenses e
  WHERE e.recorded_by_membership_id = v_membership_id
    AND e.business_date = p_business_date;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_in
  FROM cash_transfers t
  WHERE t.to_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL;

  SELECT COALESCE(SUM(t.amount), 0) INTO v_out
  FROM cash_transfers t
  WHERE t.from_agent_id = p_agent_id
    AND t.business_date = p_business_date
    AND t.from_agent_confirmed_at IS NOT NULL
    AND t.to_agent_confirmed_at IS NOT NULL;

  RETURN QUERY SELECT
    v_open, v_cash, v_upi, v_bank, v_chq, v_disb, v_exp, v_in, v_out,
    v_open + v_cash - v_disb - v_exp + v_in - v_out;
END;
$function$;

DO $$
DECLARE v_n INT;
BEGIN
  FOR v_n IN
    SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='app' AND p.proname IN
       ('day_closure_expected','agent_expected_closing','online_payment_modes')
     GROUP BY p.proname
  LOOP
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'a replaced function gained an overload (%)', v_n;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM unnest(app.online_payment_modes())) <> 4 THEN
    RAISE EXCEPTION 'online_payment_modes should name four modes';
  END IF;
END $$;

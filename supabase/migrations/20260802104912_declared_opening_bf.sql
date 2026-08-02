-- BF is DECLARED at migration, not accumulated from history.
--
-- The app assumed capital arrives through investors: owner_bf_balance is only
-- ever moved, by record_investment, migrate_loan, submit_agent_settlement and
-- friends. There was no way to SET it. A business running ten years on its own
-- retained profit, with no investor money for the last five, had no door in --
-- BF would start at 0 and every migrated loan would drive it negative.
--
-- The Owner counts the cash box on migration day and declares that figure.
-- Everything before it is deliberately out of scope: ten years of turnover
-- does not need reconstructing to know what is in the box today.

ALTER TABLE businesses
    ADD COLUMN opening_bf_declared_amount DECIMAL(14,0) NULL,
    ADD COLUMN opening_bf_declared_on     DATE NULL;

COMMENT ON COLUMN businesses.opening_bf_declared_amount IS
  'Cash in hand declared by the Owner on migration day. Set once while migration is unlocked, then frozen. NULL means never declared.';

-- Declares opening BF. Refuses once migration is locked, so the figure cannot
-- move after the business goes live.
--
-- WHY THE LOCK MATTERS BEYOND TIDINESS: day_ledger derives its opening balance
-- from owner_bf_balance when no earlier ledger row exists, and
-- app.recompute_day_ledger_onward cascades a change forward through every
-- later day. Re-declaring BF in month three would silently rewrite months of
-- closing balances.
CREATE OR REPLACE FUNCTION app.set_opening_bf(
    p_business_id UUID,
    p_amount NUMERIC
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
    v_locked BOOLEAN;
    v_amount DECIMAL(14,0) := CEIL(p_amount);
BEGIN
    IF NOT app.is_owner(p_business_id) THEN
        RAISE EXCEPTION 'Only the Owner can declare opening BF'
          USING ERRCODE = '42501';
    END IF;

    SELECT migration_locked INTO v_locked
      FROM businesses WHERE business_id = p_business_id;
    IF v_locked IS NULL THEN
        RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_locked THEN
        RAISE EXCEPTION 'Migration is locked. Opening BF cannot be changed once the business is live.'
          USING ERRCODE = '23514';
    END IF;

    IF v_amount < 0 THEN
        RAISE EXCEPTION 'Opening BF cannot be negative' USING ERRCODE = '23514';
    END IF;

    UPDATE businesses
       SET opening_bf_declared_amount = v_amount,
           opening_bf_declared_on     = CURRENT_DATE,
           -- The declared figure IS the working balance, not an addition to
           -- it: the Owner counted the box, so whatever was there before is
           -- already inside that count.
           owner_bf_balance           = v_amount
     WHERE business_id = p_business_id;

    INSERT INTO audit_log (
        business_id, actor_person_id, action_type, entity_type, entity_id,
        new_value, business_date
    ) VALUES (
        p_business_id, app.current_person_id(), 'Other Admin Event',
        'opening_bf_declared', 0,
        json_build_object('amount', v_amount, 'declared_on', CURRENT_DATE),
        CURRENT_DATE
    );

    RETURN json_build_object('opening_bf', v_amount, 'declared_on', CURRENT_DATE);
END;
$fn$;

GRANT EXECUTE ON FUNCTION app.set_opening_bf(UUID, NUMERIC) TO authenticated;

-- migrate_loan must no longer touch BF.
--
-- It did `owner_bf_balance = owner_bf_balance - v_given + v_collected`, which
-- made sense only while BF was accumulated from history. Against a DECLARED
-- figure it is double counting: the Owner counted the cash box today, and that
-- count already reflects every rupee lent out and every rupee collected back
-- over the past ten years. Re-applying them per loan would drift BF by the
-- full amount of every loan entered.
--
-- Dropped and recreated because parameter defaults cannot be changed in place.
-- Signature and defaults are preserved exactly; the ONLY behavioural change is
-- the removed UPDATE.
DROP FUNCTION IF EXISTS app.migrate_loan(uuid,uuid,numeric,numeric,numeric,date,repayment_frequency_enum,numeric,integer,numeric,uuid);

CREATE FUNCTION app.migrate_loan(
    p_customer_id uuid, p_business_id uuid, p_amount_given numeric,
    p_repayment_amount numeric, p_remaining_balance numeric,
    p_effective_date date, p_repayment_type repayment_frequency_enum,
    p_installment_amount numeric,
    p_grace_period_days integer DEFAULT 0,
    p_processing_fee numeric DEFAULT 0,
    p_collection_agent_membership_id uuid DEFAULT NULL::uuid
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  v_locked BOOLEAN;
  v_given DECIMAL(14,0) := CEIL(p_amount_given);
  v_repay DECIMAL(14,0) := CEIL(p_repayment_amount);
  v_remain DECIMAL(14,0) := CEIL(p_remaining_balance);
  v_fee DECIMAL(14,0) := CEIL(COALESCE(p_processing_fee, 0));
  v_inst DECIMAL(14,0) := CEIL(p_installment_amount);
  v_collected DECIMAL(14,0);
  v_interest DECIMAL(14,0);
  v_status loan_status_enum;
  v_agent_membership UUID;
  v_loan_id UUID;
  v_loan_number VARCHAR(30);
  v_interval INTERVAL;
  v_n INT;
  v_due DATE;
  v_left DECIMAL(14,0);
  v_amt DECIMAL(14,0);
  i INT;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(
               p_collection_agent_membership_id, 'can_migrate_records') THEN
    RAISE EXCEPTION 'Not authorized to enter pre-existing records for this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is locked for this business. Reopen migration before entering pre-existing records.'
      USING ERRCODE = '23514';
  END IF;

  IF v_repay <= 0 OR v_given <= 0 OR v_inst <= 0 THEN
    RAISE EXCEPTION 'Amount Given, Repayment Amount and Installment Amount must all be greater than zero'
      USING ERRCODE = '23514';
  END IF;
  IF v_remain < 0 OR v_remain > v_repay THEN
    RAISE EXCEPTION 'Remaining Balance must be between 0 and the Repayment Amount (%)', v_repay
      USING ERRCODE = '23514';
  END IF;
  IF v_given + v_fee > v_repay THEN
    RAISE EXCEPTION 'Amount Given plus Processing Fee (%) cannot exceed the Repayment Amount (%) - that would make interest negative',
      v_given + v_fee, v_repay USING ERRCODE = '23514';
  END IF;

  v_agent_membership := p_collection_agent_membership_id;
  IF v_agent_membership IS NULL THEN
    SELECT c.assigned_agent_membership_id INTO v_agent_membership
    FROM customers c WHERE c.customer_id = p_customer_id;
  END IF;
  IF v_agent_membership IS NULL THEN
    SELECT bm.membership_id INTO v_agent_membership
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.business_id = p_business_id
      AND bm.role = 'Agent'
      AND bm.membership_status = 'Active'
      AND bm.person_id = b.owner_person_id
    LIMIT 1;
  END IF;
  IF v_agent_membership IS NULL THEN
    RAISE EXCEPTION 'No collecting agent could be determined for this loan. Assign an agent to the customer first.'
      USING ERRCODE = '23502';
  END IF;

  v_collected := v_repay - v_remain;
  v_interest  := v_repay - v_given - v_fee;
  v_status    := (CASE WHEN v_remain <= 0 THEN 'Closed' ELSE 'Active' END)::loan_status_enum;

  v_interval := CASE p_repayment_type
                  WHEN 'Daily'   THEN INTERVAL '1 day'
                  WHEN 'Weekly'  THEN INTERVAL '7 days'
                  ELSE                INTERVAL '1 month'
                END;

  v_n := GREATEST(CEIL(v_remain::numeric / v_inst)::INT, 0);

  v_loan_number := 'LN-MIG-' || to_char(now(), 'YYYYMMDD') || '-' || substr(md5(random()::text), 1, 6);

  INSERT INTO loans (
    loan_number, customer_id, business_id, repayment_amount, interest_amount,
    processing_fee, repayment_type, duration_value, installment_amount,
    grace_period_days, remaining_balance, collection_agent_membership_id, effective_date,
    loan_status, issue_business_date, live_photo_url
  ) VALUES (
    v_loan_number, p_customer_id, p_business_id, v_repay, v_interest,
    v_fee, p_repayment_type, v_n, v_inst,
    COALESCE(p_grace_period_days, 0), v_remain, v_agent_membership, p_effective_date,
    v_status,
    p_effective_date,
    'migrated:pre-existing-loan:no-live-photo'
  ) RETURNING loan_id INTO v_loan_id;

  v_left := v_remain;
  v_due := CURRENT_DATE;
  i := 1;
  WHILE v_left > 0 LOOP
    v_amt := LEAST(v_inst, v_left);
    INSERT INTO loan_schedule (loan_id, installment_number, due_date, installment_amount, status)
    VALUES (v_loan_id, i, v_due, v_amt, 'Pending');
    v_left := v_left - v_amt;
    v_due := (v_due + v_interval)::date;
    i := i + 1;
  END LOOP;

  -- NO owner_bf_balance UPDATE here. See the header: BF is declared, and that
  -- declared count already contains the effect of every pre-existing loan.

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    p_business_id, app.current_person_id(), 'Other Admin Event', 'loan_migrated', 0,
    v_loan_id,
    json_build_object('amount_given', v_given, 'repayment_amount', v_repay,
                      'remaining_balance', v_remain, 'collected', v_collected,
                      'interest_amount', v_interest, 'effective_date', p_effective_date),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'loan_id', v_loan_id, 'loan_number', v_loan_number,
    'collected', v_collected, 'interest_amount', v_interest,
    'installments_created', GREATEST(i - 1, 0)
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION app.migrate_loan(uuid,uuid,numeric,numeric,numeric,date,repayment_frequency_enum,numeric,integer,numeric,uuid) TO authenticated;

-- migration_summary now returns the declared figure and its date, so the
-- screen can show what the Owner actually stated rather than a breakdown that
-- no longer reconciles to it.
DROP FUNCTION IF EXISTS app.migration_summary(UUID);

CREATE FUNCTION app.migration_summary(p_business_id UUID)
RETURNS TABLE(
    migration_locked BOOLEAN,
    business_started_at TIMESTAMP,
    investment_principal NUMERIC,
    migrated_loan_count INT,
    total_given NUMERIC,
    total_collected NUMERIC,
    line_balance NUMERIC,
    bf NUMERIC,
    opening_bf_declared_amount NUMERIC,
    opening_bf_declared_on DATE
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
BEGIN
  IF NOT app.is_owner(p_business_id) AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    b.migration_locked,
    b.business_started_at,
    COALESCE((SELECT SUM(i.original_principal_amount) FROM investments i
              WHERE i.business_id = p_business_id AND i.status = 'Active'), 0),
    COALESCE((SELECT COUNT(*)::int FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.amount_given) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.repayment_amount - l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id
                AND l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')), 0),
    b.owner_bf_balance,
    b.opening_bf_declared_amount,
    b.opening_bf_declared_on
  FROM businesses b WHERE b.business_id = p_business_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION app.migration_summary(UUID) TO authenticated;

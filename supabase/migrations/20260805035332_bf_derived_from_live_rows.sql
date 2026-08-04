-- P0: BF correctness.
--
-- Two defects, one root cause each.
--
-- 1. `businesses.owner_bf_balance` carried two incompatible meanings: the
--    day-one seed for `day_ledger`, and the live owner cash-in-hand that
--    seventeen RPCs increment. A running total cannot be a correct historical
--    seed. `sri tirumala finance` proved it: owner_bf_balance is 0 and there
--    are no investment rows, yet every ledger day read 10,00,000 — a fossil of
--    a value the column held once, never revisited because
--    recompute_day_ledger_onward only ever walks forward.
--
--    The genuine seed column already existed and was unused by the recompute:
--    `businesses.opening_bf_declared_amount`. It is now the only seed, and
--    owner_bf_balance becomes derived — never authoritative.
--
-- 2. Deleting a record never reversed its cash effect. The *ledger* already
--    self-heals (the eight triggers fire AFTER UPDATE, so flipping deleted_at
--    re-runs the recompute and the row drops out of sums that all filter
--    `deleted_at IS NULL`). BF did not: it stayed a stored running total, so
--    ledger and BF silently disagreed after any delete.
--
-- Both BF pots are now derived from live rows, the way day_ledger already
-- works. Delete and restore both move BF because neither has to remember to.

-- ---------------------------------------------------------------------------
-- 1. Grant ledger.
--
-- Agent BF cannot be derived without one: grant_agent_bf moved cash from the
-- owner's pot to an agent's and left no row behind, so the grant was
-- unreconstructable from live data. Every other agent-BF event already has a
-- table (collections, loans, expenses, cheti_payments, cash_transfers,
-- account_settlements). This closes the set.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.agent_bf_grants (
    grant_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id              UUID NOT NULL REFERENCES businesses(business_id),
    membership_id            UUID NOT NULL REFERENCES business_members(membership_id),
    amount                   NUMERIC(14,0) NOT NULL CHECK (amount > 0),
    business_date            DATE NOT NULL DEFAULT CURRENT_DATE,
    granted_by_membership_id UUID REFERENCES business_members(membership_id),
    created_at               TIMESTAMP NOT NULL DEFAULT now(),
    deleted_at               TIMESTAMP,
    deleted_by_membership_id UUID REFERENCES business_members(membership_id),
    delete_reason            TEXT
);

CREATE INDEX IF NOT EXISTS idx_agent_bf_grants_membership
    ON public.agent_bf_grants (membership_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_agent_bf_grants_business
    ON public.agent_bf_grants (business_id) WHERE deleted_at IS NULL;

ALTER TABLE public.agent_bf_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS agent_bf_grants_owner_all ON public.agent_bf_grants;
CREATE POLICY agent_bf_grants_owner_all ON public.agent_bf_grants
    FOR ALL USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));

DROP POLICY IF EXISTS agent_bf_grants_agent_read ON public.agent_bf_grants;
CREATE POLICY agent_bf_grants_agent_read ON public.agent_bf_grants
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM business_members bm
                 WHERE bm.membership_id = agent_bf_grants.membership_id
                   AND bm.person_id = app.current_person_id()
                   AND bm.membership_status = 'Active')
    );

-- ---------------------------------------------------------------------------
-- 2. Derived agent BF.
--
-- Every term reads live rows only. A deleted collection stops crediting the
-- agent the moment deleted_at is set; a restored one starts again. Nothing
-- has to be reversed because nothing was ever accumulated.
--
-- Settlement handover: submit_agent_settlement moves the whole agent pot to
-- the owner, so it is subtracted while the settlement stands. return_settlement
-- flips status to 'Returned', which drops the term and hands the cash back.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_agent_bf(p_membership_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_agent_id       UUID;
    v_grants         NUMERIC(14,0);
    v_collections    NUMERIC(14,0);
    v_loans          NUMERIC(14,0);
    v_expenses       NUMERIC(14,0);
    v_cheti          NUMERIC(14,0);
    v_in             NUMERIC(14,0);
    v_out            NUMERIC(14,0);
    v_handed         NUMERIC(14,0);
    v_bf             NUMERIC(14,0);
    v_assignment_id  UUID;
BEGIN
    SELECT a.agent_id INTO v_agent_id FROM agents a WHERE a.membership_id = p_membership_id;

    SELECT COALESCE(SUM(amount), 0) INTO v_grants
      FROM agent_bf_grants
     WHERE membership_id = p_membership_id AND deleted_at IS NULL;

    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE c.collected_by_membership_id = p_membership_id
       AND c.deleted_at IS NULL AND l.deleted_at IS NULL;

    SELECT COALESCE(SUM(l.amount_given), 0) INTO v_loans
      FROM loans l
     WHERE l.collection_agent_membership_id = p_membership_id
       AND l.deleted_at IS NULL;

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
      FROM expenses e
     WHERE e.recorded_by_membership_id = p_membership_id
       AND e.deleted_at IS NULL;

    SELECT COALESCE(SUM(cp.net_paid), 0) INTO v_cheti
      FROM cheti_payments cp
     WHERE cp.recorded_by_membership_id = p_membership_id
       AND cp.deleted_at IS NULL;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.to_agent_id   = v_agent_id), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.from_agent_id = v_agent_id), 0)
      INTO v_in, v_out
      FROM cash_transfers t
     WHERE (t.from_agent_id = v_agent_id OR t.to_agent_id = v_agent_id)
       AND t.from_agent_confirmed_at IS NOT NULL
       AND t.to_agent_confirmed_at IS NOT NULL
       AND t.deleted_at IS NULL;

    SELECT COALESCE(SUM(s.agent_bf_handed_over), 0) INTO v_handed
      FROM account_settlements s
     WHERE s.agent_id = v_agent_id
       AND s.status <> 'Returned';

    v_bf := COALESCE(v_grants,0) + COALESCE(v_collections,0)
          - COALESCE(v_loans,0) - COALESCE(v_expenses,0) - COALESCE(v_cheti,0)
          + COALESCE(v_in,0) - COALESCE(v_out,0)
          - COALESCE(v_handed,0);

    SELECT assignment_id INTO v_assignment_id
      FROM agent_bf_assignments
     WHERE membership_id = p_membership_id
     ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
     LIMIT 1;

    IF v_assignment_id IS NOT NULL THEN
        UPDATE agent_bf_assignments
           SET agent_bf_current = v_bf, updated_at = now()
         WHERE assignment_id = v_assignment_id;
    ELSIF v_bf <> 0 THEN
        INSERT INTO agent_bf_assignments
            (membership_id, business_date, opening_bf, agent_bf_current, confirmed_by_agent)
        VALUES (p_membership_id, CURRENT_DATE, 0, v_bf, false);
    END IF;

    RETURN v_bf;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Derived owner BF.
--
-- Business-wide cash lives in day_ledger; the owner's pot is whatever is not
-- currently in an agent's pocket. A grant, a transfer between agents and a
-- settlement handover all move cash between pots without changing the total,
-- which is exactly why none of them touch day_ledger.
--
-- A derived number must be allowed to state the truth, so a negative result is
-- stored and recorded rather than clamped — clamping is how a confidently
-- wrong number reaches a collection screen. The forward guards in
-- record_expense / create_loan_with_bf_check / grant_agent_bf / record_cheti_payment
-- are what stop new spending from going negative; they are unchanged.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_business_bf(p_business_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_m         RECORD;
    v_agent_sum NUMERIC(14,0) := 0;
    v_closing   NUMERIC(14,0);
    v_owner     NUMERIC(14,0);
BEGIN
    FOR v_m IN
        SELECT membership_id FROM business_members
         WHERE business_id = p_business_id AND role = 'Agent'
    LOOP
        v_agent_sum := v_agent_sum + app.recompute_agent_bf(v_m.membership_id);
    END LOOP;

    SELECT closing_balance INTO v_closing
      FROM day_ledger
     WHERE business_id = p_business_id
     ORDER BY business_date DESC
     LIMIT 1;

    IF v_closing IS NULL THEN
        SELECT COALESCE(opening_bf_declared_amount, 0) INTO v_closing
          FROM businesses WHERE business_id = p_business_id;
    END IF;

    v_owner := COALESCE(v_closing, 0) - v_agent_sum;

    UPDATE businesses SET owner_bf_balance = v_owner WHERE business_id = p_business_id;

    -- The UPDATE above is unconditional on purpose: the derived figure lands
    -- whether or not it can be audited. audit_log.actor_person_id is NOT NULL
    -- and current_person_id() is NULL without a JWT, so a recompute run from
    -- cron or a migration would otherwise abort on the audit insert and leave
    -- BF stale — the exact failure this migration exists to remove.
    IF v_owner < 0 AND app.current_person_id() IS NOT NULL THEN
        INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                               entity_id, new_value, business_date)
        VALUES (p_business_id, app.current_person_id(), 'Other Admin Event',
                'owner_bf_negative', 0,
                json_build_object('owner_bf', v_owner, 'ledger_closing', v_closing,
                                  'agent_bf_total', v_agent_sum),
                CURRENT_DATE);
    END IF;

    RETURN v_owner;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Rebuild the whole chain, not just forward.
--
-- recompute_day_ledger_onward stays as the cheap path for a new record on a
-- known day. Delete and restore use this one, because the day that needs
-- revisiting can be the seed row itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_ledger_chain(p_business_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_date DATE;
BEGIN
    FOR v_date IN
        SELECT business_date FROM day_ledger
         WHERE business_id = p_business_id
         ORDER BY business_date
    LOOP
        PERFORM app.recompute_day_ledger(p_business_id, v_date);
    END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Seed day one from the declared opening, never from the live balance.
--    Only the seed block changes; every sum below it is untouched.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.recompute_day_ledger(p_business_id uuid, p_business_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_opening      DECIMAL(14,0);
    v_collections  DECIMAL(14,0);
    v_loans        DECIMAL(14,0);
    v_deposits     DECIMAL(14,0);
    v_withdrawals  DECIMAL(14,0);
    v_expenses     DECIMAL(14,0);
    v_cheti_paid   DECIMAL(14,0);
    v_cheti_recv   DECIMAL(14,0);
    v_short        DECIMAL(14,0);
    v_excess       DECIMAL(14,0);
    v_closing      DECIMAL(14,0);
BEGIN
    SELECT closing_balance INTO v_opening
      FROM day_ledger
     WHERE business_id = p_business_id
       AND business_date < p_business_date
     ORDER BY business_date DESC
     LIMIT 1;

    -- The earliest day opens on what the Owner declared when they counted the
    -- box, not on owner_bf_balance — that is now a derived figure and using it
    -- here made the seed drift every time cash moved.
    IF v_opening IS NULL THEN
        SELECT COALESCE(opening_bf_declared_amount, 0) INTO v_opening
          FROM businesses WHERE business_id = p_business_id;
    END IF;
    v_opening := COALESCE(v_opening, 0);

    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE l.business_id = p_business_id
       AND c.business_date = p_business_date
       AND c.deleted_at IS NULL
       AND l.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount_given), 0) INTO v_loans
      FROM loans
     WHERE business_id = p_business_id
       AND issue_business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(principal_amount), 0) INTO v_deposits
      FROM investments
     WHERE business_id = p_business_id
       AND effective_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(w.amount), 0) INTO v_withdrawals
      FROM investment_withdrawals w
      JOIN investments i ON i.investment_id = w.investment_id
     WHERE i.business_id = p_business_id
       AND w.business_date = p_business_date
       AND w.deleted_at IS NULL
       AND i.deleted_at IS NULL;

    SELECT COALESCE(SUM(amount), 0) INTO v_expenses
      FROM expenses
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(net_paid), 0) INTO v_cheti_paid
      FROM cheti_payments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(availed_amount), 0) INTO v_cheti_recv
      FROM chetis
     WHERE business_id = p_business_id
       AND availed_date = p_business_date
       AND NOT availed_pre_migration
       AND deleted_at IS NULL;

    SELECT COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Short'), 0),
           COALESCE(SUM(amount) FILTER (WHERE adjustment_type = 'Excess'), 0)
      INTO v_short, v_excess
      FROM settlement_adjustments
     WHERE business_id = p_business_id
       AND business_date = p_business_date
       AND deleted_at IS NULL;

    v_closing := v_opening
               + v_collections
               - v_loans
               + v_deposits
               - v_withdrawals
               - v_expenses
               - v_cheti_paid
               + v_cheti_recv;

    INSERT INTO day_ledger (
        business_id, business_date, opening_balance, total_collections,
        total_loan_distribution, investor_deposits, investor_withdrawals,
        total_expenses, cheti_paid, cheti_received, short_amount,
        excess_amount, closing_balance
    ) VALUES (
        p_business_id, p_business_date, v_opening, v_collections,
        v_loans, v_deposits, v_withdrawals,
        v_expenses, v_cheti_paid, v_cheti_recv, v_short,
        v_excess, v_closing
    )
    ON CONFLICT (business_id, business_date) DO UPDATE SET
        opening_balance         = EXCLUDED.opening_balance,
        total_collections       = EXCLUDED.total_collections,
        total_loan_distribution = EXCLUDED.total_loan_distribution,
        investor_deposits       = EXCLUDED.investor_deposits,
        investor_withdrawals    = EXCLUDED.investor_withdrawals,
        total_expenses          = EXCLUDED.total_expenses,
        cheti_paid              = EXCLUDED.cheti_paid,
        cheti_received          = EXCLUDED.cheti_received,
        short_amount            = EXCLUDED.short_amount,
        excess_amount           = EXCLUDED.excess_amount,
        closing_balance         = EXCLUDED.closing_balance;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 6. open_business_day carried the same stale seed. Same fix.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.open_business_day(p_business_id uuid, p_business_date date DEFAULT CURRENT_DATE)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_id UUID;
  v_prev_closing DECIMAL(14,0);
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may open a business day' USING ERRCODE = '42501';
  END IF;

  SELECT ledger_id INTO v_id FROM day_ledger
  WHERE business_id = p_business_id AND business_date = p_business_date;
  IF v_id IS NOT NULL THEN
    RETURN v_id;   -- idempotent
  END IF;

  SELECT closing_balance INTO v_prev_closing
  FROM day_ledger
  WHERE business_id = p_business_id AND business_date < p_business_date
  ORDER BY business_date DESC LIMIT 1;

  IF v_prev_closing IS NULL THEN
    SELECT COALESCE(opening_bf_declared_amount, 0) INTO v_prev_closing
    FROM businesses WHERE business_id = p_business_id;
  END IF;

  INSERT INTO day_ledger (
    business_id, business_date, opening_balance, total_collections,
    total_loan_distribution, investor_deposits, investor_withdrawals,
    total_expenses, short_amount, excess_amount, closing_balance, status
  ) VALUES (
    p_business_id, p_business_date, COALESCE(v_prev_closing, 0), 0,
    0, 0, 0, 0, 0, 0, COALESCE(v_prev_closing, 0), 'Open'
  ) RETURNING ledger_id INTO v_id;

  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. set_opening_bf writes the seed, then lets everything downstream derive.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.set_opening_bf(p_business_id uuid, p_amount numeric)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_locked BOOLEAN;
    v_amount DECIMAL(14,0) := CEIL(p_amount);
BEGIN
    IF NOT app.is_owner(p_business_id) THEN
        RAISE EXCEPTION 'Only the Owner can declare opening BF' USING ERRCODE = '42501';
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

    -- The declared figure IS the seed: the Owner counted the box, so whatever
    -- was there before is already inside that count. owner_bf_balance is no
    -- longer written here — it falls out of the ledger chain below.
    UPDATE businesses
       SET opening_bf_declared_amount = v_amount,
           opening_bf_declared_on     = CURRENT_DATE
     WHERE business_id = p_business_id;

    PERFORM app.recompute_ledger_chain(p_business_id);
    PERFORM app.recompute_business_bf(p_business_id);

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
$function$;

-- ---------------------------------------------------------------------------
-- 8. grant_agent_bf writes a grant row. The two UPDATEs it used to do are
--    replaced by a recompute, so a deleted grant reverses itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.grant_agent_bf(p_agent_membership_id uuid, p_amount numeric)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_owner_bf DECIMAL(14,0);
  v_owner_membership UUID;
BEGIN
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

  SELECT owner_bf_balance INTO v_owner_bf
  FROM businesses WHERE business_id = v_business_id FOR UPDATE;
  IF v_owner_bf < p_amount THEN
    RAISE EXCEPTION 'Owner BF is only %, cannot top up %', v_owner_bf, p_amount USING ERRCODE = '23514';
  END IF;

  SELECT membership_id INTO v_owner_membership
  FROM business_members
  WHERE business_id = v_business_id AND person_id = app.current_person_id()
    AND role = 'Owner' AND membership_status = 'Active'
  LIMIT 1;

  INSERT INTO agent_bf_grants (business_id, membership_id, amount, business_date, granted_by_membership_id)
  VALUES (v_business_id, p_agent_membership_id, p_amount, CURRENT_DATE, v_owner_membership);

  PERFORM app.recompute_business_bf(v_business_id);

  RETURN (SELECT agent_bf_current FROM agent_bf_assignments
           WHERE membership_id = p_agent_membership_id
           ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC LIMIT 1);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 9. Delete and restore move BF.
--
-- The ledger already self-heals via the eight AFTER UPDATE triggers, but only
-- forward from the deleted row's own day — so the chain is rebuilt from the
-- earliest day, then BF is derived from the result.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.soft_delete_record(p_entity text, p_record_id uuid, p_reason text DEFAULT NULL::text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID;
  v_membership_id UUID;
  v_already TIMESTAMP;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to delete records in this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT membership_id INTO v_membership_id
  FROM business_members
  WHERE business_id = v_business_id
    AND person_id = app.current_person_id()
    AND membership_status = 'Active'
  ORDER BY CASE role WHEN 'Owner' THEN 0 ELSE 1 END
  LIMIT 1;

  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_already USING p_record_id;
  IF v_already IS NOT NULL THEN
    RAISE EXCEPTION 'This record is already deleted' USING ERRCODE = '23514';
  END IF;

  EXECUTE format(
    'UPDATE %I SET deleted_at = now(), deleted_by_membership_id = $2, delete_reason = $3 WHERE %I = $1',
    v_table, v_pk)
    USING p_record_id, v_membership_id, p_reason;

  PERFORM app.recompute_ledger_chain(v_business_id);
  PERFORM app.recompute_business_bf(v_business_id);

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_soft_deleted', 0, p_record_id,
    json_build_object('reason', p_reason, 'table', v_table),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'deleted',
    'entity', p_entity,
    'record_id', p_record_id,
    'recoverable_until', (now() + INTERVAL '30 days')::date
  );
END;
$function$;

CREATE OR REPLACE FUNCTION app.restore_record(p_entity text, p_record_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_table TEXT; v_pk TEXT; v_business_id UUID; v_deleted_at TIMESTAMP;
BEGIN
  SELECT o_table, o_pk, o_business_id
    INTO v_table, v_pk, v_business_id
  FROM app.resolve_deletable(p_entity, p_record_id);

  IF NOT app.may_delete_records(v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to restore records in this business'
      USING ERRCODE = '42501';
  END IF;

  EXECUTE format('SELECT deleted_at FROM %I WHERE %I = $1 FOR UPDATE', v_table, v_pk)
    INTO v_deleted_at USING p_record_id;
  IF v_deleted_at IS NULL THEN
    RAISE EXCEPTION 'This record is not deleted' USING ERRCODE = '23514';
  END IF;

  EXECUTE format(
    'UPDATE %I SET deleted_at = NULL, deleted_by_membership_id = NULL, delete_reason = NULL WHERE %I = $1',
    v_table, v_pk)
    USING p_record_id;

  PERFORM app.recompute_ledger_chain(v_business_id);
  PERFORM app.recompute_business_bf(v_business_id);

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    p_entity || '_restored', 0, p_record_id,
    json_build_object('table', v_table), CURRENT_DATE
  );

  RETURN json_build_object('status', 'restored', 'entity', p_entity, 'record_id', p_record_id);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 10. The non-negative CHECKs have to go.
--
-- They were correct for a running total that only ever moved through guarded
-- RPCs. Against a derived figure they are a gag: a recompute that legitimately
-- lands negative would abort the delete that triggered it, and the user would
-- see a failed delete rather than a wrong balance they could act on. The
-- audit_log row in recompute_business_bf is what surfaces it instead.
-- ---------------------------------------------------------------------------
ALTER TABLE businesses            DROP CONSTRAINT IF EXISTS chk_businesses_owner_bf_nonneg;
ALTER TABLE agent_bf_assignments  DROP CONSTRAINT IF EXISTS chk_agent_bf_current_nonneg;

-- ---------------------------------------------------------------------------
-- 11. Backfill. Rewrites historical day_ledger rows — approved, including
--     sri tirumala finance's fossil 10,00,000.
-- ---------------------------------------------------------------------------
DO $$
DECLARE b RECORD;
BEGIN
    FOR b IN SELECT business_id FROM businesses LOOP
        PERFORM app.recompute_ledger_chain(b.business_id);
        PERFORM app.recompute_business_bf(b.business_id);
    END LOOP;
END $$;

-- A pre-existing loan is not money out of today's agent float.
--
-- SEEN LIVE: an Agent's Cash in Hand read -1,06,600. app.recompute_agent_bf
-- subtracts every loan assigned to the agent, and two migrated loans totalling
-- 1,17,600 of amount_given were counted against a float that had never held
-- the money. That cash left the till months before this business joined MANA
-- LINE; the loan was entered to record what is still owed, not to spend
-- anything today.
--
-- It also produced a day net of -1,17,600 on the day those loans were dated,
-- and BF that no grant could ever bring back to positive: every rupee of the
-- old book's line would have to be re-granted first.
--
-- Marked explicitly rather than inferred from the loan number, which is
-- cosmetic, or from migrated_through_date, which moves.
ALTER TABLE loans
  ADD COLUMN IF NOT EXISTS is_pre_existing boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN loans.is_pre_existing IS
  'Entered by the migration as an already-running loan. Its cash left the till before MANA LINE, so it never counts against an agent float or a day net.';

-- Backfill: every loan the migration wrote carries the LN-MIG- prefix.
UPDATE loans SET is_pre_existing = true
 WHERE loan_number LIKE 'LN-MIG-%' AND is_pre_existing = false;

CREATE OR REPLACE FUNCTION app.recompute_agent_bf(p_membership_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
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

    -- is_pre_existing excluded: that cash never passed through this float.
    SELECT COALESCE(SUM(l.amount_given), 0) INTO v_loans
      FROM loans l
     WHERE l.collection_agent_membership_id = p_membership_id
       AND l.deleted_at IS NULL
       AND l.is_pre_existing = false;

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
$$;

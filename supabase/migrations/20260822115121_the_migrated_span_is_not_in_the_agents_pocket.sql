-- An agent's float holds live cash, not the book that came before it.
--
-- recompute_agent_bf already excludes pre-existing loans -- "that cash never
-- passed through this float" -- but it counted every collection, including the
-- ones replayed out of a paper book. On sri satyanarayana that is all 250 of
-- them, Rs 8,86,400, none of which is in anybody's pocket today: the book
-- collected it and lent it straight back out, and closed the span on Rs 100.
--
-- So the agent derived to Rs 8,97,400 and, since recompute_business_bf nets
-- agent holdings off the ledger closing, the Owner derived to MINUS
-- Rs 8,97,300 against a till holding Rs 100.
--
-- Everything dated at or before migrated_through_date is the declared book.
-- Its closing already nets off every collection, disbursement and expense
-- inside the span, so counting any of them again in the float double counts.
-- The same cut applies to expenses and cheti payments, for the same reason.
--
-- Signature unchanged: one overload, no PostgREST 300.
CREATE OR REPLACE FUNCTION app.recompute_agent_bf(p_membership_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_agent_id       UUID;
    v_business_id    UUID;
    v_span           DATE;
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

    -- The book's own span. '-infinity' for a business that never migrated, so
    -- every comparison below is simply true and nothing is excluded.
    SELECT bm.business_id INTO v_business_id
      FROM business_members bm WHERE bm.membership_id = p_membership_id;
    SELECT COALESCE(migrated_through_date, '-infinity'::date) INTO v_span
      FROM businesses WHERE business_id = v_business_id;

    SELECT COALESCE(SUM(amount), 0) INTO v_grants
      FROM agent_bf_grants
     WHERE membership_id = p_membership_id AND deleted_at IS NULL
       AND business_date > v_span;

    SELECT COALESCE(SUM(c.collected_amount), 0) INTO v_collections
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE c.collected_by_membership_id = p_membership_id
       AND c.deleted_at IS NULL AND l.deleted_at IS NULL
       AND c.business_date > v_span;

    -- is_pre_existing excluded: that cash never passed through this float.
    SELECT COALESCE(SUM(l.amount_given), 0) INTO v_loans
      FROM loans l
     WHERE l.collection_agent_membership_id = p_membership_id
       AND l.deleted_at IS NULL
       AND l.is_pre_existing = false
       AND l.issue_business_date > v_span;

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expenses
      FROM expenses e
     WHERE e.recorded_by_membership_id = p_membership_id
       AND e.deleted_at IS NULL
       AND e.business_date > v_span;

    SELECT COALESCE(SUM(cp.net_paid), 0) INTO v_cheti
      FROM cheti_payments cp
     WHERE cp.recorded_by_membership_id = p_membership_id
       AND cp.deleted_at IS NULL
       AND cp.business_date > v_span;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.to_agent_id   = v_agent_id), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.from_agent_id = v_agent_id), 0)
      INTO v_in, v_out
      FROM cash_transfers t
     WHERE (t.from_agent_id = v_agent_id OR t.to_agent_id = v_agent_id)
       AND t.from_agent_confirmed_at IS NOT NULL
       AND t.to_agent_confirmed_at IS NOT NULL
       AND t.deleted_at IS NULL
       AND t.business_date > v_span;

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

-- ============================================================================
-- 0016_rls_module7_collection_domain.sql
-- MANA LINE — RLS: Module 7 (Collection Domain)
-- Depends on: 0012, 0013, 0014, 0015
-- ============================================================================

-- collections: the core cash-collection record. Owner: full. Agent:
-- insert+select scoped to assigned customer's loans, gated
-- can_collect_payments for insert / can_view_customers for select — the
-- collecting agent is recorded on collected_by_membership_id, matching
-- BR-117/118. Customer: read-only, own loans' collections (payment history,
-- CW-004).
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY collections_owner_all ON collections
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = collections.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = collections.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY collections_agent_select_assigned ON collections
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = collections.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  );

CREATE POLICY collections_agent_insert_assigned ON collections
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = collections.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_collect_payments')
    )
    AND collected_by_membership_id = app.active_membership_id(
      (SELECT l2.business_id FROM loans l2 WHERE l2.loan_id = collections.loan_id), 'Agent'
    )
  );

CREATE POLICY collections_customer_select_own ON collections
  FOR SELECT
  USING (app.is_own_customer_row(customer_id));

-- collection_payment_splits: follows parent collection's visibility exactly.
ALTER TABLE collection_payment_splits ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_payment_splits_owner_all ON collection_payment_splits
  FOR ALL
  USING (EXISTS (SELECT 1 FROM collections co JOIN loans l ON l.loan_id = co.loan_id WHERE co.collection_id = collection_payment_splits.collection_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM collections co JOIN loans l ON l.loan_id = co.loan_id WHERE co.collection_id = collection_payment_splits.collection_id AND app.is_owner(l.business_id)));

CREATE POLICY collection_payment_splits_agent_all_assigned ON collection_payment_splits
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM collections co JOIN loans l ON l.loan_id = co.loan_id
      WHERE co.collection_id = collection_payment_splits.collection_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM collections co JOIN loans l ON l.loan_id = co.loan_id
      WHERE co.collection_id = collection_payment_splits.collection_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_collect_payments')
    )
  );

CREATE POLICY collection_payment_splits_customer_select_own ON collection_payment_splits
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM collections co WHERE co.collection_id = collection_payment_splits.collection_id AND app.is_own_customer_row(co.customer_id))
  );

-- no_collection_visits: visit-without-payment log. Owner: full. Agent:
-- insert+select scoped to assigned customer, gated can_access_collection_mode
-- (this is logged during Collection Mode per AG-002/AG-003). Customer: no
-- access — this is an internal field-ops log, never shown on any
-- Customer-facing screen. Erring restrictive, no Customer policy.
ALTER TABLE no_collection_visits ENABLE ROW LEVEL SECURITY;

CREATE POLICY no_collection_visits_owner_all ON no_collection_visits
  FOR ALL
  USING (app.is_owner(app.business_id_for_customer(no_collection_visits.customer_id)))
  WITH CHECK (app.is_owner(app.business_id_for_customer(no_collection_visits.customer_id)));

CREATE POLICY no_collection_visits_agent_all_assigned ON no_collection_visits
  FOR ALL
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(no_collection_visits.customer_id), 'can_access_collection_mode')
  )
  WITH CHECK (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(no_collection_visits.customer_id), 'can_access_collection_mode')
    AND visited_by_membership_id = app.active_membership_id(
      app.business_id_for_customer(no_collection_visits.customer_id), 'Agent'
    )
  );

-- collection_drafts: created_by_membership_id owns the draft. Owner: full
-- (needs visibility to resolve BF-blocked drafts, OW-013). Agent: self-scope
-- to drafts THEY created, gated can_create_drafts for insert,
-- can_edit_own_drafts for update, can_cancel_own_drafts for delete/discard.
-- No Customer/Investor access — drafts are an internal Agent working-set
-- concept, never customer or investor facing.
ALTER TABLE collection_drafts ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_drafts_owner_all ON collection_drafts
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(collection_drafts.created_by_membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(collection_drafts.created_by_membership_id)));

CREATE POLICY collection_drafts_agent_select_own ON collection_drafts
  FOR SELECT
  USING (app.membership_belongs_to_current_person(collection_drafts.created_by_membership_id));

CREATE POLICY collection_drafts_agent_insert_own ON collection_drafts
  FOR INSERT
  WITH CHECK (
    app.own_active_agent_membership_permits(collection_drafts.created_by_membership_id, 'can_create_drafts')
  );

CREATE POLICY collection_drafts_agent_update_own ON collection_drafts
  FOR UPDATE
  USING (
    app.own_active_agent_membership_permits(collection_drafts.created_by_membership_id, 'can_edit_own_drafts')
  )
  WITH CHECK (
    app.own_active_agent_membership_permits(collection_drafts.created_by_membership_id, 'can_edit_own_drafts')
    OR app.own_active_agent_membership_permits(collection_drafts.created_by_membership_id, 'can_cancel_own_drafts')
  );
-- Note: cancel is modeled as an UPDATE (status -> 'Discarded'), matching
-- the "no hard deletes" convention (BR-002/127) — no DELETE policy is
-- offered to any role for this or any other table, consistent with that
-- convention across the whole schema.

-- customer_online_payments: Customer self-service UPI submission (CW-005).
-- Customer: self-insert + self-select. Owner: full (confirms payment).
-- Agent: select+update(confirm) scoped to assigned customer, gated
-- can_collect_payments (confirming an online payment is functionally a
-- collection-confirmation action).
ALTER TABLE customer_online_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_online_payments_owner_all ON customer_online_payments
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = customer_online_payments.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = customer_online_payments.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY customer_online_payments_agent_select_assigned ON customer_online_payments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = customer_online_payments.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  );

CREATE POLICY customer_online_payments_agent_update_confirm ON customer_online_payments
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = customer_online_payments.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_collect_payments')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = customer_online_payments.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_collect_payments')
    )
    AND confirmed_by_person_id = app.current_person_id()
  );

CREATE POLICY customer_online_payments_customer_select_own ON customer_online_payments
  FOR SELECT
  USING (app.is_own_customer_row(customer_id));

CREATE POLICY customer_online_payments_customer_insert_own ON customer_online_payments
  FOR INSERT
  WITH CHECK (app.is_own_customer_row(customer_id));

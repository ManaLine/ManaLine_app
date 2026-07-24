-- ============================================================================
-- 0015_rls_module6_loan_domain.sql
-- MANA LINE — RLS: Module 6 (Loan Domain)
-- Depends on: 0012, 0013, 0014
-- ============================================================================

-- loans: central operational table. Owner: full. Agent: scoped to loans of
-- their ASSIGNED customers (matches AG-004), gated can_view_customers for
-- read, can_issue_loans for insert. Customer: self-read only, own loans.
-- Negative case: an Agent assigned to Customer A's loans can never see
-- Customer B's loans even in the same business; a Customer never sees any
-- other customer's loan.
ALTER TABLE loans ENABLE ROW LEVEL SECURITY;

CREATE POLICY loans_owner_all ON loans
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY loans_agent_select_assigned ON loans
  FOR SELECT
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(business_id, 'can_view_customers')
  );

CREATE POLICY loans_agent_insert_assigned ON loans
  FOR INSERT
  WITH CHECK (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(business_id, 'can_issue_loans')
  );

CREATE POLICY loans_customer_select_own ON loans
  FOR SELECT
  USING (app.is_own_customer_row(customer_id));

-- loan_schedule: follows the parent loan's visibility exactly (installment
-- detail is not more sensitive than the loan itself, and CW-004 explicitly
-- shows "Full Repayment Schedule" to the Customer).
ALTER TABLE loan_schedule ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_schedule_owner_all ON loan_schedule
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_schedule.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_schedule.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY loan_schedule_agent_select_assigned ON loan_schedule
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = loan_schedule.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  );

CREATE POLICY loan_schedule_customer_select_own ON loan_schedule
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_schedule.loan_id AND app.is_own_customer_row(l.customer_id)));

-- loan_cancellations: pre-cash-handover cancellations. Owner: full. Agent:
-- insert+select scoped to assigned customer's loans, gated can_issue_loans
-- (cancellation is part of the issuance flow, BR-015/168). Customer: no
-- access — cancellation is an internal Owner/Agent operational action, not
-- customer-facing in any screen spec (they simply never see the loan if
-- cancelled pre-handover). Erring restrictive, no Customer policy.
ALTER TABLE loan_cancellations ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_cancellations_owner_all ON loan_cancellations
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_cancellations.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_cancellations.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY loan_cancellations_agent_all_assigned ON loan_cancellations
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = loan_cancellations.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_issue_loans')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = loan_cancellations.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_issue_loans')
    )
    AND cancelled_by_person_id = app.current_person_id()
  );

-- loan_requests: Customer self-service request (CW-003), distinct from the
-- loan itself. Customer: self-insert + self-select. Owner: full manage
-- (approve/reject). Agent: read-only, scoped to assigned customer, gated
-- can_issue_loans (they typically action these on Owner's behalf per
-- OW-005-adjacent flows) — judgment call: screen specs describe this as an
-- Owner review queue (CW-003 "Owner decision" language), so Agent gets
-- READ only, never approve/reject.
ALTER TABLE loan_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_requests_owner_all ON loan_requests
  FOR ALL
  USING (app.is_owner(app.business_id_for_customer(loan_requests.customer_id)))
  WITH CHECK (app.is_owner(app.business_id_for_customer(loan_requests.customer_id)));

CREATE POLICY loan_requests_agent_select_assigned ON loan_requests
  FOR SELECT
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(loan_requests.customer_id), 'can_issue_loans')
  );

CREATE POLICY loan_requests_customer_select_own ON loan_requests
  FOR SELECT
  USING (app.is_own_customer_row(customer_id));

CREATE POLICY loan_requests_customer_insert_own ON loan_requests
  FOR INSERT
  WITH CHECK (app.is_own_customer_row(customer_id));

-- extension_requests: requested by Customer OR Agent (per schema enum),
-- decided by Owner only. Owner: full. Agent: insert+select scoped to
-- assigned customer's loans. Customer: self-insert + self-select on own
-- loans.
ALTER TABLE extension_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY extension_requests_owner_all ON extension_requests
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = extension_requests.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = extension_requests.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY extension_requests_agent_all_assigned ON extension_requests
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = extension_requests.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = extension_requests.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
    AND requested_by = 'Agent'
  );

CREATE POLICY extension_requests_customer_select_own ON extension_requests
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = extension_requests.loan_id AND app.is_own_customer_row(l.customer_id)));

CREATE POLICY extension_requests_customer_insert_own ON extension_requests
  FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = extension_requests.loan_id AND app.is_own_customer_row(l.customer_id))
    AND requested_by = 'Customer'
  );

-- penalty_entries: applied_by_person_id is "Owner or Agent with
-- can_apply_penalty" per schema note — this flag is OFF by default
-- (BR-236), so this is deliberately hard to satisfy unless explicitly
-- turned on, matching intent. Owner: full. Agent: insert+select scoped to
-- assigned customer's loans, gated can_apply_penalty specifically (NOT the
-- broader can_issue_loans/can_view_customers — this is its own dedicated
-- flag for a reason: penalties are financially punitive and default-off).
-- Customer: read-only, own loans (penalty history is part of CW-004's
-- loan detail / Line Score visibility).
ALTER TABLE penalty_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY penalty_entries_owner_all ON penalty_entries
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = penalty_entries.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = penalty_entries.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY penalty_entries_agent_select_assigned ON penalty_entries
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = penalty_entries.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  );

CREATE POLICY penalty_entries_agent_insert_assigned ON penalty_entries
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = penalty_entries.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_apply_penalty')
    )
    AND applied_by_person_id = app.current_person_id()
  );

CREATE POLICY penalty_entries_customer_select_own ON penalty_entries
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = penalty_entries.loan_id AND app.is_own_customer_row(l.customer_id)));

-- ============================================================================
-- 0014_rls_module2to5_config_customer_agent_investor.sql
-- MANA LINE — RLS: Module 2 (Loan Templates), Module 3 (Customer Domain),
-- Module 4 (Agent Domain), Module 5 (Investor Domain)
-- Depends on: 0012, 0013
-- ============================================================================

-- ============================================================================
-- MODULE 2 — LOAN TEMPLATES & CONFIGURATION
-- ============================================================================

-- loan_templates: Owner full manage. Agent needs read (template picker at
-- loan creation, AG-005/AG-007) gated by can_issue_loans. Customer needs
-- read too (CW-003 Request New Loan picks a template) — but only Active
-- templates; scoped via USING clause on status for the Customer policy.
ALTER TABLE loan_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_templates_owner_all ON loan_templates
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY loan_templates_agent_select ON loan_templates
  FOR SELECT
  USING (app.is_active_agent(business_id) AND app.agent_permission(business_id, 'can_issue_loans'));

CREATE POLICY loan_templates_customer_select_active ON loan_templates
  FOR SELECT
  USING (app.is_active_customer(business_id) AND status = 'Active');

-- ============================================================================
-- MODULE 3 — CUSTOMER DOMAIN
-- ============================================================================

-- customers: the anchor row. Owner: full. Agent: read/limited-write scoped
-- to ASSIGNED customers only (AG-004 PERMISSION section is explicit that
-- Can View Customers does not mean "whole business" — matches
-- assigned_agent_membership_id). Customer: self-read only (their own row).
-- Negative case this prevents: an Agent assigned to Customer A can never see
-- Customer B's row just because they share can_view_customers=true and the
-- same business; and a Customer can never see any other customer's row.
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY customers_owner_all ON customers
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(customers.membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(customers.membership_id)));

CREATE POLICY customers_agent_select_assigned ON customers
  FOR SELECT
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_membership(customers.membership_id), 'can_view_customers')
  );

CREATE POLICY customers_agent_update_contact_assigned ON customers
  FOR UPDATE
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_membership(customers.membership_id), 'can_edit_customer_contact')
  )
  WITH CHECK (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_membership(customers.membership_id), 'can_edit_customer_contact')
  );

CREATE POLICY customers_self_select ON customers
  FOR SELECT
  USING (app.membership_belongs_to_current_person(customers.membership_id));

-- Agent create-customer (can_create_customer) is deliberately NOT modeled as
-- a simple INSERT policy here: creating a customer requires simultaneously
-- creating the business_members row (role=Customer) AND the customers row
-- in a single transaction with a fresh or looked-up person_id — a raw client
-- INSERT policy on `customers` alone can't safely enforce "the membership
-- row it references was just created by me, for a person who consented".
-- Flagged in END RESULT: customer creation should go through a SECURITY
-- DEFINER RPC gated by can_create_customer, not direct table INSERT grants.

-- guarantors: belongs to the loan (BR-207), not customer identity. Owner:
-- full. Agent: scoped to loans they're the collection_agent on, or via
-- assigned-customer coverage — matching OW-005 "belongs to the loan" model.
-- Customer: read-only for guarantors on their OWN loans (visible in loan
-- detail per CW-004's Agreement Summary).
ALTER TABLE guarantors ENABLE ROW LEVEL SECURITY;

CREATE POLICY guarantors_owner_all ON guarantors
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = guarantors.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = guarantors.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY guarantors_agent_all_assigned ON guarantors
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = guarantors.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_view_customers')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = guarantors.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_issue_loans')
    )
  );

CREATE POLICY guarantors_customer_select_own ON guarantors
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = guarantors.loan_id AND app.is_own_customer_row(l.customer_id))
  );

-- customer_remarks: append-only (BR pattern: never edited). Owner: full read
-- + insert. Agent: insert+read scoped to assigned customer, gated by
-- can_add_remarks. Customer: NO access at all — remarks are an internal
-- Owner/Agent operational note surface (AG-004/OW-004), never customer-
-- visible per any screen spec. Judgment call, erring restrictive: no
-- Customer policy at all (deny-all default under RLS-enabled).
ALTER TABLE customer_remarks ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_remarks_owner_all ON customer_remarks
  FOR ALL
  USING (app.is_owner(app.business_id_for_customer(customer_remarks.customer_id)))
  WITH CHECK (app.is_owner(app.business_id_for_customer(customer_remarks.customer_id)));

CREATE POLICY customer_remarks_agent_select_assigned ON customer_remarks
  FOR SELECT
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(customer_remarks.customer_id), 'can_view_customers')
  );

CREATE POLICY customer_remarks_agent_insert_assigned ON customer_remarks
  FOR INSERT
  WITH CHECK (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(customer_remarks.customer_id), 'can_add_remarks')
    AND entered_by_person_id = app.current_person_id()
  );
-- No UPDATE/DELETE policy for any role — append-only per spec.

-- customer_documents: Owner full. Agent scoped to assigned customer, gated
-- by can_upload_documents for INSERT and can_view_customers for SELECT.
-- Customer: self-read only (their own docs) + self-insert of their own
-- documents (e.g. re-uploading a photo) — no UPDATE (never edited, only
-- archived per is_archived, and archival is an Owner/Agent action, not
-- self-service, so Customer gets no UPDATE policy).
ALTER TABLE customer_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_documents_owner_all ON customer_documents
  FOR ALL
  USING (app.is_owner(app.business_id_for_customer(customer_documents.customer_id)))
  WITH CHECK (app.is_owner(app.business_id_for_customer(customer_documents.customer_id)));

CREATE POLICY customer_documents_agent_select_assigned ON customer_documents
  FOR SELECT
  USING (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(customer_documents.customer_id), 'can_view_customers')
  );

CREATE POLICY customer_documents_agent_insert_assigned ON customer_documents
  FOR INSERT
  WITH CHECK (
    app.agent_covers_customer(customer_id)
    AND app.agent_permission(app.business_id_for_customer(customer_documents.customer_id), 'can_upload_documents')
  );

CREATE POLICY customer_documents_self_select ON customer_documents
  FOR SELECT
  USING (app.is_own_customer_row(customer_id));

CREATE POLICY customer_documents_self_insert ON customer_documents
  FOR INSERT
  WITH CHECK (app.is_own_customer_row(customer_id));

-- ============================================================================
-- MODULE 4 — AGENT DOMAIN
-- ============================================================================

-- agents: Owner full. Self-select (the Agent seeing their own row). No
-- Investor/Customer access at all — matches briefing's "Investor: ... no
-- access to Agent/Customer operational data at all" instruction.
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;

CREATE POLICY agents_owner_all ON agents
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(agents.membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(agents.membership_id)));

CREATE POLICY agents_self_select ON agents
  FOR SELECT
  USING (person_id = app.current_person_id());

-- agent_compensation_history: FINANCIALLY SENSITIVE — explicitly called out
-- in the briefing as one of the "tightest policy" tables. Owner: full manage
-- (it's the Owner's own compensation decision). Agent: self-select ONLY
-- (an Agent should see their own salary terms — no spec says they're
-- blocked from seeing their own pay — but nothing else). NO Investor access
-- (investor visibility into agent compensation is never granted by any
-- screen spec; explicitly excluded). No other Agent can ever see a
-- colleague's compensation row.
ALTER TABLE agent_compensation_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_compensation_history_owner_all ON agent_compensation_history
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_compensation_history.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_compensation_history.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY agent_compensation_history_self_select ON agent_compensation_history
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_compensation_history.agent_id AND a.person_id = app.current_person_id()));

-- agent_permissions: Owner full manage (this IS the permission-toggle
-- table, OW-002 C5d). Agent: self-select only, so the app can render
-- "what am I allowed to do" client-side — but NEVER self-UPDATE (an Agent
-- granting themselves permissions would be a privilege-escalation hole).
ALTER TABLE agent_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_permissions_owner_all ON agent_permissions
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_permissions.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_permissions.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY agent_permissions_self_select ON agent_permissions
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_permissions.agent_id AND a.person_id = app.current_person_id()));

-- agent_area_assignments: Owner full. Agent self-select (needs to know their
-- own assigned areas for AG-001/AG-003).
ALTER TABLE agent_area_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_area_assignments_owner_all ON agent_area_assignments
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_area_assignments.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_area_assignments.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY agent_area_assignments_self_select ON agent_area_assignments
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_area_assignments.agent_id AND a.person_id = app.current_person_id()));

-- agent_documents: same pattern as customer_documents (per schema note
-- "Same pattern as customer_documents"). Owner full. Agent self-manage own
-- docs (upload own ID/address proof).
ALTER TABLE agent_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_documents_owner_all ON agent_documents
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_documents.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_documents.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY agent_documents_self_all ON agent_documents
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_documents.agent_id AND a.person_id = app.current_person_id()))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_documents.agent_id AND a.person_id = app.current_person_id()));

-- cash_transfers: agent-to-agent BF transfer (BR-173). Owner: full read (and
-- write, for dispute resolution). Agent: read+confirm (UPDATE limited to
-- setting their own confirmation timestamp) where they are either party
-- (from_agent_id or to_agent_id). A raw column-scoped UPDATE isn't
-- expressible in USING/CHECK alone without a trigger guard, so — consistent
-- with the account_periods approach above — Agent gets SELECT here and
-- confirmation should go through a SECURITY DEFINER RPC. Flagged in END
-- RESULT.
ALTER TABLE cash_transfers ENABLE ROW LEVEL SECURITY;

CREATE POLICY cash_transfers_owner_all ON cash_transfers
  FOR ALL
  USING (
    EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = cash_transfers.from_agent_id AND app.is_owner(bm.business_id))
    OR EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = cash_transfers.to_agent_id AND app.is_owner(bm.business_id))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = cash_transfers.from_agent_id AND app.is_owner(bm.business_id))
    OR EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = cash_transfers.to_agent_id AND app.is_owner(bm.business_id))
  );

CREATE POLICY cash_transfers_agent_select_party ON cash_transfers
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = cash_transfers.from_agent_id AND a.person_id = app.current_person_id())
    OR EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = cash_transfers.to_agent_id AND a.person_id = app.current_person_id())
  );

-- ============================================================================
-- MODULE 5 — INVESTOR DOMAIN
-- ============================================================================

-- investors: Owner full. Self-select. Zero Agent/Customer access, per
-- briefing ("Investor: ... no access to other Investors' figures").
ALTER TABLE investors ENABLE ROW LEVEL SECURITY;

CREATE POLICY investors_owner_all ON investors
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(investors.membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(investors.membership_id)));

CREATE POLICY investors_self_select ON investors
  FOR SELECT
  USING (person_id = app.current_person_id());

-- investments: Owner full. Investor: read-only, OWN investments only
-- (IW-003 PERMISSION model — "scoped to that business", each investment
-- independent per BR-029/030). Agent: read-only IF can_view_investor_info
-- (schema explicitly has this flag) — still business-wide by design (the
-- permission is literally named "view investor info", not "view own
-- assigned investor's info" — there's no assigned-investor concept
-- anywhere in the schema, unlike Agent-Customer assignment). Negative case:
-- an Investor never sees another Investor's investments row, ever, and an
-- Agent without can_view_investor_info sees none at all.
ALTER TABLE investments ENABLE ROW LEVEL SECURITY;

CREATE POLICY investments_owner_all ON investments
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY investments_investor_select_own ON investments
  FOR SELECT
  USING (
    app.is_active_investor(business_id)
    AND EXISTS (SELECT 1 FROM investors i WHERE i.investor_id = investments.investor_id AND i.person_id = app.current_person_id())
  );

CREATE POLICY investments_agent_select_with_permission ON investments
  FOR SELECT
  USING (app.is_active_agent(business_id) AND app.agent_permission(business_id, 'can_view_investor_info'));

-- investment_interest_ledger: FINANCIALLY SENSITIVE. Owner: full (owner_verified
-- flag is an Owner-only action per BR-055). Investor: read-only, own
-- investments only. Agent: read-only via can_view_investor_info, mirroring
-- investments above (an Agent who can see the investment record can see its
-- interest ledger — consistent scope; not granting Agent WRITE, since ledger
-- entries are system/Owner generated, never Agent-entered per any spec).
ALTER TABLE investment_interest_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY investment_interest_ledger_owner_all ON investment_interest_ledger
  FOR ALL
  USING (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_interest_ledger.investment_id AND app.is_owner(inv.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_interest_ledger.investment_id AND app.is_owner(inv.business_id)));

CREATE POLICY investment_interest_ledger_investor_select_own ON investment_interest_ledger
  FOR SELECT
  USING (app.is_own_investment_row(investment_id));

CREATE POLICY investment_interest_ledger_agent_select ON investment_interest_ledger
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM investments inv
      WHERE inv.investment_id = investment_interest_ledger.investment_id
        AND app.is_active_agent(inv.business_id)
        AND app.agent_permission(inv.business_id, 'can_view_investor_info')
    )
  );

-- investment_withdrawals: FINANCIALLY SENSITIVE, Owner-approved only
-- (approved_by_person_id is always Owner per schema note). Owner: full.
-- Investor: read-only, own investments (they need to see their own
-- withdrawal history). No Agent access — withdrawals are an Owner<->Investor
-- financial transaction; the briefing's default-conservative instruction
-- applies here since no screen spec grants Agent visibility into investor
-- withdrawal amounts.
ALTER TABLE investment_withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY investment_withdrawals_owner_all ON investment_withdrawals
  FOR ALL
  USING (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_withdrawals.investment_id AND app.is_owner(inv.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_withdrawals.investment_id AND app.is_owner(inv.business_id)));

CREATE POLICY investment_withdrawals_investor_select_own ON investment_withdrawals
  FOR SELECT
  USING (app.is_own_investment_row(investment_id));

-- investment_withdrawal_requests: Investor self-service request layer
-- (IW-004). Investor: self-insert + self-select (their own requests only).
-- Owner: full manage (approve/reject/pay).
ALTER TABLE investment_withdrawal_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY investment_withdrawal_requests_owner_all ON investment_withdrawal_requests
  FOR ALL
  USING (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_withdrawal_requests.investment_id AND app.is_owner(inv.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM investments inv WHERE inv.investment_id = investment_withdrawal_requests.investment_id AND app.is_owner(inv.business_id)));

CREATE POLICY investment_withdrawal_requests_investor_select_own ON investment_withdrawal_requests
  FOR SELECT
  USING (requested_by_person_id = app.current_person_id() AND app.is_own_investment_row(investment_id));

CREATE POLICY investment_withdrawal_requests_investor_insert_own ON investment_withdrawal_requests
  FOR INSERT
  WITH CHECK (requested_by_person_id = app.current_person_id() AND app.is_own_investment_row(investment_id));

-- distribution_declarations / distribution_payments: FINANCIALLY SENSITIVE
-- (profit share). Owner: full. Agent: self-select ONLY on rows where
-- recipient_type='Agent' AND agent_id is their own (they should see their
-- own declared/paid profit share, nothing else). Investor: self-select ONLY
-- on rows where recipient_type='Investor' AND investment_id is their own.
-- Negative case: an Agent never sees another Agent's or any Investor's
-- distribution row, and vice versa.
ALTER TABLE distribution_declarations ENABLE ROW LEVEL SECURITY;

CREATE POLICY distribution_declarations_owner_all ON distribution_declarations
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY distribution_declarations_agent_select_own ON distribution_declarations
  FOR SELECT
  USING (
    recipient_type = 'Agent'
    AND EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = distribution_declarations.agent_id AND a.person_id = app.current_person_id())
  );

CREATE POLICY distribution_declarations_investor_select_own ON distribution_declarations
  FOR SELECT
  USING (recipient_type = 'Investor' AND app.is_own_investment_row(investment_id));

ALTER TABLE distribution_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY distribution_payments_owner_all ON distribution_payments
  FOR ALL
  USING (EXISTS (SELECT 1 FROM distribution_declarations dd WHERE dd.declaration_id = distribution_payments.declaration_id AND app.is_owner(dd.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM distribution_declarations dd WHERE dd.declaration_id = distribution_payments.declaration_id AND app.is_owner(dd.business_id)));

CREATE POLICY distribution_payments_agent_select_own ON distribution_payments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM distribution_declarations dd
      JOIN agents a ON a.agent_id = dd.agent_id
      WHERE dd.declaration_id = distribution_payments.declaration_id
        AND dd.recipient_type = 'Agent'
        AND a.person_id = app.current_person_id()
    )
  );

CREATE POLICY distribution_payments_investor_select_own ON distribution_payments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM distribution_declarations dd
      WHERE dd.declaration_id = distribution_payments.declaration_id
        AND dd.recipient_type = 'Investor'
        AND app.is_own_investment_row(dd.investment_id)
    )
  );

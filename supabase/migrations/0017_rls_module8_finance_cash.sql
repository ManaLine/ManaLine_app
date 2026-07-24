-- ============================================================================
-- 0017_rls_module8_finance_cash.sql
-- MANA LINE — RLS: Module 8 (Finance / Cash / Day Closure)
-- Depends on: 0012, 0013, 0014
--
-- This module holds the business's internal cash figures. Per the briefing:
-- "Customer: ... zero visibility into business-internal figures (BF cash,
-- agent compensation, other customers)." Every table below therefore has NO
-- Customer policy and NO Investor policy unless a specific screen spec
-- explicitly grants one (none do, in the reviewed specs) — erring
-- restrictive throughout this entire module.
-- ============================================================================

-- expenses: Owner: full. Agent: insert+select scoped to own entries
-- (recorded_by_membership_id = self), gated a plausible permission — no
-- screen spec names an explicit "can_record_expenses" flag; closest fit is
-- can_perform_day_settlement (expenses are part of day-level cash
-- accounting) OR general agent membership. JUDGMENT CALL, erring
-- restrictive: I gated this on can_perform_day_settlement rather than
-- leaving it open to any active Agent, since expenses directly affect BF
-- cash and day_ledger totals. Flagged in END RESULT for confirmation this
-- is the right permission flag (spec doesn't name one explicitly).
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY expenses_owner_all ON expenses
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY expenses_agent_select_own ON expenses
  FOR SELECT
  USING (
    app.is_active_agent(business_id)
    AND recorded_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

CREATE POLICY expenses_agent_insert_own ON expenses
  FOR INSERT
  WITH CHECK (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_perform_day_settlement')
    AND recorded_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

-- day_ledger (Daily Record Book): FINANCIALLY SENSITIVE, business-wide cash
-- summary. Owner: full. Agent: read-only, gated can_view_reports (this is
-- report-hub-adjacent data per OW-009/OW-010) — NOT scoped to "own entries"
-- since it's an aggregate business-wide figure, not a per-agent one; the
-- permission flag is the only available control. No client INSERT/UPDATE
-- for Agent — the ledger is system-computed from collections/loans/expenses,
-- never directly entered.
ALTER TABLE day_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY day_ledger_owner_all ON day_ledger
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY day_ledger_agent_select ON day_ledger
  FOR SELECT
  USING (app.is_active_agent(business_id) AND app.agent_permission(business_id, 'can_view_reports'));

-- day_closures: Owner-only per schema ("closed_by_person_id | FK→persons |
-- Owner only", "reopened_at | ... | Owner-only (BR-221)"). No Agent policy
-- at all — erring restrictive and matching the schema note explicitly.
ALTER TABLE day_closures ENABLE ROW LEVEL SECURITY;

CREATE POLICY day_closures_owner_all ON day_closures
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

-- account_settlements: FINANCIALLY SENSITIVE — Agent daily/weekly/monthly
-- settlement TO Owner (AG-006). Owner: full (reviews/approves/returns).
-- Agent: self-select + self-insert (submitting their own settlement) ONLY
-- for their own agent_id — never another agent's settlement, and never able
-- to self-approve (status transitions to Approved/Returned are Owner-only,
-- enforced by giving Agent INSERT only, no UPDATE policy at all).
ALTER TABLE account_settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY account_settlements_owner_all ON account_settlements
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = account_settlements.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = account_settlements.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY account_settlements_agent_select_own ON account_settlements
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = account_settlements.agent_id AND a.person_id = app.current_person_id()));

CREATE POLICY account_settlements_agent_insert_own ON account_settlements
  FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = account_settlements.agent_id AND a.person_id = app.current_person_id())
    AND status = 'Pending Owner Review'
  );

-- settlement_adjustments: FINANCIALLY SENSITIVE (explicitly named in the
-- briefing as one of the tightest-policy tables). Owner: full — "applied_to"
-- is explicitly "Owner-controlled, never automatic" per schema. Agent:
-- self-select ONLY on rows where agent_id is their own (they should be able
-- to see their own Short/Excess register entries — nothing says they're
-- blocked from seeing their own — but NO insert/update at all; this table
-- is entirely Owner-authored). No Customer/Investor access even when
-- target_customer_id references them — this is an internal accounting
-- adjustment record, not a customer-facing statement.
ALTER TABLE settlement_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY settlement_adjustments_owner_all ON settlement_adjustments
  FOR ALL
  USING (
    (agent_id IS NOT NULL AND EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = settlement_adjustments.agent_id AND app.is_owner(bm.business_id)))
    OR (settlement_id IS NOT NULL AND EXISTS (SELECT 1 FROM account_settlements s JOIN agents a ON a.agent_id = s.agent_id JOIN business_members bm ON bm.membership_id = a.membership_id WHERE s.settlement_id = settlement_adjustments.settlement_id AND app.is_owner(bm.business_id)))
  )
  WITH CHECK (
    (agent_id IS NOT NULL AND EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = settlement_adjustments.agent_id AND app.is_owner(bm.business_id)))
    OR (settlement_id IS NOT NULL AND EXISTS (SELECT 1 FROM account_settlements s JOIN agents a ON a.agent_id = s.agent_id JOIN business_members bm ON bm.membership_id = a.membership_id WHERE s.settlement_id = settlement_adjustments.settlement_id AND app.is_owner(bm.business_id)))
  );

CREATE POLICY settlement_adjustments_agent_select_own ON settlement_adjustments
  FOR SELECT
  USING (agent_id IS NOT NULL AND EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = settlement_adjustments.agent_id AND a.person_id = app.current_person_id()));

-- agent_salary_ledger: FINANCIALLY SENSITIVE (named explicitly in briefing).
-- Owner: full — "stays unpaid until Owner pays (BR-071)". Agent: self-select
-- ONLY, own rows. No write access for Agent at all.
ALTER TABLE agent_salary_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_salary_ledger_owner_all ON agent_salary_ledger
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_salary_ledger.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = agent_salary_ledger.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY agent_salary_ledger_self_select ON agent_salary_ledger
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = agent_salary_ledger.agent_id AND a.person_id = app.current_person_id()));

-- salary_advances: Owner: full. Agent: self-select own advances. No client
-- Agent INSERT — an Agent requesting/receiving an advance is an Owner
-- decision/entry per every screen reference to advances (OW-002/OW-013
-- context), not self-service.
ALTER TABLE salary_advances ENABLE ROW LEVEL SECURITY;

CREATE POLICY salary_advances_owner_all ON salary_advances
  FOR ALL
  USING (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = salary_advances.agent_id AND app.is_owner(bm.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM agents a JOIN business_members bm ON bm.membership_id = a.membership_id WHERE a.agent_id = salary_advances.agent_id AND app.is_owner(bm.business_id)));

CREATE POLICY salary_advances_self_select ON salary_advances
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = salary_advances.agent_id AND a.person_id = app.current_person_id()));

-- ----------------------------------------------------------------------------
-- Addendum tables introduced in the "MERGED ADDENDUM CONTENT" section of the
-- schema doc: agent_access_days, agent_bf_assignments, loan_groups,
-- loan_group_members. These weren't given their own numbered module in the
-- briefing's file list, but they are Module 8/6-adjacent cash/loan tables
-- referenced nowhere else — homing them here (BF/cash) and in loan domain
-- policy style, flagged explicitly in END RESULT since the briefing's module
-- boundaries didn't anticipate them by name.
-- ----------------------------------------------------------------------------

-- agent_access_days: Owner grants/edits (granted_by_membership_id is always
-- Owner). Agent: self-select own access-day rows only.
ALTER TABLE agent_access_days ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_access_days_owner_all ON agent_access_days
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(agent_access_days.membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(agent_access_days.membership_id)));

CREATE POLICY agent_access_days_self_select ON agent_access_days
  FOR SELECT
  USING (app.membership_belongs_to_current_person(agent_access_days.membership_id));

-- agent_bf_assignments: Owner sets opening_bf/agent_bf_current. Agent:
-- self-select + a narrow self-UPDATE limited to the two boolean
-- confirmation flags at session start (confirmed_by_agent /
-- update_requested) — same caveat as account_periods/cash_transfers above:
-- RLS can't cleanly restrict which columns an UPDATE touches, so Agent
-- confirmation should go through a SECURITY DEFINER RPC rather than a raw
-- UPDATE grant. Flagged in END RESULT. Agent therefore gets SELECT only
-- here at the RLS layer.
ALTER TABLE agent_bf_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_bf_assignments_owner_all ON agent_bf_assignments
  FOR ALL
  USING (app.is_owner(app.business_id_for_membership(agent_bf_assignments.membership_id)))
  WITH CHECK (app.is_owner(app.business_id_for_membership(agent_bf_assignments.membership_id)));

CREATE POLICY agent_bf_assignments_self_select ON agent_bf_assignments
  FOR SELECT
  USING (app.membership_belongs_to_current_person(agent_bf_assignments.membership_id));

-- loan_groups: created_by Owner or Agent (schema explicit). Owner: full.
-- Agent: insert+select for groups they created, gated can_issue_loans
-- (grouping is part of the loan-issuance workflow). Customer: read-only via
-- their own loan's group membership (see loan_group_members policy — a
-- Customer needs to see their Group Balance/EMI aggregate per the schema's
-- "Group Balance/EMI are computed aggregates" note, which implies customer
-- visibility into their own group).
ALTER TABLE loan_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_groups_owner_all ON loan_groups
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY loan_groups_agent_select ON loan_groups
  FOR SELECT
  USING (app.is_active_agent(business_id) AND app.agent_permission(business_id, 'can_issue_loans'));

CREATE POLICY loan_groups_agent_insert ON loan_groups
  FOR INSERT
  WITH CHECK (
    app.is_active_agent(business_id)
    AND app.agent_permission(business_id, 'can_issue_loans')
    AND created_by_membership_id = app.active_membership_id(business_id, 'Agent')
  );

-- loan_group_members: visibility follows the member loan's own visibility
-- (Owner/assigned-Agent/owning-Customer), same join pattern as guarantors.
ALTER TABLE loan_group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY loan_group_members_owner_all ON loan_group_members
  FOR ALL
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_group_members.loan_id AND app.is_owner(l.business_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_group_members.loan_id AND app.is_owner(l.business_id)));

CREATE POLICY loan_group_members_agent_all_assigned ON loan_group_members
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = loan_group_members.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_issue_loans')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM loans l
      WHERE l.loan_id = loan_group_members.loan_id
        AND app.agent_covers_customer(l.customer_id)
        AND app.agent_permission(l.business_id, 'can_issue_loans')
    )
  );

CREATE POLICY loan_group_members_customer_select_own ON loan_group_members
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM loans l WHERE l.loan_id = loan_group_members.loan_id AND app.is_own_customer_row(l.customer_id)));

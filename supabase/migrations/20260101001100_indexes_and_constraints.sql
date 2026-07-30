-- =============================================================================
-- MANA LINE — Cross-Module Indexes & Constraints
-- All forward-reference FKs required by earlier modules were closed inline,
-- in the migration file where the referenced table was created, each
-- annotated at the point of use:
--   - person_addresses.village_id  -> locations(location_id)   (closed in 0002)
--   - business_members.permission_profile_id -> agent_permissions(permission_profile_id) (closed in 0005)
--   - guarantors.loan_id -> loans(loan_id)                     (closed in 0007)
--   - distribution_declarations.agent_id -> agents(agent_id)   (closed in 0006, agents already existed)
-- This file holds only additional cross-module composite indexes that
-- support common multi-table query patterns, plus a couple of constraints
-- that only make sense once every referenced table exists.
-- =============================================================================

-- Common lookup: all active loans for a business, by status
CREATE INDEX idx_loans_business_status ON loans(business_id, loan_status);

-- Common lookup: a customer's loans within a business
CREATE INDEX idx_loans_business_customer ON loans(business_id, customer_id);

-- Common lookup: collections for a business_date range (day ledger reconciliation)
CREATE INDEX idx_collections_business_date ON collections(business_date);

-- Common lookup: business_members by business + role + status (capacity/queue screens, BR-192)
CREATE INDEX idx_business_members_business_role_status ON business_members(business_id, role, membership_status);

-- Common lookup: notifications inbox, unread-first
CREATE INDEX idx_notifications_recipient_unread ON notifications(recipient_person_id, is_read);

-- Common lookup: account_periods by business + status (Overdue/Submitted queues, OW-011)
CREATE INDEX idx_account_periods_business_status ON account_periods(business_id, status);

-- Common lookup: agent_bf_assignments by membership + business_date (session-start gate lookups, Merged Addendum item 4)
CREATE INDEX idx_agent_bf_assignments_membership_date ON agent_bf_assignments(membership_id, business_date);

-- Common lookup: day_ledger by business, most-recent-first pattern support
CREATE INDEX idx_day_ledger_business_date ON day_ledger(business_id, business_date DESC);

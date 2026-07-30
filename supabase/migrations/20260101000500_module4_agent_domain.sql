-- =============================================================================
-- MANA LINE — Module 4: Agent Domain
-- Source: 03_Database_Schema.md §4.1-4.6, plus Merged Addendum item 3
-- (agent_access_days) and item 4 (agent_bf_assignments)
-- =============================================================================

CREATE TYPE agent_current_status_enum AS ENUM ('Active', 'Disabled', 'Suspended', 'Removed');
CREATE TYPE salary_cycle_enum AS ENUM ('Monthly', 'Custom');

-- ---------------------------------------------------------------------------
-- 4.1 agents — FK 1:1 into business_members (role=Agent)
-- ---------------------------------------------------------------------------
CREATE TABLE agents (
    agent_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id       UUID NOT NULL UNIQUE REFERENCES business_members(membership_id),
    person_id           BIGINT NOT NULL REFERENCES persons(person_id),
    joined_date          DATE NOT NULL,
    current_status        agent_current_status_enum NOT NULL DEFAULT 'Active'
);

-- ---------------------------------------------------------------------------
-- 4.3 agent_permissions — granular, per business membership (BR-073-080)
-- Created before 4.2 in file order isn't required, but placed here since
-- business_members.permission_profile_id (Module 1) forward-references this
-- table's PK; the FK constraint itself is added in 0011.
-- ---------------------------------------------------------------------------
CREATE TABLE agent_permissions (
    permission_profile_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id                   UUID NOT NULL REFERENCES agents(agent_id),
    can_collect_payments         BOOLEAN NOT NULL DEFAULT FALSE,
    can_issue_loans              BOOLEAN NOT NULL DEFAULT FALSE,
    can_view_customers            BOOLEAN NOT NULL DEFAULT FALSE,
    can_create_drafts             BOOLEAN NOT NULL DEFAULT FALSE,
    can_edit_own_drafts            BOOLEAN NOT NULL DEFAULT FALSE,
    can_cancel_own_drafts           BOOLEAN NOT NULL DEFAULT FALSE,
    can_view_reports               BOOLEAN NOT NULL DEFAULT FALSE,
    can_view_dashboard              BOOLEAN NOT NULL DEFAULT FALSE,
    can_export_reports              BOOLEAN NOT NULL DEFAULT FALSE,
    can_view_investor_info           BOOLEAN NOT NULL DEFAULT FALSE,
    can_perform_day_settlement        BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_collection_mode         BOOLEAN NOT NULL DEFAULT FALSE,
    can_upload_documents               BOOLEAN NOT NULL DEFAULT FALSE,
    can_add_remarks                    BOOLEAN NOT NULL DEFAULT FALSE,
    can_transfer_collections            BOOLEAN NOT NULL DEFAULT FALSE,
    can_apply_penalty                   BOOLEAN NOT NULL DEFAULT FALSE,   -- BR-236, OFF by default
    can_create_customer                  BOOLEAN NOT NULL DEFAULT FALSE,
    can_edit_customer_contact             BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at                            TIMESTAMP NOT NULL DEFAULT now() -- takes effect immediately, historical txns unaffected
);

-- Forward-reference FK from Module 1 (business_members.permission_profile_id)
ALTER TABLE business_members
    ADD CONSTRAINT fk_business_members_permission_profile FOREIGN KEY (permission_profile_id) REFERENCES agent_permissions(permission_profile_id);

-- ---------------------------------------------------------------------------
-- 4.2 agent_compensation_history — effective-dated (BR-067/068, OW-002)
-- ---------------------------------------------------------------------------
CREATE TABLE agent_compensation_history (
    compensation_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id                UUID NOT NULL REFERENCES agents(agent_id),
    fixed_salary_amount       DECIMAL(14,0) NOT NULL,
    salary_cycle              salary_cycle_enum NOT NULL,
    daily_allowance             DECIMAL(14,0) NULL,                       -- Note: BR-046 'reduces final salary' language is SUPERSEDED by Merged Addendum item 3; kept here for historical compensation records only, agent_access_days is the live daily-allowance mechanism
    profit_share_percent          DECIMAL(5,2) NULL,                      -- optional, tentative, disabled by default (BR-232)
    effective_date                DATE NOT NULL,
    superseded_at                  TIMESTAMP NULL,                        -- when replaced by a new row
    created_at                     TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4.4 agent_area_assignments
-- ---------------------------------------------------------------------------
CREATE TABLE agent_area_assignments (
    assignment_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id               UUID NOT NULL REFERENCES agents(agent_id),
    operating_area_id       UUID NOT NULL REFERENCES operating_areas(operating_area_id),
    assigned_at              TIMESTAMP NOT NULL DEFAULT now(),
    removed_at                TIMESTAMP NULL
);

-- ---------------------------------------------------------------------------
-- 4.5 agent_documents — same pattern as customer_documents
-- ---------------------------------------------------------------------------
CREATE TABLE agent_documents (
    document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id           UUID NOT NULL REFERENCES agents(agent_id),
    document_type      customer_document_type_enum NOT NULL,             -- reuses Module 3's document-type enum, same value set applies
    file_url            TEXT NOT NULL,
    is_archived          BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_at           TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4.6 cash_transfers — agent-to-agent BF cash transfer (BR-173)
-- ---------------------------------------------------------------------------
CREATE TABLE cash_transfers (
    transfer_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_agent_id                UUID NOT NULL REFERENCES agents(agent_id),
    to_agent_id                  UUID NOT NULL REFERENCES agents(agent_id),
    amount                       DECIMAL(14,0) NOT NULL,
    business_date                 DATE NOT NULL,
    entry_timestamp                TIMESTAMP NOT NULL DEFAULT now(),
    from_agent_confirmed_at          TIMESTAMP NULL,
    to_agent_confirmed_at             TIMESTAMP NULL,
    CONSTRAINT chk_cash_transfers_distinct_agents CHECK (from_agent_id <> to_agent_id)
);

-- ---------------------------------------------------------------------------
-- Merged Addendum item 3 — agent_access_days (NEW, no salary linkage)
-- Populates the Daily Allowance tab on OW-013. Zero relationship to
-- agent_salary_ledger — paid same-day, direct cash, outside the salary cycle.
-- ---------------------------------------------------------------------------
CREATE TABLE agent_access_days (
    access_day_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id               UUID NOT NULL REFERENCES business_members(membership_id), -- the Agent
    business_date                DATE NOT NULL,
    granted_by_membership_id       UUID NOT NULL REFERENCES business_members(membership_id), -- Owner who granted access
    allowance_amount              DECIMAL(14,0) NOT NULL,                -- e.g. 200/day, paid same-day cash
    created_at                    TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                    TIMESTAMP NOT NULL DEFAULT now()       -- Owner can edit access days after grant
);

-- ---------------------------------------------------------------------------
-- Merged Addendum item 4 — agent_bf_assignments (NEW, session-based BF model)
-- ---------------------------------------------------------------------------
CREATE TABLE agent_bf_assignments (
    assignment_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id                UUID NOT NULL REFERENCES business_members(membership_id), -- the Agent
    account_period_id             UUID NULL REFERENCES account_periods(account_period_id), -- session-based; doc allows business_date OR FK->account_periods
    business_date                 DATE NULL,
    opening_bf                    DECIMAL(14,0) NOT NULL,                -- defaults to previous session's Closing BF, Owner-overridable before granting access
    agent_bf_current               DECIMAL(14,0) NOT NULL DEFAULT 0,     -- set by Owner via 'Agent BF' tab
    confirmed_by_agent              BOOLEAN NOT NULL DEFAULT FALSE,      -- TRUE when Agent taps Confirm on session-start pop-up
    update_requested                BOOLEAN NOT NULL DEFAULT FALSE,      -- TRUE when Agent taps Update instead - blocks entry, notifies Owner
    created_at                      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_agent_bf_assignments_session_key CHECK (account_period_id IS NOT NULL OR business_date IS NOT NULL)
);
COMMENT ON TABLE agent_bf_assignments IS 'Session-based per Merged Addendum item 4: session identified by account_period_id OR business_date, not hardcoded to one. BF floor at 0 and blocking rules are application-layer, not DB constraints, since a Draft-save fallback path exists (collection_drafts, draft_type=Loan Distribution).';

CREATE INDEX idx_agent_permissions_agent ON agent_permissions(agent_id);
CREATE INDEX idx_agent_compensation_agent ON agent_compensation_history(agent_id);
CREATE INDEX idx_agent_area_assignments_agent ON agent_area_assignments(agent_id);
CREATE INDEX idx_agent_documents_agent ON agent_documents(agent_id);
CREATE INDEX idx_cash_transfers_from ON cash_transfers(from_agent_id);
CREATE INDEX idx_cash_transfers_to ON cash_transfers(to_agent_id);
CREATE INDEX idx_agent_access_days_membership ON agent_access_days(membership_id);
CREATE INDEX idx_agent_bf_assignments_membership ON agent_bf_assignments(membership_id);

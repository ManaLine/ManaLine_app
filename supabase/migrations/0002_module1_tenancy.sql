-- =============================================================================
-- MANA LINE — Module 1: Tenancy / Business
-- Source: 03_Database_Schema.md §1.1–1.10, plus Merged Addendum items 4 & 5
-- (owner_bf_balance, allow_multi_group_membership added to businesses)
-- =============================================================================

CREATE TYPE business_status_enum AS ENUM ('Active', 'Not Started', 'Suspended');
CREATE TYPE location_area_type_enum AS ENUM ('Village', 'Town');
CREATE TYPE location_status_enum AS ENUM ('Active', 'Inactive');
CREATE TYPE operating_area_status_enum AS ENUM ('Active', 'Inactive');
CREATE TYPE account_cycle_unit_enum AS ENUM ('Days', 'Weeks', 'Months');
CREATE TYPE route_status_enum AS ENUM ('Active', 'Inactive');
CREATE TYPE agreement_type_enum AS ENUM ('Customer', 'Agent', 'Investor');
CREATE TYPE agreement_source_type_enum AS ENUM ('Uploaded PDF', 'In-App');
CREATE TYPE business_member_role_enum AS ENUM ('Owner', 'Agent', 'Investor', 'Customer');
CREATE TYPE membership_status_enum AS ENUM ('Pending Invitation', 'Pending Acceptance', 'Active', 'Temporarily Disabled', 'Suspended', 'Removed', 'Pending Approval');
CREATE TYPE membership_verification_status_enum AS ENUM ('Not Required', 'Pending Verification', 'Verified');
CREATE TYPE onboarding_method_enum AS ENUM ('Direct Registration', 'ID Lookup', 'Migration/Pre-Existing');
CREATE TYPE membership_request_role_enum AS ENUM ('Customer', 'Investor');
CREATE TYPE membership_request_status_enum AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE account_period_status_enum AS ENUM ('Running', 'Overdue', 'Submitted', 'Approved', 'Locked');

-- ---------------------------------------------------------------------------
-- 1.1 businesses — one Owner per business (BR-185); one Owner may own many
-- (BR-119 REVISED — confirmed decision: multi-business per Owner allowed in
-- V1, each business independent with its own MLBI/areas/accounting). No
-- UNIQUE constraint on owner_person_id, intentionally, to support this.
-- ---------------------------------------------------------------------------
CREATE TABLE businesses (
    business_id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mlbi                              VARCHAR(20) NOT NULL UNIQUE,        -- e.g. MLBI-00000125, system-generated, immutable
    owner_person_id                   BIGINT NOT NULL REFERENCES persons(person_id), -- exactly one Owner per business (BR-185); NOT unique here — BR-119 revised allows one owner -> many businesses
    business_name                     VARCHAR(150) NOT NULL,
    registered_finance_name            VARCHAR(150) NOT NULL,
    logo_url                          TEXT NULL,
    business_type                     VARCHAR(100) NULL,
    business_address                  TEXT NULL,
    business_phone                    VARCHAR(15) NULL,
    business_email                    VARCHAR(150) NULL,
    business_status                    business_status_enum NOT NULL DEFAULT 'Not Started',
    accepting_new_customers            BOOLEAN NOT NULL DEFAULT TRUE,     -- CW-002
    accepting_new_investors            BOOLEAN NOT NULL DEFAULT TRUE,     -- IW-002
    customer_loan_requests_allowed      BOOLEAN NOT NULL DEFAULT FALSE,   -- OW-013 settings
    migration_locked                   BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE once 'Business Started' clicked (BR-159)
    business_started_at                 TIMESTAMP NULL,
    max_investors                      INT NULL,                         -- BR-186 Owner-adjustable cap
    max_agents                        INT NULL,
    max_customers                      INT NULL,
    owner_bf_balance                    DECIMAL(14,0) NOT NULL DEFAULT 0, -- Addendum item 4 — business-level BF cash pool
    allow_multi_group_membership         BOOLEAN NOT NULL DEFAULT FALSE,  -- Addendum item 5 — Group Loans toggle
    created_at                          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON COLUMN businesses.owner_person_id IS 'BR-119 revised (confirmed): multi-business per Owner IS allowed in V1 — one owner may own multiple independent businesses, each with its own MLBI/areas/accounting. Intentionally not UNIQUE.';

-- ---------------------------------------------------------------------------
-- 1.2 locations — master location data, permanent, shared across businesses
-- ---------------------------------------------------------------------------
CREATE TABLE locations (
    location_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pin_code             VARCHAR(6) NOT NULL,
    village_town_name     VARCHAR(150) NOT NULL,
    area_type            location_area_type_enum NOT NULL,
    mandal               VARCHAR(100) NOT NULL,
    district             VARCHAR(100) NOT NULL,
    state                VARCHAR(100) NOT NULL,
    status               location_status_enum NOT NULL DEFAULT 'Active' -- never hard-deleted (BR-127)
);

-- Forward-reference FK from Module 0 now that locations exists.
ALTER TABLE person_addresses
    ADD CONSTRAINT fk_person_addresses_village FOREIGN KEY (village_id) REFERENCES locations(location_id);

-- ---------------------------------------------------------------------------
-- 1.3 operating_areas
-- ---------------------------------------------------------------------------
CREATE TABLE operating_areas (
    operating_area_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id              UUID NOT NULL REFERENCES businesses(business_id),
    location_id              UUID NOT NULL REFERENCES locations(location_id),
    status                   operating_area_status_enum NOT NULL DEFAULT 'Active', -- Owner can disable (AG-001)
    account_cycle_duration    INT NOT NULL,                                -- e.g. 3
    account_cycle_unit        account_cycle_unit_enum NOT NULL,
    submission_time           TIME NOT NULL,                               -- e.g. 21:00
    created_at                TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 1.8 business_members — central polymorphic membership table (BR-179)
-- Created here, ahead of routes/1.4, because routes.default_agent_id FKs it.
-- ---------------------------------------------------------------------------
CREATE TABLE business_members (
    membership_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id                 BIGINT NOT NULL REFERENCES persons(person_id),
    business_id                UUID NOT NULL REFERENCES businesses(business_id),
    role                       business_member_role_enum NOT NULL,
    membership_status          membership_status_enum NOT NULL DEFAULT 'Pending Invitation', -- 'Pending Approval' = capacity overflow queue (BR-192)
    verification_status         membership_verification_status_enum NOT NULL DEFAULT 'Not Required', -- Customer=Not Required (BR-189); Agent/Investor=OTP-gated (BR-188/190/191)
    onboarding_method           onboarding_method_enum NOT NULL,           -- BR-204/OW-015
    invited_by_person_id         BIGINT NULL REFERENCES persons(person_id),
    joined_at                   TIMESTAMP NULL,                            -- when Active
    removed_at                  TIMESTAMP NULL,                            -- membership closed, history preserved (BR-203)
    locked_by_this_owner         BOOLEAN NOT NULL DEFAULT FALSE,           -- per-owner lock, no cross-tenancy effect (BR-203)
    permission_profile_id         UUID NULL,                                -- FK -> agent_permissions, added in 0011 (Agent role only; agent_permissions is Module 4)
    created_at                   TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_business_members_person_business_role UNIQUE (person_id, business_id, role)
);
COMMENT ON TABLE business_members IS 'Anchor row for every role (BR-179 — roles are additive toggles on one identity). Role-specific detail lives in customers/agents/investors, each FK to membership_id.';
COMMENT ON COLUMN business_members.permission_profile_id IS 'Agent-role only. FK to agent_permissions(permission_profile_id) added in 0011_indexes_and_constraints.sql since agent_permissions is defined in Module 4, after this table.';

-- ---------------------------------------------------------------------------
-- 1.4 routes — reusable collection plans (BR-027, BR-131-138)
-- ---------------------------------------------------------------------------
CREATE TABLE routes (
    route_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id           UUID NOT NULL REFERENCES businesses(business_id),
    route_name            VARCHAR(150) NOT NULL,
    status                route_status_enum NOT NULL DEFAULT 'Active',
    default_agent_id       UUID NULL REFERENCES business_members(membership_id), -- BR-134
    effective_date         DATE NOT NULL                                  -- route changes apply prospectively (BR-136)
);

-- ---------------------------------------------------------------------------
-- 1.5 route_locations — many-to-many, ordered (BR-132/133/137)
-- ---------------------------------------------------------------------------
CREATE TABLE route_locations (
    route_location_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id              UUID NOT NULL REFERENCES routes(route_id),
    location_id           UUID NOT NULL REFERENCES locations(location_id), -- a location may belong to multiple routes (BR-137)
    visit_order            INT NOT NULL                                    -- manual ordering (BR-133)
);

-- ---------------------------------------------------------------------------
-- 1.6 business_agreements — templates (OW-013)
-- ---------------------------------------------------------------------------
CREATE TABLE business_agreements (
    agreement_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id               UUID NOT NULL REFERENCES businesses(business_id),
    agreement_type             agreement_type_enum NOT NULL,
    source_type                agreement_source_type_enum NOT NULL,
    content_url_or_text         TEXT NOT NULL,
    version                    INT NOT NULL,
    effective_date              DATE NOT NULL,
    created_at                 TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 1.7 agreement_acceptances — permanent audit of every acceptance
-- ---------------------------------------------------------------------------
CREATE TABLE agreement_acceptances (
    acceptance_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agreement_id      UUID NOT NULL REFERENCES business_agreements(agreement_id),
    person_id         BIGINT NOT NULL REFERENCES persons(person_id),
    otp_id            UUID NOT NULL REFERENCES otp_verifications(otp_id),
    accepted_at        TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 1.9 membership_requests — self-service join requests (CW-002, IW-002)
-- ---------------------------------------------------------------------------
CREATE TABLE membership_requests (
    request_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id                    BIGINT NOT NULL REFERENCES persons(person_id),
    business_id                   UUID NOT NULL REFERENCES businesses(business_id),
    requested_role                 membership_request_role_enum NOT NULL,
    proposed_investment_amount      DECIMAL(14,0) NULL,                    -- indicative only, IW-002; precision per Merged Addendum item 1
    remarks                        TEXT NULL,
    status                         membership_request_status_enum NOT NULL DEFAULT 'Pending',
    reviewed_by_person_id            BIGINT NULL REFERENCES persons(person_id),
    reviewed_at                     TIMESTAMP NULL,
    rejection_reason                TEXT NULL,
    cooldown_until                  TIMESTAMP NULL,                        -- 24-hour reapply rule
    created_at                      TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 1.10 account_periods — Business Date Engine (OW-013, locked)
-- ---------------------------------------------------------------------------
CREATE TABLE account_periods (
    account_period_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                  UUID NOT NULL REFERENCES businesses(business_id),
    operating_area_id             UUID NOT NULL REFERENCES operating_areas(operating_area_id),
    agent_membership_id           UUID NOT NULL REFERENCES business_members(membership_id), -- assigned agent
    business_start_date            TIMESTAMP NOT NULL,                     -- never changes
    planned_business_end_date       TIMESTAMP NOT NULL,                    -- system-calculated from account_cycle
    actual_end_date                 TIMESTAMP NULL,                        -- if closed early
    early_closure_reason            VARCHAR(255) NULL,                     -- mandatory if actual < planned (app-layer enforced)
    status                          account_period_status_enum NOT NULL DEFAULT 'Running',
    submitted_at                     TIMESTAMP NULL,
    approved_by_person_id             BIGINT NULL REFERENCES persons(person_id), -- Owner only
    approved_at                      TIMESTAMP NULL
);

CREATE INDEX idx_businesses_owner ON businesses(owner_person_id);
CREATE INDEX idx_operating_areas_business ON operating_areas(business_id);
CREATE INDEX idx_business_members_business ON business_members(business_id);
CREATE INDEX idx_business_members_person ON business_members(person_id);
CREATE INDEX idx_routes_business ON routes(business_id);
CREATE INDEX idx_route_locations_route ON route_locations(route_id);
CREATE INDEX idx_business_agreements_business ON business_agreements(business_id);
CREATE INDEX idx_agreement_acceptances_person ON agreement_acceptances(person_id);
CREATE INDEX idx_membership_requests_business ON membership_requests(business_id);
CREATE INDEX idx_membership_requests_person ON membership_requests(person_id);
CREATE INDEX idx_account_periods_business ON account_periods(business_id);

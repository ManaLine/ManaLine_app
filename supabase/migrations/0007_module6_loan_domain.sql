-- =============================================================================
-- MANA LINE — Module 6: Loan Domain
-- Source: 03_Database_Schema.md §6.1-6.7, plus Merged Addendum item 5
-- (loan_groups, loan_group_members)
-- REMOVED per §6.3 / 13_Rejected_Removed_Deferred_Register.md: loan_merges
-- table and the merged_into_loan_id column previously on loans no longer
-- exist — intentionally omitted below, not an oversight.
-- REMOVED per Register (Loan Renewal item): parent_loan_id column / renew
-- endpoint — also intentionally absent from loans.
-- =============================================================================

CREATE TYPE loan_status_enum AS ENUM ('Draft', 'Active', 'Grace Period', 'Penalty', 'Closed', 'Cancelled', 'Defaulted');
-- NOTE: 'Merged' and 'Renewed' are explicitly NOT in this ENUM — both features
-- were dropped entirely (§6.3 loan_merges REMOVED; Loan Renewal REMOVED per
-- 13_Rejected_Removed_Deferred_Register.md).
CREATE TYPE loan_schedule_status_enum AS ENUM ('Pending', 'Completed', 'Partial');
CREATE TYPE loan_request_status_enum AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE extension_requested_by_enum AS ENUM ('Customer', 'Agent');
CREATE TYPE extension_status_enum AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE penalty_option_enum AS ENUM ('Flat Amount', '% of Overdue Installment', '% of Remaining Balance');

-- ---------------------------------------------------------------------------
-- 6.1 loans
-- ---------------------------------------------------------------------------
CREATE TABLE loans (
    loan_id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_number                        VARCHAR(30) NOT NULL UNIQUE,        -- system-generated (OW-005)
    customer_id                        UUID NOT NULL REFERENCES customers(customer_id),
    business_id                        UUID NOT NULL REFERENCES businesses(business_id),
    template_id                        UUID NULL REFERENCES loan_templates(template_id),
    repayment_amount                    DECIMAL(14,0) NOT NULL,            -- total amount customer repays
    interest_amount                     DECIMAL(14,0) NOT NULL,            -- deducted upfront (BR-004/011)
    processing_fee                       DECIMAL(14,0) NOT NULL,           -- deducted upfront
    amount_given                        DECIMAL(14,0) GENERATED ALWAYS AS (repayment_amount - interest_amount - processing_fee) STORED, -- locked formula, read-only (BR-004/011, OW-007)
    repayment_type                      repayment_frequency_enum NOT NULL,
    duration_value                       INT NOT NULL,
    installment_amount                   DECIMAL(14,0) NOT NULL,
    grace_period_days                     INT NOT NULL,                    -- internal only, never shown to customer (BR-206)
    penalty_template_note                  TEXT NULL,                      -- optional pre-fill only; actual penalty via §6.7 (BR-236)
    remaining_balance                      DECIMAL(14,0) NOT NULL,         -- BR-235 unified running balance; init = repayment_amount
    collection_agent_membership_id           UUID NOT NULL REFERENCES business_members(membership_id),
    effective_date                          DATE NOT NULL,                 -- controls financial impact (OW-005 rule)
    loan_status                             loan_status_enum NOT NULL DEFAULT 'Draft',
    issue_business_date                      DATE NOT NULL,
    entry_timestamp                          TIMESTAMP NOT NULL DEFAULT now(),
    live_photo_url                            TEXT NOT NULL,               -- mandatory at creation (BR-036/081)
    closed_at                                 TIMESTAMP NULL,
    created_at                                TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                                TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE loans IS 'loan_status intentionally excludes Merged and Renewed — both features fully removed (see 13_Rejected_Removed_Deferred_Register.md). No merged_into_loan_id or parent_loan_id column exists.';
COMMENT ON COLUMN loans.amount_given IS 'GENERATED = repayment_amount - interest_amount - processing_fee; read-only, locked formula (BR-004/011, OW-007 "Owner Cannot Edit").';

-- Close the forward reference from Module 3 (guarantors.loan_id) and add its index.
ALTER TABLE guarantors
    ADD CONSTRAINT fk_guarantors_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id);

-- ---------------------------------------------------------------------------
-- 6.2 loan_schedule (Installments)
-- ---------------------------------------------------------------------------
CREATE TABLE loan_schedule (
    schedule_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                   UUID NOT NULL REFERENCES loans(loan_id),
    installment_number          INT NOT NULL,
    due_date                    DATE NOT NULL,
    installment_amount           DECIMAL(14,0) NOT NULL,
    status                       loan_schedule_status_enum NOT NULL DEFAULT 'Pending', -- advances only on full installment completion (BR-112)
    completed_at                  TIMESTAMP NULL
);

-- 6.3 loan_merges — INTENTIONALLY OMITTED.
-- REMOVED (locked decision): Merge Loans feature dropped entirely for
-- customers; OW-009 retired. This table and the merged_into_loan_id column
-- previously on `loans` no longer exist. See 03_Database_Schema.md §6.3 and
-- 13_Rejected_Removed_Deferred_Register.md ("Loan Renewal ... REMOVED").

-- ---------------------------------------------------------------------------
-- 6.4 loan_cancellations — only before cash handover, no financial impact
-- ---------------------------------------------------------------------------
CREATE TABLE loan_cancellations (
    cancellation_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                  UUID NOT NULL REFERENCES loans(loan_id),
    cancelled_by_person_id     BIGINT NOT NULL REFERENCES persons(person_id),
    reason                     TEXT NULL,
    cancelled_at                TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 6.5 loan_requests — customer self-service loan request (CW-003)
-- ---------------------------------------------------------------------------
CREATE TABLE loan_requests (
    request_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id                UUID NOT NULL REFERENCES customers(customer_id),
    template_id                 UUID NULL REFERENCES loan_templates(template_id),
    requested_amount              DECIMAL(14,0) NOT NULL,
    purpose_remark                 TEXT NULL,
    preferred_frequency             repayment_frequency_enum NULL,
    status                          loan_request_status_enum NOT NULL DEFAULT 'Pending',
    reviewed_by_person_id             BIGINT NULL REFERENCES persons(person_id),
    resulting_loan_id                  UUID NULL REFERENCES loans(loan_id), -- set on approval
    rejection_reason                    TEXT NULL,
    cooldown_until                      TIMESTAMP NULL,                   -- 24-hour reapply
    created_at                          TIMESTAMP NOT NULL DEFAULT now(),
    resolved_at                         TIMESTAMP NULL
);

-- ---------------------------------------------------------------------------
-- 6.6 extension_requests — grace-period extension requests (OW-006)
-- ---------------------------------------------------------------------------
CREATE TABLE extension_requests (
    extension_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                UUID NOT NULL REFERENCES loans(loan_id),
    requested_by             extension_requested_by_enum NOT NULL,
    status                   extension_status_enum NOT NULL DEFAULT 'Pending', -- Owner decision
    decided_by_person_id       BIGINT NULL REFERENCES persons(person_id),
    business_date              DATE NOT NULL
);

-- ---------------------------------------------------------------------------
-- 6.7 penalty_entries — manual post-grace penalty application (BR-236)
-- ---------------------------------------------------------------------------
CREATE TABLE penalty_entries (
    penalty_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                      UUID NOT NULL REFERENCES loans(loan_id),
    penalty_option                 penalty_option_enum NOT NULL,
    penalty_value                    DECIMAL(14,0) NOT NULL,             -- flat Rs or % as per option
    penalty_amount_applied             DECIMAL(14,0) NOT NULL,           -- resolved Rs amount added to remaining_balance
    applied_by_person_id                 BIGINT NOT NULL REFERENCES persons(person_id), -- Owner or Agent with can_apply_penalty
    business_date                        DATE NOT NULL,
    entry_timestamp                        TIMESTAMP NOT NULL DEFAULT now(),
    is_waived_or_reduced                    BOOLEAN NOT NULL DEFAULT FALSE -- affects Line Score Recovery Bonus eligibility (BR-215)
);

-- ---------------------------------------------------------------------------
-- Merged Addendum item 5 — Group Loans (NEW). Individual liability
-- throughout; Group Balance/EMI are computed aggregates at read time, not
-- stored. One member's Penalty/Default status has zero effect on others.
-- ---------------------------------------------------------------------------
CREATE TABLE loan_groups (
    group_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                  UUID NOT NULL REFERENCES businesses(business_id),
    group_name                    VARCHAR(100) NOT NULL,
    created_by_membership_id        UUID NOT NULL REFERENCES business_members(membership_id), -- Owner or Agent
    created_at                     TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE loan_group_members (
    group_member_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id                UUID NOT NULL REFERENCES loan_groups(group_id),
    loan_id                  UUID NOT NULL REFERENCES loans(loan_id),     -- loan already exists individually before grouping
    added_at                  TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE loan_group_members IS 'businesses.allow_multi_group_membership (Module 1) governs whether a loan_id may appear in more than one group_id — app-layer enforced, not a DB uniqueness constraint, since the toggle is per-business and can change over time.';

CREATE INDEX idx_loans_customer ON loans(customer_id);
CREATE INDEX idx_loans_business ON loans(business_id);
CREATE INDEX idx_loans_agent ON loans(collection_agent_membership_id);
CREATE INDEX idx_loan_schedule_loan ON loan_schedule(loan_id);
CREATE INDEX idx_loan_cancellations_loan ON loan_cancellations(loan_id);
CREATE INDEX idx_loan_requests_customer ON loan_requests(customer_id);
CREATE INDEX idx_extension_requests_loan ON extension_requests(loan_id);
CREATE INDEX idx_penalty_entries_loan ON penalty_entries(loan_id);
CREATE INDEX idx_loan_groups_business ON loan_groups(business_id);
CREATE INDEX idx_loan_group_members_group ON loan_group_members(group_id);
CREATE INDEX idx_loan_group_members_loan ON loan_group_members(loan_id);

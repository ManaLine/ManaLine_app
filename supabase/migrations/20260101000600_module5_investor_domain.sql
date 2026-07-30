-- =============================================================================
-- MANA LINE — Module 5: Investor Domain
-- Source: 03_Database_Schema.md §5.1-5.6, plus Merged Addendum item 2
-- (investment_withdrawals principal/interest split columns)
-- =============================================================================

CREATE TYPE investment_interest_type_enum AS ENUM ('Simple', 'Yearly Compound');
CREATE TYPE investment_status_enum AS ENUM ('Active', 'Closed');
CREATE TYPE interest_ledger_entry_type_enum AS ENUM ('Accrual Snapshot', 'Payment', 'Compounding Event');
CREATE TYPE withdrawal_type_enum AS ENUM ('Interest Only', 'Principal Partial', 'Principal Full', 'Principal + Interest');
CREATE TYPE withdrawal_request_status_enum AS ENUM ('Pending', 'Approved-Paid', 'Rejected');
CREATE TYPE distribution_recipient_type_enum AS ENUM ('Agent', 'Investor');
CREATE TYPE distribution_status_enum AS ENUM ('Declared', 'Paid');

-- ---------------------------------------------------------------------------
-- 5.1 investors — FK 1:1 into business_members (role=Investor)
-- ---------------------------------------------------------------------------
CREATE TABLE investors (
    investor_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id       UUID NOT NULL UNIQUE REFERENCES business_members(membership_id),
    person_id           BIGINT NOT NULL REFERENCES persons(person_id)
);

-- ---------------------------------------------------------------------------
-- 5.2 investments — each investment fully independent (BR-029/030)
-- remaining_balance is a SINGLE combined figure (Principal + accrued
-- Interest) per Merged Addendum item 2; balance = 0 -> auto Closed
-- (application-layer trigger, not enforced here).
-- ---------------------------------------------------------------------------
CREATE TABLE investments (
    investment_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    investor_id                    UUID NOT NULL REFERENCES investors(investor_id),
    business_id                    UUID NOT NULL REFERENCES businesses(business_id),
    principal_amount                 DECIMAL(14,0) NOT NULL,             -- current principal, changes only via withdrawal (BR-170) or compounding
    original_principal_amount          DECIMAL(14,0) NOT NULL,           -- frozen at creation, Agreement Snapshot (BR-034)
    roi_rate                         DECIMAL(10,4) NOT NULL,             -- Rs per Rs100 per month (BR-233); rate field, not swept into whole-rupee precision change
    interest_type                     investment_interest_type_enum NOT NULL, -- fixed at creation, frozen (BR-034)
    profit_share_percent                DECIMAL(5,2) NULL,               -- optional, independent of ROI
    profit_share_effective_date          DATE NULL,
    effective_date                      DATE NOT NULL,
    status                              investment_status_enum NOT NULL DEFAULT 'Active',
    nominee_person_id                    BIGINT NULL REFERENCES persons(person_id), -- ownership transfer target (BR-171)
    last_interest_payment_date             DATE NULL,                    -- interest accrues from later of effective_date/this (BR-051, BR-234)
    last_compounding_date                  DATE NULL,                    -- Yearly Compound only
    remarks                                TEXT NULL,
    created_at                             TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON COLUMN investments.principal_amount IS 'Per Merged Addendum item 2, this is now the single combined Principal+Interest running balance in practice for withdrawal purposes; original schema note retained. Balance reaching 0 auto-closes the investment (app-layer).';

-- ---------------------------------------------------------------------------
-- 5.3 investment_interest_ledger — every interest calculation/payment event
-- ---------------------------------------------------------------------------
CREATE TABLE investment_interest_ledger (
    interest_ledger_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    investment_id             UUID NOT NULL REFERENCES investments(investment_id),
    entry_type                 interest_ledger_entry_type_enum NOT NULL,
    amount                     DECIMAL(14,0) NOT NULL,
    business_date               DATE NOT NULL,
    entry_timestamp              TIMESTAMP NOT NULL DEFAULT now(),
    owner_verified                BOOLEAN NOT NULL DEFAULT FALSE,        -- BR-055
    remarks                       TEXT NULL
);

-- ---------------------------------------------------------------------------
-- 5.4 investment_withdrawals — with Merged Addendum item 2 split columns
-- ---------------------------------------------------------------------------
CREATE TABLE investment_withdrawals (
    withdrawal_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    investment_id                UUID NOT NULL REFERENCES investments(investment_id),
    withdrawal_type                withdrawal_type_enum NOT NULL,
    amount                         DECIMAL(14,0) NOT NULL,
    principal_portion               DECIMAL(14,0) NOT NULL,              -- Merged Addendum item 2 — Owner-entered at approval time
    interest_portion                DECIMAL(14,0) NOT NULL,              -- Merged Addendum item 2 — Owner-entered at approval time
    business_date                   DATE NOT NULL,
    entry_timestamp                  TIMESTAMP NOT NULL DEFAULT now(),
    approved_by_person_id              BIGINT NOT NULL REFERENCES persons(person_id), -- Owner
    remarks                            TEXT NULL,
    CONSTRAINT chk_investment_withdrawals_split_sums CHECK (principal_portion + interest_portion = amount)
);
COMMENT ON TABLE investment_withdrawals IS 'principal_portion/interest_portion added per Merged Addendum item 2. Owner manually allocates the split on OW-003 approval; no automatic waterfall — enforced additively via CHECK, values themselves are app-entered.';

-- ---------------------------------------------------------------------------
-- 5.5 investment_withdrawal_requests — self-service request layer (IW-004)
-- ---------------------------------------------------------------------------
CREATE TABLE investment_withdrawal_requests (
    request_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    investment_id                UUID NOT NULL REFERENCES investments(investment_id),
    requested_by_person_id         BIGINT NOT NULL REFERENCES persons(person_id),
    withdrawal_type                withdrawal_type_enum NOT NULL,
    requested_amount                DECIMAL(14,0) NOT NULL,
    remarks                         TEXT NULL,
    status                          withdrawal_request_status_enum NOT NULL DEFAULT 'Pending',
    resulting_withdrawal_id           UUID NULL REFERENCES investment_withdrawals(withdrawal_id), -- set once Owner pays out & confirms
    rejection_reason                  TEXT NULL,
    created_at                        TIMESTAMP NOT NULL DEFAULT now(),
    resolved_at                       TIMESTAMP NULL
);

-- ---------------------------------------------------------------------------
-- 5.6a distribution_declarations (replaces original distribution_ledger,
-- per Amendment 1 / Rule #058: Declare != Pay)
-- ---------------------------------------------------------------------------
CREATE TABLE distribution_declarations (
    declaration_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                 UUID NOT NULL REFERENCES businesses(business_id),
    recipient_type               distribution_recipient_type_enum NOT NULL,
    agent_id                    UUID NULL,                               -- FK -> agents, added in 0011 (Module 4, already exists by now — added here for consistency of pattern with true forward refs; can be direct)
    investment_id                 UUID NULL REFERENCES investments(investment_id),
    profit_share_percent            DECIMAL(5,2) NOT NULL,                -- snapshot of agreed % at declaration time
    total_profit_amount              DECIMAL(14,0) NOT NULL,
    declared_amount                  DECIMAL(14,0) NOT NULL,              -- recipient's share; system pre-computed, Owner-overridable (BR-232)
    business_date                     DATE NOT NULL,
    status                             distribution_status_enum NOT NULL DEFAULT 'Declared',
    remarks                            TEXT NULL,
    created_at                         TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_distribution_declarations_recipient CHECK (
        (recipient_type = 'Agent' AND agent_id IS NOT NULL AND investment_id IS NULL) OR
        (recipient_type = 'Investor' AND investment_id IS NOT NULL AND agent_id IS NULL)
    )
);
COMMENT ON COLUMN distribution_declarations.agent_id IS 'References agents(agent_id) — agents table already exists (Module 4, migration 0005), so this FK is added directly rather than deferred to 0011.';

ALTER TABLE distribution_declarations
    ADD CONSTRAINT fk_distribution_declarations_agent FOREIGN KEY (agent_id) REFERENCES agents(agent_id);

-- ---------------------------------------------------------------------------
-- 5.6b distribution_payments
-- ---------------------------------------------------------------------------
CREATE TABLE distribution_payments (
    payment_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    declaration_id                UUID NOT NULL REFERENCES distribution_declarations(declaration_id),
    paid_amount                    DECIMAL(14,0) NOT NULL,               -- full settlement only in V1 — one Payment per Declaration
    interest_amount                 DECIMAL(14,0) NOT NULL DEFAULT 0,    -- manually entered by Owner, never system-computed (Rule #059)
    business_date                    DATE NOT NULL,
    entry_timestamp                   TIMESTAMP NOT NULL DEFAULT now(),
    approved_by_person_id               BIGINT NOT NULL REFERENCES persons(person_id), -- Owner
    remarks                             TEXT NULL,
    CONSTRAINT uq_distribution_payments_one_per_declaration UNIQUE (declaration_id)
);
COMMENT ON CONSTRAINT uq_distribution_payments_one_per_declaration ON distribution_payments IS 'Enforces "one Payment per Declaration, full settlement only in V1" from the schema doc.';

CREATE INDEX idx_investments_investor ON investments(investor_id);
CREATE INDEX idx_investments_business ON investments(business_id);
CREATE INDEX idx_investment_interest_ledger_investment ON investment_interest_ledger(investment_id);
CREATE INDEX idx_investment_withdrawals_investment ON investment_withdrawals(investment_id);
CREATE INDEX idx_investment_withdrawal_requests_investment ON investment_withdrawal_requests(investment_id);
CREATE INDEX idx_distribution_declarations_business ON distribution_declarations(business_id);
CREATE INDEX idx_distribution_payments_declaration ON distribution_payments(declaration_id);

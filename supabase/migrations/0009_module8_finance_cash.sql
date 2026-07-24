-- =============================================================================
-- MANA LINE — Module 8: Finance / Cash / Day Closure
-- Source: 03_Database_Schema.md §8.1-8.7, plus Merged Addendum item 9
-- (account_settlements.return_reason)
-- =============================================================================

CREATE TYPE expense_category_enum AS ENUM ('General', 'Travel', 'Salary', 'Fuel', 'External Chit', 'Other');
CREATE TYPE day_ledger_status_enum AS ENUM ('Open', 'Closed');
CREATE TYPE settlement_cycle_type_enum AS ENUM ('Daily', 'Weekly', 'Monthly');
CREATE TYPE settlement_status_enum AS ENUM ('Pending Owner Review', 'Approved', 'Returned');
CREATE TYPE adjustment_type_enum AS ENUM ('Short', 'Excess');
CREATE TYPE adjustment_applied_to_enum AS ENUM ('Agent Salary Deduction', 'Customer Pending Settlement', 'Excess Ledger-Unresolved');
CREATE TYPE salary_ledger_status_enum AS ENUM ('Pending', 'Paid');

-- ---------------------------------------------------------------------------
-- 8.1 expenses
-- ---------------------------------------------------------------------------
CREATE TABLE expenses (
    expense_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                 UUID NOT NULL REFERENCES businesses(business_id),
    category                     expense_category_enum NOT NULL,        -- external chits recorded as expense only (BR-061)
    amount                        DECIMAL(14,0) NOT NULL,
    recorded_by_membership_id       UUID NOT NULL REFERENCES business_members(membership_id),
    business_date                    DATE NOT NULL,
    entry_timestamp                   TIMESTAMP NOT NULL DEFAULT now(),
    remarks                            TEXT NULL
);

-- ---------------------------------------------------------------------------
-- 8.2 day_ledger (Daily Record Book) — one row per business day per business
-- ---------------------------------------------------------------------------
CREATE TABLE day_ledger (
    ledger_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                  UUID NOT NULL REFERENCES businesses(business_id),
    business_date                 DATE NOT NULL,
    opening_balance                 DECIMAL(14,0) NOT NULL,             -- BF Cash
    total_collections                DECIMAL(14,0) NOT NULL,
    total_loan_distribution            DECIMAL(14,0) NOT NULL,
    investor_deposits                  DECIMAL(14,0) NOT NULL,
    investor_withdrawals                 DECIMAL(14,0) NOT NULL,
    total_expenses                        DECIMAL(14,0) NOT NULL,
    short_amount                           DECIMAL(14,0) NOT NULL DEFAULT 0,
    excess_amount                           DECIMAL(14,0) NOT NULL DEFAULT 0,
    closing_balance                          DECIMAL(14,0) NOT NULL,
    status                                    day_ledger_status_enum NOT NULL DEFAULT 'Open',
    remarks                                    TEXT NULL,               -- optional (BR-097)
    CONSTRAINT uq_day_ledger_business_date UNIQUE (business_id, business_date)
);

-- ---------------------------------------------------------------------------
-- 8.3 day_closures
-- ---------------------------------------------------------------------------
CREATE TABLE day_closures (
    closure_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id               UUID NOT NULL REFERENCES businesses(business_id),
    business_date              DATE NOT NULL,
    physical_cash                DECIMAL(14,0) NOT NULL,
    upi_balance                   DECIMAL(14,0) NOT NULL,
    bank_balance                   DECIMAL(14,0) NOT NULL,
    cheque_balance                  DECIMAL(14,0) NOT NULL,
    expected_cash                    DECIMAL(14,0) NOT NULL,
    expected_upi                       DECIMAL(14,0) NOT NULL,
    expected_bank                        DECIMAL(14,0) NOT NULL,
    expected_cheque                        DECIMAL(14,0) NOT NULL,
    difference                              DECIMAL(14,0) NOT NULL,     -- must = 0 to close (BR-043/219)
    closed_by_person_id                       BIGINT NOT NULL REFERENCES persons(person_id), -- Owner only
    closed_at                                  TIMESTAMP NOT NULL DEFAULT now(),
    reopened_at                                 TIMESTAMP NULL,         -- Owner-only (BR-221); triggers recalculation
    reopen_reason                                TEXT NULL
);

-- ---------------------------------------------------------------------------
-- 8.4 account_settlements — agent daily/weekly/monthly settlement to Owner
-- (AG-006), with Merged Addendum item 9 return_reason column
-- ---------------------------------------------------------------------------
CREATE TABLE account_settlements (
    settlement_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_period_id               UUID NOT NULL REFERENCES account_periods(account_period_id),
    agent_id                          UUID NOT NULL REFERENCES agents(agent_id),
    cycle_type                          settlement_cycle_type_enum NOT NULL,
    opening_balance                       DECIMAL(14,0) NOT NULL,
    cash_collected                          DECIMAL(14,0) NOT NULL,
    upi_collected                             DECIMAL(14,0) NOT NULL,
    bank_collected                              DECIMAL(14,0) NOT NULL,
    cheque_collected                              DECIMAL(14,0) NOT NULL, -- amount only; no separate Cheque Count field (per Register addendum, dropped)
    loan_distribution                               DECIMAL(14,0) NOT NULL,
    expenses                                          DECIMAL(14,0) NOT NULL,
    expected_closing_balance                            DECIMAL(14,0) NOT NULL, -- per BR-237 formula
    physical_cash_declared                                DECIMAL(14,0) NOT NULL,
    difference                                              DECIMAL(14,0) NOT NULL,
    status                                                    settlement_status_enum NOT NULL DEFAULT 'Pending Owner Review', -- single 'sent back' status ('Returned'); no separate 'Reject' action (per Register addendum, consolidated)
    return_reason                                              TEXT NULL, -- Merged Addendum item 9 — required whenever status transitions to 'Returned'
    submitted_at                                                 TIMESTAMP NOT NULL DEFAULT now(),
    reviewed_by_person_id                                          BIGINT NULL REFERENCES persons(person_id),
    reviewed_at                                                     TIMESTAMP NULL,
    CONSTRAINT chk_account_settlements_return_reason CHECK (status <> 'Returned' OR return_reason IS NOT NULL)
);
COMMENT ON COLUMN account_settlements.return_reason IS 'Merged Addendum item 9. NULL for all statuses except Returned, where it is mandatory (enforced by CHECK).';

-- ---------------------------------------------------------------------------
-- 8.5 settlement_adjustments — Short/Excess register (BR-045/066/069/070)
-- ---------------------------------------------------------------------------
CREATE TABLE settlement_adjustments (
    adjustment_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_id               UUID NULL REFERENCES account_settlements(settlement_id),
    agent_id                      UUID NULL REFERENCES agents(agent_id), -- short belongs to individual agent ledger
    adjustment_type                 adjustment_type_enum NOT NULL,
    amount                            DECIMAL(14,0) NOT NULL,
    applied_to                          adjustment_applied_to_enum NOT NULL, -- Owner-controlled, never automatic (BR-069)
    target_customer_id                    UUID NULL REFERENCES customers(customer_id), -- if applied as customer settlement
    resolved                                BOOLEAN NOT NULL DEFAULT FALSE,
    business_date                             DATE NOT NULL
);

-- ---------------------------------------------------------------------------
-- 8.6 agent_salary_ledger
-- ---------------------------------------------------------------------------
CREATE TABLE agent_salary_ledger (
    salary_ledger_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id                    UUID NOT NULL REFERENCES agents(agent_id),
    pay_cycle_start                DATE NOT NULL,
    pay_cycle_end                    DATE NOT NULL,
    fixed_salary                       DECIMAL(14,0) NOT NULL,
    adjustments                          DECIMAL(14,0) NOT NULL DEFAULT 0,
    advances_deducted                      DECIMAL(14,0) NOT NULL DEFAULT 0,
    shorts_deducted                          DECIMAL(14,0) NOT NULL DEFAULT 0,
    payable_salary                             DECIMAL(14,0) GENERATED ALWAYS AS (fixed_salary + adjustments - advances_deducted - shorts_deducted) STORED, -- per BR-068/237 formula
    status                                       salary_ledger_status_enum NOT NULL DEFAULT 'Pending', -- stays unpaid until Owner pays (BR-071)
    paid_at                                       TIMESTAMP NULL
);
COMMENT ON COLUMN agent_salary_ledger.payable_salary IS 'GENERATED per BR-068/237 formula: fixed_salary + adjustments - advances_deducted - shorts_deducted. Flagged for the verification/calc-engine chats to confirm this matches the exact 15_Calculation_Engine.md formula before relying on it.';

-- ---------------------------------------------------------------------------
-- 8.7 salary_advances
-- ---------------------------------------------------------------------------
CREATE TABLE salary_advances (
    advance_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id                UUID NOT NULL REFERENCES agents(agent_id),
    amount                     DECIMAL(14,0) NOT NULL,
    business_date               DATE NOT NULL,
    remarks                       TEXT NULL
);

CREATE INDEX idx_expenses_business ON expenses(business_id);
CREATE INDEX idx_day_ledger_business ON day_ledger(business_id);
CREATE INDEX idx_day_closures_business ON day_closures(business_id);
CREATE INDEX idx_account_settlements_period ON account_settlements(account_period_id);
CREATE INDEX idx_account_settlements_agent ON account_settlements(agent_id);
CREATE INDEX idx_settlement_adjustments_settlement ON settlement_adjustments(settlement_id);
CREATE INDEX idx_settlement_adjustments_agent ON settlement_adjustments(agent_id);
CREATE INDEX idx_agent_salary_ledger_agent ON agent_salary_ledger(agent_id);
CREATE INDEX idx_salary_advances_agent ON salary_advances(agent_id);

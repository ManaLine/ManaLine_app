-- =============================================================================
-- MANA LINE — Module 2: Loan Templates & Configuration
-- Source: 03_Database_Schema.md §2.1
-- =============================================================================

CREATE TYPE loan_template_status_enum AS ENUM ('Active', 'Inactive');
CREATE TYPE repayment_frequency_enum AS ENUM ('Daily', 'Weekly', 'Monthly');

-- ---------------------------------------------------------------------------
-- 2.1 loan_templates
-- ---------------------------------------------------------------------------
CREATE TABLE loan_templates (
    template_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                    UUID NOT NULL REFERENCES businesses(business_id),
    template_name                  VARCHAR(150) NOT NULL,
    status                         loan_template_status_enum NOT NULL DEFAULT 'Active',
    default_amount                  DECIMAL(14,0) NOT NULL,               -- precision per Merged Addendum item 1 (whole rupees, round-up)
    repayment_frequency              repayment_frequency_enum NOT NULL,
    duration_value                   INT NOT NULL,
    default_roi_or_interest           DECIMAL(10,2) NOT NULL,             -- rate field, not a currency amount — retained at (10,2) per doc, not swept into the amount-column precision change
    default_processing_fee             DECIMAL(14,0) NOT NULL,
    default_grace_period_days          INT NOT NULL,
    agent_permission_overrides           JSON NULL,                       -- template-specific permissions (BR-143)
    effective_date                      DATE NOT NULL,                    -- prospective changes only (BR-144)
    usage_count                         INT NOT NULL DEFAULT 0,           -- BR-145
    remarks                             TEXT NULL,
    is_locked                           BOOLEAN NOT NULL DEFAULT FALSE    -- immutable once used; delete blocked if in use (BR-146, app-layer)
);

CREATE INDEX idx_loan_templates_business ON loan_templates(business_id);

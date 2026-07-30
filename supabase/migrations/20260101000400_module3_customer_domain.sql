-- =============================================================================
-- MANA LINE — Module 3: Customer Domain
-- Source: 03_Database_Schema.md §3.1-3.4
-- FORWARD REFERENCE NOTE: guarantors.loan_id references loans, which is
-- defined in Module 6 (0007). Per the dependency-order convention, the
-- column is created here without the FK constraint; the constraint itself
-- is added in 0011_indexes_and_constraints.sql once loans exists.
-- =============================================================================

CREATE TYPE occupation_enum AS ENUM ('Farmer', 'Milk Vendor', 'Auto Driver', 'Tea Shop', 'Tailor', 'Daily Wage', 'Government Employee', 'Private Employee', 'Business', 'Housewife', 'Student', 'Retired', 'Other-Custom');
CREATE TYPE customer_status_enum AS ENUM ('Active', 'Inactive', 'Deceased');
CREATE TYPE guarantor_status_enum AS ENUM ('Active', 'Removed');
CREATE TYPE remark_priority_enum AS ENUM ('Normal', 'High');
CREATE TYPE customer_document_type_enum AS ENUM ('Aadhaar', 'Photo', 'Address Proof', 'Customer Agreement', 'Loan Agreement', 'Guarantor Document', 'Other');

-- ---------------------------------------------------------------------------
-- 3.1 customers — business-scoped customer profile, 1:1 into business_members
-- No is_blacklisted column exists anywhere (BR-227). No local sequential
-- customer number — identified solely by MLID (BR-223).
-- ---------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id                     UUID NOT NULL UNIQUE REFERENCES business_members(membership_id),
    person_id                         BIGINT NOT NULL REFERENCES persons(person_id), -- denormalized for join speed
    assigned_agent_membership_id        UUID NULL REFERENCES business_members(membership_id), -- current agent
    occupation                         occupation_enum NOT NULL,          -- mandatory category (BR-230)
    occupation_other_text                VARCHAR(150) NULL,               -- when Other-Custom
    customer_status                     customer_status_enum NOT NULL DEFAULT 'Active', -- BR-231
    customer_since                      DATE NOT NULL,
    default_max_active_loans              INT NULL,                       -- overrides company default (BR-166)
    created_at                          TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE customers IS 'No is_blacklisted column exists anywhere (BR-227). No local sequential customer number — identified solely by MLID (BR-223).';

-- ---------------------------------------------------------------------------
-- 3.2 guarantors — belongs to the loan, never the customer identity
-- (OW-005 rule, BR-207). loan_id FK added in 0011 (forward reference).
-- ---------------------------------------------------------------------------
CREATE TABLE guarantors (
    guarantor_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                 UUID NOT NULL,                                -- FK -> loans, added in 0011 (Module 6 forward reference)
    guarantor_person_id       BIGINT NULL REFERENCES persons(person_id),  -- if linked to existing MLID
    guarantor_name            VARCHAR(150) NOT NULL,                      -- free text if not linked
    relationship               VARCHAR(100) NOT NULL,
    phone                      VARCHAR(15) NOT NULL,
    address                    TEXT NOT NULL,
    remarks                    TEXT NULL,
    status                     guarantor_status_enum NOT NULL DEFAULT 'Active',
    created_at                 TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 3.3 customer_remarks — append-only, never edited
-- ---------------------------------------------------------------------------
CREATE TABLE customer_remarks (
    remark_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             UUID NOT NULL REFERENCES customers(customer_id),
    entered_by_person_id      BIGINT NOT NULL REFERENCES persons(person_id),
    remark_text              TEXT NOT NULL,
    priority                 remark_priority_enum NOT NULL DEFAULT 'Normal',
    business_date             DATE NOT NULL,
    created_at                TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 3.4 customer_documents
-- ---------------------------------------------------------------------------
CREATE TABLE customer_documents (
    document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id       UUID NOT NULL REFERENCES customers(customer_id),
    document_type      customer_document_type_enum NOT NULL,
    file_url            TEXT NOT NULL,
    is_archived          BOOLEAN NOT NULL DEFAULT FALSE,                  -- never deleted (BR pattern)
    uploaded_at           TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_customers_membership ON customers(membership_id);
CREATE INDEX idx_customers_person ON customers(person_id);
CREATE INDEX idx_customers_agent ON customers(assigned_agent_membership_id);
CREATE INDEX idx_guarantors_loan ON guarantors(loan_id);
CREATE INDEX idx_customer_remarks_customer ON customer_remarks(customer_id);
CREATE INDEX idx_customer_documents_customer ON customer_documents(customer_id);

-- =============================================================================
-- MANA LINE — Module 7: Collection Domain
-- Source: 03_Database_Schema.md §7.1-7.5
-- =============================================================================

CREATE TYPE payer_type_enum AS ENUM ('Customer', 'Guarantor');
CREATE TYPE collection_result_type_enum AS ENUM ('Full', 'Partial', 'Excess', 'No Collection');
CREATE TYPE excess_disposition_enum AS ENUM ('Advance', 'Refund', 'Next Installment');
CREATE TYPE payment_mode_enum AS ENUM ('Cash', 'UPI', 'Bank Transfer', 'Cheque');
CREATE TYPE no_collection_reason_enum AS ENUM ('Customer Not Home', 'House Locked', 'Customer Out Of Village', 'Requested Extension', 'Medical Emergency', 'Festival', 'Natural Disaster', 'Phone Call Not Answered', 'Shifted Village', 'Refused Payment', 'Other');
CREATE TYPE draft_type_enum AS ENUM ('Collection', 'Loan Distribution', 'Customer Remark', 'Document Upload');
CREATE TYPE draft_status_enum AS ENUM ('Draft', 'Submitted', 'Discarded');
CREATE TYPE online_payment_status_enum AS ENUM ('Submitted', 'Confirmed', 'Not Received-Disputed');

-- ---------------------------------------------------------------------------
-- 7.1 collections
-- ---------------------------------------------------------------------------
CREATE TABLE collections (
    collection_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                       UUID NOT NULL REFERENCES loans(loan_id),
    customer_id                   UUID NOT NULL REFERENCES customers(customer_id),
    receipt_number                  VARCHAR(30) NOT NULL UNIQUE,
    collected_amount                 DECIMAL(14,0) NOT NULL,
    payer_type                       payer_type_enum NOT NULL,
    guarantor_id                       UUID NULL REFERENCES guarantors(guarantor_id), -- when payer_type=Guarantor
    collected_by_membership_id           UUID NOT NULL REFERENCES business_members(membership_id), -- BR-117/118
    business_date                        DATE NOT NULL,
    entry_timestamp                       TIMESTAMP NOT NULL DEFAULT now(),
    optional_payment_time                  TIME NULL,
    result_type                            collection_result_type_enum NOT NULL,
    difference_amount                       DECIMAL(14,0) NOT NULL DEFAULT 0, -- shortfall/excess vs installment_amount
    excess_disposition                       excess_disposition_enum NULL,   -- Owner-decided, never system-assumed
    remarks                                  TEXT NULL,
    created_at                               TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 7.2 collection_payment_splits — mixed payment support (BR-023/025)
-- ---------------------------------------------------------------------------
CREATE TABLE collection_payment_splits (
    split_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id         UUID NOT NULL REFERENCES collections(collection_id),
    payment_mode            payment_mode_enum NOT NULL,
    amount                    DECIMAL(14,0) NOT NULL
);
COMMENT ON TABLE collection_payment_splits IS 'Doc-specified invariant: SUM(amount) per collection_id must equal collections.collected_amount. Not expressible as a plain CHECK (requires cross-row aggregation) — implement via trigger or application-layer validation; flagged for the verification chat.';

-- ---------------------------------------------------------------------------
-- 7.3 no_collection_visits — visit without payment (OW-006/AG-002/AG-003)
-- ---------------------------------------------------------------------------
CREATE TABLE no_collection_visits (
    visit_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                       UUID NULL REFERENCES loans(loan_id),
    customer_id                   UUID NOT NULL REFERENCES customers(customer_id),
    visited_by_membership_id        UUID NOT NULL REFERENCES business_members(membership_id),
    reason                          no_collection_reason_enum NOT NULL,
    business_date                    DATE NOT NULL,
    entry_timestamp                   TIMESTAMP NOT NULL DEFAULT now()   -- no financial entry created
);

-- ---------------------------------------------------------------------------
-- 7.4 collection_drafts — prevents data loss (BR-026/174)
-- ---------------------------------------------------------------------------
CREATE TABLE collection_drafts (
    draft_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_type                   draft_type_enum NOT NULL,
    created_by_membership_id       UUID NOT NULL REFERENCES business_members(membership_id),
    payload_json                    JSON NOT NULL,                      -- partial entry data; flexible across all draft types (see OPEN ITEM 2 in source doc, confirmed acceptable)
    loan_id                          UUID NULL REFERENCES loans(loan_id),
    status                            draft_status_enum NOT NULL DEFAULT 'Draft',
    created_at                        TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                        TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE collection_drafts IS 'draft_type=Loan Distribution is also reused by the BF-Cash-Low auto-save-as-Draft flow (Merged Addendum item 4) — no schema change needed for that, per the doc.';

-- ---------------------------------------------------------------------------
-- 7.5 customer_online_payments — customer self-service UPI payment (CW-005)
-- ---------------------------------------------------------------------------
CREATE TABLE customer_online_payments (
    online_payment_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                       UUID NOT NULL REFERENCES loans(loan_id), -- mandatory, no free entry
    customer_id                   UUID NOT NULL REFERENCES customers(customer_id),
    amount                          DECIMAL(14,0) NOT NULL,
    status                          online_payment_status_enum NOT NULL DEFAULT 'Submitted',
    confirmed_by_person_id            BIGINT NULL REFERENCES persons(person_id), -- Owner/Agent
    resulting_collection_id             UUID NULL REFERENCES collections(collection_id), -- set on confirmation (payment_mode=UPI)
    submitted_at                        TIMESTAMP NOT NULL DEFAULT now(),
    confirmed_at                        TIMESTAMP NULL
);

CREATE INDEX idx_collections_loan ON collections(loan_id);
CREATE INDEX idx_collections_customer ON collections(customer_id);
CREATE INDEX idx_collection_payment_splits_collection ON collection_payment_splits(collection_id);
CREATE INDEX idx_no_collection_visits_loan ON no_collection_visits(loan_id);
CREATE INDEX idx_no_collection_visits_customer ON no_collection_visits(customer_id);
CREATE INDEX idx_collection_drafts_creator ON collection_drafts(created_by_membership_id);
CREATE INDEX idx_customer_online_payments_loan ON customer_online_payments(loan_id);

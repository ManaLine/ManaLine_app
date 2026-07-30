-- =============================================================================
-- MANA LINE — Module 0: Identity Network (Global, Cross-Business)
-- Source: 03_Database_Schema.md §0.1–0.7 (Confirmed, Merged Edition 2026-07-19)
-- No RLS in this migration. No hard deletes anywhere (BR-002/BR-127 pattern).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- ENUM TYPES — Module 0
-- ---------------------------------------------------------------------------
CREATE TYPE mlid_type_enum AS ENUM ('MLPI', 'MLTI');
CREATE TYPE verification_ring_enum AS ENUM ('GREEN', 'RED');
CREATE TYPE profile_status_enum AS ENUM ('Complete', 'Incomplete', 'Pending Verification', 'Archived');
CREATE TYPE registration_source_enum AS ENUM ('Owner', 'Agent', 'Migration', 'System');
CREATE TYPE customer_type_enum AS ENUM ('New', 'Migrated');
CREATE TYPE otp_purpose_enum AS ENUM ('Registration', 'Role Escalation', 'Password Reset', 'PIN Reset', 'Account Unlock', 'Agreement Acceptance');
CREATE TYPE otp_status_enum AS ENUM ('Sent', 'Verified', 'Expired');
CREATE TYPE identity_document_type_enum AS ENUM ('Aadhaar', 'Photo', 'Address Proof', 'Other');
CREATE TYPE duplicate_detection_method_enum AS ENUM ('System-Automatic', 'Owner-Manual');
CREATE TYPE duplicate_suspect_status_enum AS ENUM ('Open', 'Resolved-Merged', 'Resolved-Not Duplicate');

-- ---------------------------------------------------------------------------
-- 0.1 persons — one row per human being, forever (BR-178, BR-160, BR-161)
-- NOTE: person_id is the immutable identity key referenced by every other
-- module. Never reference a person via mlid (mlid can be reassigned per
-- BR-184 MLTI->MLPI upgrade, and corrected per BR-239 Aadhaar correction).
-- No Blacklist field anywhere on this table (BR-227, explicitly forbidden).
-- ---------------------------------------------------------------------------
CREATE TABLE persons (
    person_id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mlid                       VARCHAR(13) NOT NULL UNIQUE,              -- BR-181/182
    mlid_type                  mlid_type_enum NOT NULL,
    gender_digit                CHAR(1) NOT NULL CHECK (gender_digit IN ('0','1')), -- 0=Female,1=Male
    full_name                  VARCHAR(150) NOT NULL,                     -- no nickname field, BR-224
    father_husband_name        VARCHAR(150) NOT NULL,
    dob                        DATE NULL,
    aadhaar_number              VARCHAR(12) NULL UNIQUE,                  -- stored encrypted at app layer
    mobile_number               VARCHAR(15) NULL,                         -- nullable, BR-192/OW-015
    password_hash               VARCHAR(255) NULL,
    pin_hash                    VARCHAR(255) NULL,
    biometric_enabled           BOOLEAN NOT NULL DEFAULT FALSE,           -- BR-196
    profile_photo_url           TEXT NULL,
    verification_ring           verification_ring_enum NOT NULL DEFAULT 'RED', -- BR-188/189
    profile_status               profile_status_enum NULL,                 -- BR-231
    is_deceased                 BOOLEAN NOT NULL DEFAULT FALSE,           -- BR-226, boolean only
    registration_source          registration_source_enum NULL,            -- BR-229
    customer_type                customer_type_enum NULL,                  -- BR-229
    failed_pin_attempts          INT NOT NULL DEFAULT 0,                   -- BR-201
    failed_password_attempts     INT NOT NULL DEFAULT 0,                   -- BR-201
    terms_accepted_at            TIMESTAMP NULL,                           -- LR-004 F15, platform-level
    terms_version                 INT NULL,
    privacy_accepted_at           TIMESTAMP NULL,                          -- LR-004 F15a, platform-level
    privacy_version                INT NULL,
    created_at                   TIMESTAMP NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE persons IS 'Module 0.1 — one row per human being, forever. No Blacklist field (BR-227). person_id is immutable and is the FK target for every other module — never key on mlid.';
COMMENT ON COLUMN persons.person_id IS 'Immutable surrogate identity key (BR-239 note: even Aadhaar correction changes column values on this same row, never re-keys to a new person_id).';

-- ---------------------------------------------------------------------------
-- 0.2 person_id_history — tracks MLTI->MLPI upgrades and Aadhaar corrections
-- (BR-184, BR-239). Append-only, never edited.
-- ---------------------------------------------------------------------------
CREATE TABLE person_id_history (
    id_history_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       BIGINT NOT NULL REFERENCES persons(person_id),
    old_mlid        VARCHAR(13) NOT NULL,
    new_mlid        VARCHAR(13) NOT NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT now(),
    reason          VARCHAR(255) NULL                                     -- e.g. 'Aadhaar Correction', 'Aadhaar Correction - Dispute Resolution'
);
COMMENT ON TABLE person_id_history IS 'Append-only. BR-184 MLTI->MLPI upgrades and BR-239 Owner-performed Aadhaar corrections both write here — never a silent overwrite.';

-- ---------------------------------------------------------------------------
-- 0.3 person_addresses — full-depth address, unlimited history (BR-225)
-- ---------------------------------------------------------------------------
CREATE TABLE person_addresses (
    address_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       BIGINT NOT NULL REFERENCES persons(person_id),
    door_no         VARCHAR(50) NOT NULL,
    area_locality   VARCHAR(100) NULL,
    pin_code        VARCHAR(6) NOT NULL,
    village_id      UUID NOT NULL,                                       -- FK -> locations, added in 0011 (locations created in Module 1)
    mandal          VARCHAR(100) NOT NULL,                                -- auto-derived from village
    district        VARCHAR(100) NOT NULL,                                -- auto-derived
    state           VARCHAR(100) NOT NULL,                                -- auto-derived
    from_date       DATE NOT NULL,
    to_date         DATE NULL,                                           -- NULL = current
    reason          VARCHAR(255) NULL,                                    -- e.g. 'Shifted' (BR-086)
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE person_addresses IS 'BR-225 full address history. village_id FK to locations(location_id) is added in 0011_indexes_and_constraints.sql once Module 1 exists (forward reference). Application layer must enforce exactly one is_current=TRUE row per person (documented invariant, not enforced here since a DB-level partial-unique-index choice is left to the RLS/verification chats to confirm).';

-- ---------------------------------------------------------------------------
-- 0.4 devices — Single Device Policy (BR-152, BR-197)
-- ---------------------------------------------------------------------------
CREATE TABLE devices (
    device_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id            BIGINT NOT NULL REFERENCES persons(person_id),
    device_fingerprint   VARCHAR(255) NOT NULL,
    registered_at         TIMESTAMP NOT NULL DEFAULT now(),
    is_active             BOOLEAN NOT NULL DEFAULT TRUE,                  -- only one active device per person at any time
    last_login_at          TIMESTAMP NULL
);
COMMENT ON TABLE devices IS 'BR-152/BR-197 Single Device Policy. Application layer enforces only one is_active=TRUE row per person; not a DB constraint here since prior device rows must be flippable to inactive without deletion.';

-- ---------------------------------------------------------------------------
-- 0.5 otp_verifications
-- ---------------------------------------------------------------------------
CREATE TABLE otp_verifications (
    otp_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id       BIGINT NOT NULL REFERENCES persons(person_id),
    purpose         otp_purpose_enum NOT NULL,
    otp_code_hash   VARCHAR(255) NOT NULL,
    sent_at         TIMESTAMP NOT NULL DEFAULT now(),
    verified_at     TIMESTAMP NULL,
    status          otp_status_enum NOT NULL DEFAULT 'Sent'
);

-- ---------------------------------------------------------------------------
-- 0.6 identity_documents
-- ---------------------------------------------------------------------------
CREATE TABLE identity_documents (
    document_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id     BIGINT NOT NULL REFERENCES persons(person_id),
    document_type identity_document_type_enum NOT NULL,
    file_url      TEXT NOT NULL,
    uploaded_at   TIMESTAMP NOT NULL DEFAULT now(),
    is_archived   BOOLEAN NOT NULL DEFAULT FALSE                          -- never deleted, only archived (BR-127 pattern)
);

-- ---------------------------------------------------------------------------
-- 0.7 duplicate_suspects — automatic OR manual flagging (BR-228)
-- ---------------------------------------------------------------------------
CREATE TABLE duplicate_suspects (
    suspect_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id_a        BIGINT NOT NULL REFERENCES persons(person_id),
    person_id_b        BIGINT NOT NULL REFERENCES persons(person_id),
    detection_method   duplicate_detection_method_enum NOT NULL,
    matched_on         VARCHAR(100) NOT NULL,                             -- e.g. 'Aadhaar+Phone'
    flagged_by         BIGINT NULL REFERENCES persons(person_id),         -- owner if manual
    status             duplicate_suspect_status_enum NOT NULL DEFAULT 'Open',
    created_at         TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT chk_duplicate_suspects_distinct_persons CHECK (person_id_a <> person_id_b)
);

CREATE INDEX idx_person_id_history_person ON person_id_history(person_id);
CREATE INDEX idx_person_addresses_person ON person_addresses(person_id);
CREATE INDEX idx_devices_person ON devices(person_id);
CREATE INDEX idx_otp_verifications_person ON otp_verifications(person_id);
CREATE INDEX idx_identity_documents_person ON identity_documents(person_id);
CREATE INDEX idx_duplicate_suspects_a ON duplicate_suspects(person_id_a);
CREATE INDEX idx_duplicate_suspects_b ON duplicate_suspects(person_id_b);

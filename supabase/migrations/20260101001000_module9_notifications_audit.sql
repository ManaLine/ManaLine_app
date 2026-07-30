-- =============================================================================
-- MANA LINE — Module 9: Notifications & Audit
-- Source: 03_Database_Schema.md §9.1-9.3, plus Merged Addendum item 6
-- ('Customer Address Updated' notification_type value)
-- =============================================================================

CREATE TYPE notification_type_enum AS ENUM (
    'New Device Login', 'Capacity Overflow', 'Owner Approval Confirmation',
    'Pending Approval', 'Pending Loan Request', 'Pending Membership Request',
    'Pending Withdrawal Request', 'Pending Online Payment', 'Account Period Due',
    'Account Period Overdue', 'Incomplete Profile', 'Penalty Applied',
    'Extension Request', 'Profit Share Declared', 'Profit Share Paid',
    'Customer Address Updated', -- Merged Addendum item 6 (Cross-Lender Proactive Address Alert)
    'Other'
);
CREATE TYPE audit_action_type_enum AS ENUM ('Settings Change', 'Permission Change', 'Loan Correction', 'Collection Correction', 'Membership Change', 'Day Reopen', 'PIN Approval', 'Password Reset', 'Account Approval', 'Other Admin Event');

-- ---------------------------------------------------------------------------
-- 9.1 notifications
-- ---------------------------------------------------------------------------
CREATE TABLE notifications (
    notification_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_person_id        BIGINT NOT NULL REFERENCES persons(person_id),
    business_id                  UUID NULL REFERENCES businesses(business_id),
    notification_type              notification_type_enum NOT NULL,     -- BR-205 minimum set
    message                          TEXT NOT NULL,
    related_entity_type                VARCHAR(50) NULL,                -- polymorphic reference, not a real FK
    related_entity_id                    BIGINT NULL,
    is_read                               BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                             TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON COLUMN notifications.related_entity_id IS 'Polymorphic pointer paired with related_entity_type; intentionally not a foreign key since the target table varies by notification_type.';

-- ---------------------------------------------------------------------------
-- 9.2 audit_log — administrative/security events ONLY (BR-158, BR-124)
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id              UUID NULL REFERENCES businesses(business_id),
    actor_person_id            BIGINT NOT NULL REFERENCES persons(person_id),
    action_type                  audit_action_type_enum NOT NULL,
    entity_type                    VARCHAR(50) NOT NULL,                -- e.g. 'loan', 'agent_permissions'
    entity_id                        BIGINT NOT NULL,                   -- polymorphic reference, not a real FK
    old_value                          JSON NULL,
    new_value                          JSON NULL,
    business_date                        DATE NULL,
    entry_timestamp                        TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE audit_log IS 'Administrative/security events ONLY — routine transactions live in their own module tables, never duplicated here (BR-158, BR-124).';

-- ---------------------------------------------------------------------------
-- 9.3 owner_approvals — in-context PIN confirmations (BR-125/200)
-- ---------------------------------------------------------------------------
CREATE TABLE owner_approvals (
    approval_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id                  UUID NOT NULL REFERENCES businesses(business_id),
    approved_by_person_id            BIGINT NOT NULL REFERENCES persons(person_id), -- Owner
    approval_context                   VARCHAR(100) NOT NULL,           -- e.g. "Closed Day Edit", "Loan Limit Override"
    related_audit_id                     UUID NULL REFERENCES audit_log(audit_id),
    approved_at                            TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_recipient ON notifications(recipient_person_id);
CREATE INDEX idx_notifications_business ON notifications(business_id);
CREATE INDEX idx_audit_log_business ON audit_log(business_id);
CREATE INDEX idx_audit_log_actor ON audit_log(actor_person_id);
CREATE INDEX idx_owner_approvals_business ON owner_approvals(business_id);

-- Cheti: the Owner's own chit fund, recorded as an ASSET.
--
-- This REVERSES BR-061 ("External Chits: recorded as business expense only").
-- That rule cannot describe how a cheti actually works. The Owner pays
-- instalments in and later avails a lumpsum back out -- the money is
-- recoverable, so it is not an expense. Booking it as one would drop line
-- profit every month the cheti runs and then show a single enormous phantom
-- gain in the month of availing.
--
-- WHY THE OWNER USES ONE: an investor is owed 100000. Rather than pull that
-- lumpsum straight out of the business, which starves the lending line, the
-- Owner joins a cheti of the same value, pays it in instalments out of BF,
-- and avails the lumpsum when the investor needs paying.
--
-- Deliberately NOT linked to an investor: confirmed with the Owner that a
-- cheti is just business cash, and which investor it eventually settles is a
-- decision made at the time, not a property of the cheti.

CREATE TYPE cheti_type_enum AS ENUM ('Fixed', 'Auction');
CREATE TYPE cheti_frequency_enum AS ENUM ('Daily', 'Weekly', 'Monthly');
CREATE TYPE cheti_status_enum AS ENUM ('Running', 'Completed');

CREATE TABLE chetis (
    cheti_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id           UUID NOT NULL REFERENCES businesses(business_id),
    name                  TEXT NOT NULL,
    -- Fixed = lucky draw, the instalment never varies.
    -- Auction = monthly bidding, so each instalment carries a dividend that
    -- reduces what is actually handed over.
    cheti_type            cheti_type_enum NOT NULL,
    frequency             cheti_frequency_enum NOT NULL,
    face_value            DECIMAL(14,0) NOT NULL CHECK (face_value > 0),
    total_instalments     INT NOT NULL CHECK (total_instalments > 0),
    instalment_amount     DECIMAL(14,0) NOT NULL CHECK (instalment_amount > 0),
    start_date            DATE NOT NULL,

    -- Position carried in when a cheti was already part-way through before
    -- this app existed. Same principle as a migrated loan: the history is NOT
    -- replayed, only the standing position is captured.
    --
    -- opening_amount_paid is its own figure and NOT derivable as
    -- opening_instalments_paid x instalment_amount: on an Auction cheti the
    -- dividends already earned mean 8 instalments of 5000 may have cost 36000,
    -- not 40000, and there are no per-month records from before migration.
    -- Final profit is (availed - total paid), so losing this number would make
    -- that unrecoverable forever.
    opening_instalments_paid INT NOT NULL DEFAULT 0 CHECK (opening_instalments_paid >= 0),
    opening_amount_paid      DECIMAL(14,0) NOT NULL DEFAULT 0 CHECK (opening_amount_paid >= 0),

    availed_date          DATE NULL,
    availed_amount        DECIMAL(14,0) NULL CHECK (availed_amount IS NULL OR availed_amount >= 0),
    -- True when the lumpsum was taken before migration. That cash is already
    -- inside the declared opening balance, so it must NOT move BF again.
    availed_pre_migration BOOLEAN NOT NULL DEFAULT false,

    status                cheti_status_enum NOT NULL DEFAULT 'Running',
    remarks               TEXT NULL,
    created_at            TIMESTAMP NOT NULL DEFAULT now(),

    CONSTRAINT ck_chetis_opening_within_term
        CHECK (opening_instalments_paid <= total_instalments),
    -- A date without an amount (or the reverse) is a half-recorded availing,
    -- which would silently distort the net position.
    CONSTRAINT ck_chetis_availed_pair CHECK (
        (availed_date IS NULL AND availed_amount IS NULL) OR
        (availed_date IS NOT NULL AND availed_amount IS NOT NULL)
    ),
    CONSTRAINT ck_chetis_availed_pre_migration_needs_availing
        CHECK (NOT availed_pre_migration OR availed_date IS NOT NULL)
);

-- Instalments recorded from migration forward. Rows here DO move BF; the
-- pre-migration ones live in chetis.opening_* and deliberately do not.
CREATE TABLE cheti_payments (
    cheti_payment_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cheti_id              UUID NOT NULL REFERENCES chetis(cheti_id) ON DELETE CASCADE,
    business_id           UUID NOT NULL REFERENCES businesses(business_id),
    business_date         DATE NOT NULL,
    gross_instalment      DECIMAL(14,0) NOT NULL CHECK (gross_instalment > 0),
    -- Always 0 on a Fixed cheti. On an Auction cheti this is the month's
    -- dividend, and it is the "cost part" the Owner asked for: cash out is
    -- reduced by it, and line profit is increased by it, because the
    -- entitlement still grows by the full gross instalment.
    dividend              DECIMAL(14,0) NOT NULL DEFAULT 0 CHECK (dividend >= 0),
    net_paid              DECIMAL(14,0) GENERATED ALWAYS AS (gross_instalment - dividend) STORED,
    recorded_by_membership_id UUID NOT NULL REFERENCES business_members(membership_id),
    entry_timestamp       TIMESTAMP NOT NULL DEFAULT now(),
    remarks               TEXT NULL,
    CONSTRAINT ck_cheti_payments_dividend_within CHECK (dividend <= gross_instalment)
);

CREATE INDEX idx_chetis_business ON chetis(business_id);
CREATE INDEX idx_cheti_payments_cheti ON cheti_payments(cheti_id);
CREATE INDEX idx_cheti_payments_business_date ON cheti_payments(business_id, business_date);

-- day_ledger has no column that can hold either side of a cheti. An
-- instalment is a BF outflow that is not a loan, an expense or an investor
-- withdrawal; an availing is a BF inflow that is not a collection or an
-- investor deposit. Without these two, closing_balance drifts by the
-- instalment amount every single period a cheti runs.
ALTER TABLE day_ledger
    ADD COLUMN cheti_paid     DECIMAL(14,0) NOT NULL DEFAULT 0,
    ADD COLUMN cheti_received DECIMAL(14,0) NOT NULL DEFAULT 0;

-- Retire 'External Chit'. Verified safe: expenses holds 0 rows, none of them
-- that category, and no function anywhere references the type or the literal.
-- Leaving it would invite a cheti to be booked as Karchulu and counted twice,
-- once as an expense and once as a cheti payment.
ALTER TYPE expense_category_enum RENAME TO expense_category_enum_old;
CREATE TYPE expense_category_enum AS ENUM ('General', 'Travel', 'Salary', 'Fuel', 'Other');
ALTER TABLE expenses
    ALTER COLUMN category TYPE expense_category_enum
    USING category::text::expense_category_enum;
DROP TYPE expense_category_enum_old;

-- Every one of the 65 existing public tables has RLS on; these match.
-- Owner-only: a cheti is the Owner's own financing, not agent-facing work.
ALTER TABLE chetis ENABLE ROW LEVEL SECURITY;
ALTER TABLE cheti_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY chetis_owner_all ON chetis FOR ALL
    USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));
CREATE POLICY cheti_payments_owner_all ON cheti_payments FOR ALL
    USING (app.is_owner(business_id)) WITH CHECK (app.is_owner(business_id));

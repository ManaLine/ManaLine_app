-- MANA LINE — 0044_business_name_unique_case_insensitive.sql
--
-- Confirmed real: same owner had "Sri tirumala finance" and
-- "sri tirumala finance" as two separate businesses — case-different but
-- effectively the same name, no constraint existed to prevent it.
--
-- Case-insensitive UNIQUE via a functional index on lower(trim(...)) —
-- Postgres has no native case-insensitive VARCHAR type without the
-- citext extension, and adding a new extension is a bigger, riskier
-- change than a functional unique index for this one column.

-- Rename the existing confirmed duplicate FIRST — the constraint below
-- would otherwise fail to apply immediately (these two real businesses
-- already violate it). Renaming the "Not Started" one (MLBI-16024000,
-- 0 agents/customers/investors) rather than the "Active" one
-- (MLBI-62730000, already has 1 agent assigned) — less real activity to
-- disturb. Data is fully preserved, only the name changes.
UPDATE businesses
SET business_name = business_name || ' (2)'
WHERE mlbi = 'MLBI-16024000' AND lower(trim(business_name)) = 'sri tirumala finance';

CREATE UNIQUE INDEX uq_businesses_name_ci ON businesses (lower(trim(business_name)));

COMMENT ON INDEX uq_businesses_name_ci IS
  'Case-insensitive uniqueness on business_name — added after finding the same owner had "Sri tirumala finance" and "sri tirumala finance" as two separate businesses. This is the real source of truth; client-side pre-checks (with alternative-name suggestions) are a UX convenience layered on top, not a substitute for this.';

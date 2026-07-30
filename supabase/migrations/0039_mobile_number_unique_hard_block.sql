-- MANA LINE — 0039_mobile_number_unique_hard_block.sql
--
-- PRODUCT DECISION (explicit, supersedes BR-228 for mobile_number): mobile
-- number now hard-blocks re-registration, same as aadhaar_number already
-- does. Originally, BR-228 deliberately made a mobile match a SOFT signal
-- only (duplicate_suspects flag, never blocking) — reasoning at the time
-- was to accommodate legitimate shared-phone/reassigned-number scenarios.
-- Master chat flagged this trade-off explicitly before implementing;
-- confirmed by product owner to proceed anyway.
--
-- NOTE: existing rows with duplicate mobile_number values (if any survived
-- earlier testing) will make this ALTER TABLE fail — run the cleanup
-- script (delivered alongside this migration) first if needed.

ALTER TABLE persons ADD CONSTRAINT uq_persons_mobile_number UNIQUE (mobile_number);

COMMENT ON CONSTRAINT uq_persons_mobile_number ON persons IS
  'Added per explicit product decision — supersedes BR-228''s original soft-only mobile duplicate signal. NULL mobile_number values remain unrestricted (Postgres UNIQUE allows multiple NULLs), matching persons.mobile_number staying nullable (BR-192/OW-015 migration-path accounts may have no mobile yet).';

-- =============================================================================
-- 0052b — persons.pin_length
-- =============================================================================
-- RECOVERED FILE, added 2026-07-30. This migration was applied directly to
-- the live project on 2026-07-28 (ledger version 20260728115602) and never
-- had a file in supabase/migrations/, which meant the repo could not rebuild
-- the database: a fresh project would have silently missed this column, and
-- any code reading persons.pin_length would fail against it. SQL below is
-- recovered verbatim from
-- supabase_migrations.schema_migrations.statements. See the drift note in
-- ../MIGRATIONS.md for how this class of gap arose.
-- -----------------------------------------------------------------------------

ALTER TABLE persons ADD COLUMN pin_length SMALLINT NULL;

COMMENT ON COLUMN persons.pin_length IS 'Digit length of the currently-set PIN (4 or 6). NULL = legacy PIN predating this column, treated as needing upgrade to 6-digit on next login.';

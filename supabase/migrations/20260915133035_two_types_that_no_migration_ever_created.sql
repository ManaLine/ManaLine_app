-- Two enum types that exist in production and in NO migration.
--
-- supabase/MIGRATIONS.md records this as the open question: "Nothing has
-- verified that running all 58 files in order against an EMPTY database
-- reproduces the current schema... treat 'the repo can rebuild the database'
-- as probable but unproven."
--
-- It has now been run, against a disposable local cluster with Supabase's
-- roles and auth schema stubbed, and the answer was NO. It failed after six
-- migrations, on 20260101000700_module6_loan_domain.sql:
--
--   ERROR: type "repayment_frequency_enum" does not exist
--
-- Diffing all 73 production enum types against every CREATE TYPE in the repo
-- found exactly two with no migration behind them. Both predate the
-- 2026-07-30 filename repair: that repair renamed files and rewrote the
-- ledger, but it could not capture objects created by hand in the dashboard,
-- because nothing recorded that they had been.
--
-- THIS FILE DOES NOT FIX THE REBUILD, and the reason is worth recording.
--
-- It was first written timestamped 20260101000050, to sort before the
-- migration that needs the type. The ledger then stamped it 20260915133035 --
-- the version is assigned when it is APPLIED, not when it is named -- and a
-- local file whose name disagrees with its ledger row is precisely the drift
-- Task 9 spent a day closing. A file cannot be both.
--
-- So this is only a RECORD: an idempotent no-op on production, capturing in
-- the repo two types that existed in no migration. The rebuild is fixed by
-- supabase/rebuild_bootstrap.sql instead, which is honest about what it is --
-- a prerequisite for an empty database, not a migration.
--
-- A DO block rather than CREATE TYPE IF NOT EXISTS, which Postgres does not
-- have for types.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typname = 'repayment_frequency_enum' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.repayment_frequency_enum AS ENUM ('Daily', 'Weekly', 'Monthly');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typname = 'loan_template_status_enum' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.loan_template_status_enum AS ENUM ('Active', 'Inactive');
  END IF;
END $$;

COMMENT ON TYPE public.repayment_frequency_enum IS
  'How often a loan is collected. Created by hand before the 2026-07-30 '
  'migration repair and captured in a migration only on 2026-09-15, after a '
  'rebuild against an empty database failed without it.';

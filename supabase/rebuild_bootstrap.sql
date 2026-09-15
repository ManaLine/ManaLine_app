-- What an EMPTY database needs before supabase/migrations can run.
--
-- NOT A MIGRATION, and deliberately not in supabase/migrations. A migration's
-- filename must match its ledger version, and the ledger assigns that version
-- when the file is APPLIED -- so a file that must sort before 20260101000700
-- can never also carry a 2026-09-15 version. Trying to be both is how the
-- drift in Task 9 started.
--
-- WHAT THIS IS FOR. supabase/MIGRATIONS.md recorded an open question: whether
-- running every file in order against an empty database reproduces the current
-- schema. On 2026-09-15 that was finally run, against a disposable local
-- Postgres cluster, and the answer was NO. It stopped after six files:
--
--   ERROR: type "repayment_frequency_enum" does not exist
--
-- Diffing production against the repo found the whole gap, and it is small:
-- two enum types and one table, none of which any migration creates. All three
-- predate the 2026-07-30 filename repair -- that repair renamed files and
-- rewrote the ledger, but nothing recorded which objects had been made by hand
-- in the dashboard, so it could not capture them.
--
-- Everything above `-- === SUPABASE ===` is the app's own. Everything below it
-- is what a managed Supabase project provides and a bare Postgres does not; on
-- a real Supabase project that half is unnecessary.
--
-- Run it with tool/verify_rebuild.ps1, which does the whole thing and then
-- runs the SQL test suite against the result.

-- === THE APP'S OWN, MISSING FROM EVERY MIGRATION ===

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                  WHERE t.typname = 'repayment_frequency_enum' AND n.nspname = 'public') THEN
    CREATE TYPE public.repayment_frequency_enum AS ENUM ('Daily', 'Weekly', 'Monthly');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                  WHERE t.typname = 'loan_template_status_enum' AND n.nspname = 'public') THEN
    CREATE TYPE public.loan_template_status_enum AS ENUM ('Active', 'Inactive');
  END IF;
END $$;

-- loan_templates. Its RLS policies ARE in 20260101001400, which is why that
-- migration has never been the thing that failed -- the table it guards simply
-- was not there. Column types, defaults and the foreign key are taken from
-- production's information_schema on 2026-09-15, not reconstructed from
-- memory. The table holds 0 rows in production.
--
-- Created WITHOUT the businesses foreign key here, because this file runs
-- before module1 creates that table. The constraint is added at the end of
-- this file, after the migrations have run.
CREATE TABLE IF NOT EXISTS public.loan_templates (
  template_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id               uuid NOT NULL,
  template_name             varchar(150) NOT NULL,
  status                    loan_template_status_enum NOT NULL DEFAULT 'Active',
  default_amount            numeric(14,0) NOT NULL,
  repayment_frequency       repayment_frequency_enum NOT NULL,
  duration_value            integer NOT NULL,
  default_roi_or_interest   numeric(10,2) NOT NULL,
  default_processing_fee    numeric(14,0) NOT NULL,
  default_grace_period_days integer NOT NULL,
  agent_permission_overrides json,
  effective_date            date NOT NULL,
  usage_count               integer NOT NULL DEFAULT 0,
  remarks                   text,
  is_locked                 boolean NOT NULL DEFAULT false
);

-- === SUPABASE ===
-- Roles, schemas and extensions a managed project already has. Stubbed so that
-- a failure during a rebuild is a failure of the MIGRATIONS rather than of the
-- scaffolding underneath them.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres LOGIN SUPERUSER; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- The default privileges Supabase installs, and the repo does not.
--
-- WHY THIS MATTERS MORE THAN IT LOOKS. RLS decides what a role may SEE; a
-- table GRANT decides whether the role may ASK. Without the grant Postgres
-- raises insufficient_privilege before any policy is consulted -- and a test
-- that counts visible rows reads that as "zero rows", which is indistinguish-
-- able from a policy correctly denying access.
--
-- So on a rebuilt database every NEGATIVE assertion in the RLS matrix passed
-- and every POSITIVE one failed, for the same reason, and the suite looked
-- like a security triumph. It was measuring nothing.
--
-- Production has these because the Supabase platform runs them when a project
-- is created, not because any migration does: 81 public tables carry SELECT
-- for anon, authenticated and service_role there, and 5 did here. Verified by
-- diffing information_schema.role_table_grants between the two on 2026-09-15.
--
-- Default privileges apply to tables created AFTER they are set, which is why
-- this sits in the bootstrap rather than anywhere later.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- And the tables this file made BEFORE the line above, which default
-- privileges cannot reach backwards to. loan_templates is created here rather
-- than by a migration precisely because it is one of the objects that exists
-- in production and in no migration -- so it is the one table that would have
-- been missed, and it was: the RLS matrix reported that a Customer could not
-- see an Active loan template in their own business, which is a real screen
-- (CW-003's template picker) and would have read as an RLS bug.
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $f$ SELECT nullif(current_setting('request.jwt.claims', true)::json->>'sub','')::uuid $f$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
  $f$ SELECT coalesce(current_setting('request.jwt.claims', true)::json->>'role','anon') $f$;
CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY, name text, public boolean DEFAULT false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text,
  owner uuid, metadata jsonb, created_at timestamptz DEFAULT now());
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
  version text PRIMARY KEY, statements text[], name text);

-- Storage helpers the bucket policies call. Supabase ships these; a bare
-- Postgres does not. foldername() splits an object path into its segments,
-- which is how a policy scopes a user to their own folder.
CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE parts text[];
BEGIN
  parts := string_to_array(name, '/');
  RETURN parts[1:array_length(parts,1)-1];
END
$f$;

CREATE OR REPLACE FUNCTION storage.filename(name text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE parts text[];
BEGIN
  parts := string_to_array(name, '/');
  RETURN parts[array_length(parts,1)];
END
$f$;

CREATE OR REPLACE FUNCTION storage.extension(name text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE parts text[];
BEGIN
  parts := string_to_array(name, '.');
  RETURN parts[array_length(parts,1)];
END
$f$;

-- ---------------------------------------------------------------------------
-- pg_cron, stubbed.
--
-- Supabase provides pg_cron; a stock PostgreSQL install does not, and
-- CREATE EXTENSION for something that is not on disk cannot be made to
-- succeed from SQL. Two migrations call cron.schedule() to book the soft-delete
-- purge and the account purge.
--
-- The stub records the booking in a table instead of running it, so the
-- rebuild can assert that the schedules were ASKED FOR -- which is the part
-- the repo is responsible for. Whether Supabase's scheduler then fires them is
-- the platform's business and is not something an empty local cluster can
-- answer either way.
--
-- This is the same category as storage.foldername() above: scaffolding the
-- platform owns, stubbed so the app's own schema can be judged on its own.
CREATE SCHEMA IF NOT EXISTS cron;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid   BIGSERIAL PRIMARY KEY,
  jobname TEXT UNIQUE,
  schedule TEXT NOT NULL,
  command  TEXT NOT NULL
);

CREATE OR REPLACE FUNCTION cron.schedule(p_name TEXT, p_schedule TEXT, p_command TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $f$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command)
       VALUES (p_name, p_schedule, p_command)
  ON CONFLICT (jobname) DO UPDATE
          SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
    RETURNING jobid INTO v_id;
  RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION cron.unschedule(p_name TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $f$
BEGIN
  DELETE FROM cron.job WHERE jobname = p_name;
  RETURN FOUND;
END
$f$;

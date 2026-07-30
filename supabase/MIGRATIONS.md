# Migrations — conventions and the 2026-07-30 drift repair

## Naming: always `<14-digit timestamp>_name.sql`

The Supabase CLI only recognises migration files whose name starts with a
14-digit `YYYYMMDDHHMMSS` timestamp. Anything else is **silently ignored** —
not warned about, not errored on. `supabase db push` simply reports nothing
to do.

Create migrations with `supabase migration new <name>` so the timestamp is
generated for you. Never hand-name a migration file.

## What went wrong before 2026-07-30

Migrations in this repo were originally named `0001_…` through `0055_…`.
Because those names don't parse as timestamps, the CLI never saw a single one
of them, and `supabase db push` had never applied anything. The schema had
instead been maintained by pasting SQL into the dashboard by hand.

Three consequences, all found on 2026-07-30:

1. **~10 migration files had never been applied at all.** 21 RPCs and 2
   storage buckets that the app actively calls did not exist in the database.
   Recording a collection, creating a loan, business sessions, day closure,
   agent settlements, cash transfers, live-photo capture, business discovery,
   the investor statement and Owner/Agent address edits were all failing at
   runtime. Files `0019`, `0021`–`0027`, `0030`, `0031` were the gap.

2. **The ledger and the repo had no overlap.** `supabase_migrations.schema_migrations`
   held 20 rows, none of whose `version` values corresponded to any filename.

3. **Two migrations existed only in the database.**
   `businesses_pending_member_select` and `add_pin_length_to_persons` had been
   applied by hand and never written to a file — so the repo could not rebuild
   the database. Both have since been recovered from
   `schema_migrations.statements` and now live in the files timestamped
   `…005400` and `…005500`.

## The repair

* All 58 files renamed to `20260101HHMMSS_name.sql`, ordinals preserved in
  order (`0001` → `20260101000100`, … `0055` → `20260101005800`). The date is
  synthetic — these migrations were authored over a longer period than one
  minute — but it is monotonic and the digits still encode the original
  sequence number, so the mapping back to the old `00NN` names stays legible
  in `git log --follow`.
* The duplicated `0051` prefix (`fix_admin_delete_business` and
  `search_businesses_by_name_rpc` both used it) was resolved into two
  distinct slots.
* The ledger was rewritten to exactly those 58 versions, all marked applied,
  so the CLI treats the existing schema as fully migrated rather than trying
  to re-run everything.
* The pre-repair ledger, including the full SQL text of every row, was
  snapshotted to `supabase_migrations.schema_migrations_backup_20260730`.
  Safe to drop once you're confident in the repair.

Verified afterwards: `supabase migration list --linked` matches local to
remote for all 58, and `supabase db push --dry-run` reports "Remote database
is up to date."

## Known limitation

Nothing has verified that running all 58 files in order against an **empty**
database reproduces the current schema. It should, now that the two orphans
are captured, but the older files use bare `CREATE TABLE` / `CREATE POLICY`
without `IF NOT EXISTS` guards, so a failure partway through a fresh run
would leave a half-built schema. Testing that needs a scratch project or a
local Docker stack. Until someone does it, treat "the repo can rebuild the
database" as probable but unproven.

## Note on file contents vs. what was applied

Where a migration was applied through the Supabase management API during the
2026-07-30 repair, the SQL sent was the same as the file's but with some long
explanatory comment blocks trimmed. Functions, policies, columns and
`COMMENT ON` text are identical; only file-header prose differs. One
function, `app.apply_loan_penalty`, reached its final form through a
follow-up statement after its migration ran — the file contains the final
version, which is what a fresh run would produce.

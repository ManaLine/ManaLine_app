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

## Known limitation — ANSWERED 2026-09-15, and the answer is now yes

This section used to say: "Nothing has verified that running all 58 files in
order against an **empty** database reproduces the current schema... treat
'the repo can rebuild the database' as probable but unproven."

It has been run. `pwsh tool/verify_rebuild.ps1` creates a disposable Postgres
cluster on port 5433 with trust auth — no password, no Docker, and it cannot
reach production or any local database you already have, because it makes its
own server. **All 427 migrations now apply cleanly to an empty database.**

The first run got 23 files in. Eight distinct failures stood between that and
427, and every one of them was invisible to `flutter analyze`, to
`flutter test`, and to applying the same migrations against production — because
production already had whatever the migration failed to create. That is the
whole value of the exercise: it is the only check in this project that does not
get to assume the answer.

| Stopped after | Failure | What it was |
|---|---|---|
| 6 | `type "repayment_frequency_enum" does not exist` | Two enum types that exist in production and in no migration. Bootstrap. |
| 7 | `relation "loan_templates" does not exist` | A table in the same category. Bootstrap. |
| 21 | `function storage.foldername(text) does not exist` | Supabase scaffolding. Stubbed. |
| 23 | `cannot change return type of existing function` | `app.submit_draft` used CREATE OR REPLACE where the return type changed. DROP-then-CREATE. |
| 95 | `constraint "chk_businesses_owner_bf_nonneg" already exists` | 22 migrations present under two names. |
| 95 | `extension "pg_cron" is not available` | Platform extension. Neutralised by name, stubbed. |
| 196 | `column "village_code" ... does not exist` | A migration edited to describe the end state. |
| 261 | `ledger_history no longer contains the text it was matching on` | CRLF vs LF. |

**The first three predate the 2026-07-30 repair above.** That repair renamed
files and rewrote the ledger, but nothing recorded which objects had been
created by hand in the dashboard, so it could not capture them. They live in
`supabase/rebuild_bootstrap.sql` — which is honest about what it is: a
prerequisite for an empty database, not a migration. A migration's filename must
match its ledger version and the ledger assigns that version when the file is
*applied*, so a file that must sort before `20260101000700` can never also carry
a 2026-09-15 version. Trying to make one file be both is how the drift in this
document started.

**The 22 duplicates.** Each was a hand-named pre-apply draft sitting beside its
ledger-stamped twin. The drafts had no ledger row, so they were deleted — but
19 translation keys lived only in them, and 21 more were already known to exist
in `ui_translations` with no migration behind them at all. All 40 are now in
`20260915140000_restore_orphaned_translation_keys.sql`, read out of production
by psql and written straight to the file. `_appliedButFileMissing` in
`test/translation_keys_exist_test.dart` is empty for the first time.

**The line-ending one is worth reading twice.** Six migrations patch a live
function by reading `pg_get_functiondef()` and running `replace()` on its text.
The stored body keeps the line endings of the file that defined it; the match
string keeps the line endings of the file doing the patching. One was CRLF and
one was LF, and the anchor was present, character for character identical in any
editor, and could not match. 97 of 426 files were CRLF, with no rule saying
which they should be. `.gitattributes` now pins `*.sql text eol=lf` and
`test/migration_line_endings_test.dart` fails on a carriage return.

**What this unlocked.** The five scratch files in `supabase/tests/` had never
executed — they need a database with no books in it, and branching is a Pro-plan
feature. They run against this cluster:

```bash
pwsh tool/verify_rebuild.ps1 -Keep
$env:MANA_DB_URL = 'postgresql://postgres@localhost:5433/mana_rebuild'
pwsh tool/run_sql_tests.ps1 -AllowNonEmpty
```

On their first execution they reported seven failures. Six were defects in the
tests themselves, each of which had been reporting the schema as broken:
a 15-character MLID in a `varchar(13)`; a `gender_digit` assertion stale since
Others was added a month earlier; an address fixture missing five NOT NULL
columns, whose own error was swallowed by a bare `WHEN OTHERS THEN NULL`; a
`day_ledger` insert the recompute trigger had already made; and a penalty
assertion that had the column default backwards. The seventh is real and is
recorded below.

A test that has never run does not go stale loudly.

**The seventh, since closed:** SP-001 business suspension was enforced in
neither layer. No RLS policy references `business_status`, and
`lib/shared/business_suspension_gate.dart` — written for exactly this and
recommending its own hookup in its header — had **no callers**. LR-012 drew a
red "Suspended" pill on the card and left the card tappable.

Decided 2026-09-15: enforce at the application layer, fail closed. The gate is
wired at five entry points and `test/business_suspension_gate_test.dart` fails
if any stops calling it. The two on the login path read a `business_status`
already loaded with the memberships, so they add no round trip — a live check
there would have ejected an agent to an error screen on the same thirty-second
signal drop that `lib/shared/outbox/` exists to ride out.

RLS is deliberately unchanged, which leaves one thing open and worth stating:
a client that is not this app, driving PostgREST with a valid JWT, can still
read a suspended business's rows. All six SQL files pass.

## Note on file contents vs. what was applied

Where a migration was applied through the Supabase management API during the
2026-07-30 repair, the SQL sent was the same as the file's but with some long
explanatory comment blocks trimmed. Functions, policies, columns and
`COMMENT ON` text are identical; only file-header prose differs. One
function, `app.apply_loan_penalty`, reached its final form through a
follow-up statement after its migration ran — the file contains the final
version, which is what a fresh run would produce.

# CLAUDE.md

**Read this file at start of every session. Confirm plugins active before starting work.**

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MANA LINE — a Flutter + Supabase field lending app for rural India (owner, agent, investor, customer workspaces; 5 languages). Read `README.md` first — it is current and accurate, including its "Status" and "Not yet true" sections.

**Money correctness is a safety property here.** A confidently wrong number on a collection screen is worse than a crash, because nobody notices it. Never swallow an error into a plausible value (`catch (_) => 0` on a money path). Read the comments at the top of any money file before changing it; commit messages explain *why* and are worth reading before touching money code.

## Build, run, test

```bash
flutter analyze
flutter test                     # 757 tests
flutter build apk --debug --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
flutter run -d chrome --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Supabase credentials come from `--dart-define` and live in `run.ps1.txt`, which is **tracked, not git-ignored** — it holds only `SUPABASE_URL` and the anon key, both of which ship inside every APK anyway. Nothing else may be added to it: a service-role key or JWT secret there would be a real leak. Put those in `.env` (already ignored). **Without them the app does not fail — it hangs**, because the fallback URL is a host that does not exist; symptoms are raw translation keys on every screen and login claiming "No internet connection". A "Build not configured" screen catches this in `main.dart`. Never commit credentials.

Run a single test file with `flutter test test/<file>.dart`. adb is not on PATH — use `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.

Supabase work goes through the project's Supabase MCP server (`execute_sql`, `apply_migration`, `list_migrations`, `get_edge_function`, `get_logs`). There are SQL test files in `supabase/tests/` (schema integrity, RLS access matrix, multi-tenancy isolation).

## Architecture

**Screen IDs are the routing contract.** Each spec screen has a locked ID (`LR-001`, `OW-005`, `AG-003`, …); the GoRouter in `lib/app/router.dart` registers exactly one route per ID (`/ow-005`), and feature screens live at `lib/features/<workspace>/screens/<id_lowercased>_*.dart`. A file/screen number doubles as its route name — rename one and you break the 1:1 cross-reference. Routes pass state through `extra` and query params; `_resolveBusinessId(s)` in router.dart is the single place that persists/recovers `businessId`.

**One workspace per feature directory**, `lib/features/{login_registration, owner_workspace, agent_workspace, customer_workspace, investor_workspace, support_admin, admin}/`. Each contains:
- `screens/` — one `ConsumerStatefulWidget` per locked screen ID. Screens read `ref.watch(provider)` and call `ref.read(provider.notifier)`, never Supabase directly.
- `state/` — Riverpod providers: `*_api_service.dart` classes wrap Supabase (`Supabase.instance.client`, `ref.read(authFlowProvider)`) and `*_state.dart` holds `AsyncNotifier`/`StateNotifier`s. Screens sit on top of the notifiers; API-service method signatures are safe to reshape as long as notifier callers stay compiling.

**Design system** lives in `lib/design/` — tokens (colors, typography, spacing), components (`ManaText`, `ManaHeader`, `ManaAmount`, `ManaSkeleton`, `ManaStatStrip`), `theme.dart`. `ManaText` enforces the locked Title Case standard in code; `ManaText.raw()` is the carve-out for free text and system IDs.

**Auth is NOT GoTrue.** `persons` (MLID/password_hash/pin_hash) is the sole identity source of truth (BR-178/181/182); there is no `persons.auth_user_id`. Login/OTP/PIN flows call Supabase Edge Functions (`supabase/functions/auth-*`, the only functions; shared helpers in `_shared/`) which mint a custom JWT carrying a `person_id` claim. `main.dart`'s `Supabase.initialize(accessToken: ...)` callback attaches that token to every request and — on 1-hour expiry — clears it and bounces to PIN entry (`/lr-009`), which re-mints. RLS reads the claim via `app.current_person_id()`. `ManaSession` (`lib/features/login_registration/state/auth_flow_state.dart`) holds the session, persists to `flutter_secure_storage`, and remembers the last businessId/agentId/membershipId that router routes read for their stub fallbacks.

**Time:** every timestamp is IST. Write timestamps with `manaTimestamp()` from `lib/shared/mana_time.dart` (offset derived from UTC, never the handset), never a bare `DateTime.now()`. `manaBusinessDate()` is the Indian calendar day — a 00:30 IST collection belongs to that Indian day. The database TimeZone is `Asia/Kolkata`.

## Money conventions (load-bearing)

Full list in README §"Money conventions"; the ones that change code:

- **ROI is ₹ per ₹100 per month**, not annual. Daily interest = `principal × (roi/100) / 30` on a 30-day month; rounding is CEILING to whole rupees (all money columns are `numeric(_,0)` — paise cannot be stored). Yearly compounding uses **actual calendar days** (365 or 366 for leap years), not hardcoded 360 — this is the Actual/360 convention (monthly rate ÷ 30 for daily, actual days for yearly).
- **`loans.amount_given` is a GENERATED column** (`repayment − interest − fee`). Never write it.
- **BF is cash** — only money that actually moved. Interest/fee withheld from a disbursement never left the till, so they never return to it as fresh cash; adding them back double counts (pinned in `test/migration_loan_math_test.dart`).
- **A cheti is an asset, not an expense** (instalments come back as an availed lumpsum).
- **`day_ledger` is recomputed, never incremented** — triggers on the eight source tables call `app.recompute_day_ledger()`, which rebuilds the day from scratch. Backdated entries cascade forward (one day's closing is the next day's opening).
- **BF is derived, never a stored running total** — `app.recompute_agent_bf()` recomposes an agent's cash from its events; `app.recompute_business_bf()` sets `owner_bf_balance` to the latest `day_ledger` closing minus what the agents hold. Delete and restore both move BF because neither has to remember to. Day one seeds from `businesses.opening_bf_declared_amount`, **never** from `owner_bf_balance` — seeding from a running total was the original defect. The two non-negative CHECKs are gone on purpose: a derived figure must be allowed to state the truth, and the pre-flight guards in the spending RPCs are the real backstop.
- One `remaining_balance` per loan; no payment waterfall; no interest accrual engine yet.

## Backend gotchas

- **Migration filenames must be `<14-digit-timestamp>_name.sql`** — anything else is silently ignored by `supabase db push` (this already happened once; full story in `supabase/MIGRATIONS.md`). Create with `supabase migration new <name>`. `supabase_migrations.schema_migrations` is the source of truth; after applying via MCP, write the local file with the *exact* stamped version or a later push re-runs it.
- **plpgsql bodies are not type-checked at CREATE time** — a broken function applies cleanly and fails on first call. Invoke it (inside a rolled-back transaction) before believing it works. Diff `pg_proc` before trusting that an RPC exists.
- **Changing an RPC's parameter list is DROP then CREATE, never `CREATE OR REPLACE`** — a changed, reordered or newly-defaulted parameter creates a *second* function, and PostgREST then answers HTTP 300 (PGRST203) because it cannot choose. Hit four times in one week (`ledger_history`, `request_bf_update`, `import_migrated_loans`, `record_collection`). After any signature change, count the overloads: `select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app' and p.proname='<name>';` must be 1.
- **PostgREST returns 200 for an UPDATE that matches zero rows** — a silent no-op is indistinguishable from success; only a re-read or checking the returned row count proves a write landed.
- **RPCs in the `app` schema need `.schema('app').rpc(...)`** — a bare `.rpc()` targets `public` and 404s. Tables are in `public`.
- **PostgREST embeds must name the FK** when two exist between the same tables, or PGRST201 (HTTP 300) kills the query — and the screen just says it could not load. There are **eleven** such pairs, not the three once listed here; `test/ambiguous_embed_guard_test.dart` holds the list, scans every `.select()` in `lib/`, and regenerates from `pg_constraint`. `!inner` is a join modifier, not an FK name: `persons!inner(...)` under `business_members` is still ambiguous.
- **All 67 public tables have RLS.** New tables match the existing pattern: `app.is_owner(business_id)` for owner-scoped, plus `app.is_active_agent(...)` / `app.agent_permission(...)` where agents need reach.

## Testing conventions

`flutter test` runs everything. `test/support/mana_harness.dart` pumps a whole screen with everything it expects — Riverpod scope, translation cache, secure storage, GoRouter — using the real `ManaTheme.light()`, because against Flutter's default theme the type scale differs and you'd measure a layout that doesn't exist.

- **Layout tests carry vendored translations on purpose** (`test/support/mana_translations_fixture.dart`): translated width is data, and without the fixture the "five languages" test measures narrower text than production.
- **Overflow is the recurring bug class** (shipped 4×; always a bare unflexible child beside a flexible one). It is invisible to `flutter analyze`. The harness checks it via `expectNoLayoutFault`, at text scales `[1.0, 1.3, 1.6, 2.0]` on a 360×640 surface. On device, the only reliable check is `adb logcat | grep overflowed`.
- **When a screen loads in `initState`, seed its provider** rather than letting it reach the network — otherwise the test lays out an empty state and proves nothing.

## Docs

`docs/01_Global_Rules_Guide.md` holds the locked business rules (BR-001…BR-240+); `docs/15_Calculation_Engine.md` holds the locked formulas. Per project convention, final BR and calculation-engine documents are authored at the *end* — decisions are recorded in code comments and commit messages as they are made, not by editing the specs mid-flight.

## Plugins / capabilities

Install from an **interactive** `claude` terminal — `/plugin` opens a dialog panel and cannot run in a non-interactive session.

All four live in the `claude-plugins-official` marketplace (already added at `~/.claude/plugins/marketplaces/claude-plugins-official`). No third-party marketplace is needed — `superpowers` is vendored there from `obra/superpowers`, and `code-review` is Anthropic's, so the `trailofbits/skills` fallback is unnecessary.

| Capability | Install source | Status here |
|---|---|---|
| Superpowers | `/plugin install superpowers@claude-plugins-official` | Active — 14 skills (`test-driven-development`, `systematic-debugging`, `brainstorming`, `writing-plans`, …) |
| Security Guidance | `/plugin install security-guidance@claude-plugins-official` | Active — **0 skills is correct**: it ships `hooks/`, not `skills/`, and fires automatically on edits and on Stop |
| Frontend Design | `/plugin install frontend-design@claude-plugins-official` | Active — 1 skill; built-in `design:*` / `artifact-design` also available |
| Code Review | `/plugin install code-review@claude-plugins-official` | Active — 1 skill; built-in `engineering:code-review` / `/code-review` also available |

Two files carry the state, and **both** must agree or nothing loads:
- `~/.claude/settings.json` → `enabledPlugins` map (`"<plugin>@claude-plugins-official": true`). This is what `/plugin install` writes, and it can be edited directly when `/plugin` is unavailable.
- `~/.claude/plugins/installed_plugins.json` → per-plugin `installPath` under `~/.claude/plugins/cache/`.

Enabling alone is not installing. If `installed_plugins.json` names an `installPath` that does not exist on disk, the plugin silently fails to load with no error — this already happened here. Marketplace entries with a local `./plugins/<name>` source can be copied from the marketplace clone; `superpowers` is a git-URL source and has to be cloned at the sha pinned in `marketplace.json`. Verify with `/plugin list`; the Desktop app's Settings → Plugins pane shows the same thing with skill counts.

## Workflow rules

**Before any new work:**
Full pass over existing code — bugs, security issues, dead code (unused functions/imports/files, duplicate logic, dead comments). Summarize findings. Fix what's safe immediately. Flag the rest before touching.

**Tools:**
- Superpowers: plan-first, TDD (RED-GREEN-REFACTOR) for all non-trivial tasks. Plan before code. Confirm architecturally significant decisions before proceeding.
- Frontend Design: all UI/layout/styling work. Real design decisions, not generic defaults.
- Code Review: senior-engineer-lens review on every diff before presenting — bugs, anti-patterns, SOLID violations, inconsistent style, dead code.
- Security Guidance: run on every change — injection flaws, unsafe deserialization, insecure DOM APIs, hardcoded secrets/keys, leak-prone patterns. Fix before marking done, don't wait to be asked.

**Ongoing:**
- Remove genuinely unused code when touching a file. Ask first if uncertain whether something is dead or planned.
- Minimal code — no speculative abstractions, no "just in case" code.
- Write/update tests for anything changed, not just anything added.
- Flag tradeoffs/risky assumptions instead of guessing silently.

**Goal:**
Fast, responsive, close-to-bug-free app. Minimal, clean code. No bloat. No unused code. No unpatched security gaps. Correctness and simplicity over cleverness.

## Not breaking the thing next to the thing you fixed

Every fix in this project that later came back as a new bug followed the
same shape: a change correct in itself, verified in isolation, reported as
done — while a second consumer of the same function, column or widget went
on using it the old way. **"Migration applied" and "flutter analyze clean"
have both repeatedly meant nothing.** Neither one executes a plpgsql body;
neither one loads a screen.

**Before changing anything shared, list its consumers.** A function, view,
column, widget or RPC. Grep `lib/` for the name; for SQL, count callers in
`pg_proc` and `pg_views`. If the list is longer than one, every entry gets
checked or gets said out loud. The two worst regressions here were a
shared window used by two things and a photo column read by sixteen — in
both cases three sites were updated and the rest silently broke.

**A change is not done until it has been run.** Not applied — run. For a
plpgsql function that means invoking it inside a rolled-back transaction
and reading the result, because bodies are not type-checked at CREATE time
and an invented enum literal applies perfectly and throws on first call.
Three times in one week: `'General'`, `'Self Request'`, `'Full Payment'`.
Read `enum_range` before writing the literal, not after.

**On a money path, read the number back afterwards** — the stored row, not
the return value. A withdrawal that validated against a computed principal
and subtracted from a stale stored one would have destroyed ₹91,250 of an
investor's money. It was caught only by selecting `principal_amount` after
the call and noticing it was wrong.

**Widening a filter changes everything downstream of it.** Making account
periods open-ended was right, and it silently stretched a one-entry-per-
window rule from four days to fifteen, blocking every weekly collection.
Filtering Inactive areas out of a list was right, and it left an Owner
with no way to understand an empty screen. Ask what reads this, and what
that thing takes it to mean.

**When a fix makes a previously unreachable path reachable, walk it.**
Fixing Request-to-Join delivered real people into an approval that had
never run and a screen that crashed on a null embed. A door locked for
months has nothing tested behind it.

**Report what was verified, and how, separately from what was changed.**
"Fixed" with no probe behind it is a guess. If something could not be
verified, say so rather than implying it was.

### The guards, and why they exist

Prose is weakest exactly when sessions get long, which is when regressions
happen. These fail instead, under `flutter test`:

| Guard | Stops |
|---|---|
| `stored_column_display_guard_test.dart` | Drawing a stored file without resolving the path — the 13 blank avatars |
| `money_write_guard_test.dart` | A money amount written straight from the client — the unguarded payout |
| `collection_window_test.dart` | The one-entry window drifting from week/month — the 15-day collection block |
| `schema_snapshot_test.dart` | Calling an RPC that is not there; a second overload (PGRST203); a Dart list drifting from a DB enum |
| `consumer_census_test.dart` | A shared contract quietly gaining or losing a consumer — the recognition failure itself |
| `ambiguous_embed_guard_test.dart` | PGRST201 on an unqualified FK embed |
| `sql_enum_literal_guard_test.dart` | An invented enum literal in migration SQL — 22P02 on first call |
| `sql_function_reference_guard_test.dart` | An invented `app.` function name in migration SQL — 42883 on first call |
| `village_search_rule_test.dart` | The PIN+3-letters rule drifting apart across its three copies |
| `village_lookup_guard_test.dart` | A PIN village search that reads `locations` without the LGD reference |
| `otp_navigation_guard_test.dart` | Reaching the OTP screen without an OTP having been sent |
| `expectNoLayoutFault` in the harness | Overflow, at four text scales in two languages |

`test/support/schema_snapshot.dart` is generated, not written — the query to
regenerate it is in its header, and it needs regenerating after any schema
change. A stale snapshot is not silently wrong: it fails the moment the app
calls something it has never heard of.

**The census is answered by looking, not by editing the number.** A count
that went up means a new file took the dependency: open it, check it honours
the contract, and only then record the new figure. That check is the whole
purpose of the test.

**Prefer adding a guard over adding a rule.** When a regression is found,
the question is not only "what fixes it" but "what would have failed".
When a guard reports a violation, fix the code or sharpen the rule with a
reason written down — never loosen it to get green. `availed_amount` came
off the money list because it is a declared figure rather than a derived
balance, and that reasoning is in the file.

### Running the SQL guards

`supabase/tests/*.sql` had never been executed. They are wired now:

```bash
pwsh tool/run_sql_tests.ps1
```

It needs `MANA_DB_URL`, which is **not** in this repo and must not be —
`run.ps1.txt` carries the anon key because that ships inside every APK
anyway, and a database password does not.

**Every file declares what it may be run against**, in a `-- @target:` line
near the top, and the runner obeys it:

| `@target` | Means | Runner behaviour |
|---|---|---|
| `production` | Reads only | Runs anywhere, with `default_transaction_read_only=on` |
| `scratch` | Fabricates persons, businesses, loans | Refused unless the target holds no businesses or loans |

A file with no marker is treated as `scratch`, because that is the direction
in which being wrong survives. `live_invariants_tests.sql` is the only
`production` file; the other five build fixtures.

**The split exists because the two kinds prove opposite things.** A stranded
customer, a mistyped village state, a loan asking for nothing while money is
owed — none can be reproduced with fixtures, because the thing under test
*is* the production data. Against an empty branch they pass trivially. The
fixture files are the reverse: meaningful anywhere, catastrophic on a real
book.

**The read-only session is the guard, and it is deliberately a runtime one.**
Deciding which files were safe, I counted `INSERT` statements and concluded
`migration_weekly_ledger_tests.sql` wrote nothing. Its writes are inside
`app.import_weekly_account` — invisible to any reading of the file's own
statements — and it was replaying twelve fabricated weeks over
`businesses ORDER BY created_at LIMIT 1`, i.e. **whichever real book was
oldest**, with the `ROLLBACK` as the only thing in the way. Static
inspection cannot answer this question. A read-only transaction answers it
at runtime.

Two consequences worth knowing before writing a new file:

- a `production` file can contain **no DDL at all** — `default_transaction_read_only`
  refuses `CREATE TEMP TABLE` and `CREATE FUNCTION` alike, so the temp-results
  harness the scratch files open with is unavailable. Raise `NOTICE`/`WARNING`
  inline and carry counters in a custom GUC via `set_config`. (I assumed temp
  tables were exempt. They are not; running it said so.)
- a scratch file must **build its own fixtures**, never adopt an existing row.
  `test/sql_tests_wired_test.dart` fails any scratch file matching
  `FROM businesses ORDER BY`.

There is no override for the production project ref. `-AllowNonEmpty` lets
scratch files run against a branch somebody has seeded deliberately; it does
not lift that refusal. Nothing having run at all exits 3 — "did not look"
must never read as green.

`test/sql_tests_wired_test.dart` runs under `flutter test` and keeps this
honest: every file must declare a `@target`, must be able to announce a
failure (`RAISE WARNING 'FAIL …'`), scratch files must `ROLLBACK` and must
not adopt an existing business, production files must contain no DDL and
must not turn the read-only session off. And when `MANA_DB_URL` is set it
shells out to the runner and asserts a zero exit; when it is not, it
**prints a skip** rather than passing quietly.

**Still uncovered, and known:** the five scratch files have still never
executed, because that needs a database with no books in it and branching is
a Pro-plan feature; the `production` file has run, and passes. Judgement
regressions — correct code that reads as broken — have no guard at all and
are found on the handset.

Two things came off this list on 2026-09-04, both the same failure: CREATE
says yes to almost anything inside a plpgsql body, and the first invocation
is what says no.

An invented FUNCTION NAME is the second. A migration called
`app.person_current_village`, which had never been written; it applied
perfectly and would have thrown 42883 the next time somebody typed a village
name into a box. I wrote that one an hour after building the guard for enum
literals, which is the sharpest illustration available that the rule "invoke
it before believing it" depends entirely on remembering.
`test/sql_function_reference_guard_test.dart` now checks every `app.<name>(`
in every migration against the snapshot — 209 distinct names today, two of
them genuinely retired and listed by name with the reason. Verified it trips
on the real case by removing `person_current_village` from the snapshot.

Enum literals were the first, after the fourth instance. `'Other'` for `occupation_enum` (which is `'Other-Custom'`)
made an Owner approving a Customer's request to join throw 22P02 on every
call since the function was written, while the Investor branch two lines
below it worked — so the feature read as half-alive rather than broken.
`test/sql_enum_literal_guard_test.dart` now checks positional
`INSERT INTO t (cols) VALUES (...)` in every migration against
`manaEnumColumns` in the snapshot. It counts what it could not parse and
fails if it ever stops finding literals to check, because a guard that
quietly checks nothing reads exactly like one that passes. Literals already
superseded by a later migration are listed by name with the migration that
fixed them — a migration file is a record of what ran, not something to
edit until it looks right.

## Bug-fix batch mode (real-device testing sessions)

Triggered when handed a batch of 15-20 device-testing issues. Overrides
the standard "full pass + TDD every change" workflow for speed — the
Hard line below never relaxes regardless of batch mode.

**Phase 1 — triage + roadmap, no fixing.** Classify each item BLOCKS
TESTING / DEGRADES TESTING / COSMETIC, one-line reason each. Then build
a tranche-based roadmap (which items ship in which order/batch, and
why) from a complete read of the bug list — not a partial skim. If
anything needed to classify or plan a fix isn't resolvable from the
migration files, business rules docs, or the rest of the repo, ask me
directly rather than assuming. Present the triage table + roadmap.
Stop, wait for my approval before touching any code.

**Phase 2 — fix BLOCKS TESTING items first**, sequentially, in the
approved tranche order. `flutter analyze` after each. Commit after each.

**Phase 3 — remaining items**, grouped by workspace/feature directory
(owner/agent/customer/investor/backend-RPC), in the approved tranche
order. One file-touch-list per group, no cross-boundary edits without
flagging first.

**Phase 4 — stop before shipping.** Once all fixes in the approved
roadmap are done and `flutter analyze` is clean on every touched file,
stop. If the batch touched SQL — a migration, an RPC, a view, RLS — run
`pwsh tool/run_sql_tests.ps1` first and report the result; that is the only
thing that executes the schema and data assertions. Do not push, build the APK, or install. Present a summary (fixed
/ flagged / deferred, table format) and wait for my explicit approval
before running `flutter build apk` or `adb install`.

**Token discipline for this mode:**
- Read only the file(s) the specific bug needs — no directory scans "to
  be safe," no re-reading files already in context this session.
- No restating bug text or file contents back before acting.
- No progress narration mid-fix ("Now checking...", "Let me look at...").
- `flutter analyze` after each individual fix; one full `flutter build
  apk` at the end of the whole batch, not after each fix.
- End-of-batch summary is a table (bug → status → one-line note), not
  prose recap.
- Skip TDD's full red-green-refactor ceremony for straightforward fixes —
  add/adjust the one test that would have caught the bug, not a new
  suite — unless the bug exposes a real gap Superpowers should plan
  around.
- Run Code Review once over the full batch diff before the final build,
  not per micro-fix.
- Security Guidance still fires on every change as normal (it's
  hook-driven, not a cost decision).

**Hard line — never skipped for token savings:**
- Never invent schema/columns/RPCs; never work around a gap silently.
- Never touch RLS policies or a money-path file without flagging it
  explicitly, however briefly.
- Migration filename convention and the DROP-then-CREATE RPC rule apply
  in full, every time.
- Never report a fix as done if `flutter analyze` still shows errors in
  that file.
- Money conventions section applies in full — no relaxation.

**Final step (only after my approval in Phase 4):** run `flutter
analyze` + full `flutter build apk`, install via adb, report completion.

## Session start checklist

1. Read CLAUDE.md
2. Confirm all 4 plugins/skills active
3. Report status
4. Proceed only after confirmation

## Response style

No unnecessary explanation. Stay strict to content. Minimal tokens. No preamble, no postamble, no filler confirmations beyond what's requested.

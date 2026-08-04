# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MANA LINE — a Flutter + Supabase field lending app for rural India (owner, agent, investor, customer workspaces; 5 languages). Read `README.md` first — it is current and accurate, including its "Status" and "Not yet true" sections.

**Money correctness is a safety property here.** A confidently wrong number on a collection screen is worse than a crash, because nobody notices it. Never swallow an error into a plausible value (`catch (_) => 0` on a money path). Read the comments at the top of any money file before changing it; commit messages explain *why* and are worth reading before touching money code.

## Build, run, test

```bash
flutter analyze
flutter test                     # 164 tests
flutter build apk --debug --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
flutter run -d chrome --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Supabase credentials come from `--dart-define` and live in `run.ps1.txt` (git-ignored). **Without them the app does not fail — it hangs**, because the fallback URL is a host that does not exist; symptoms are raw translation keys on every screen and login claiming "No internet connection". A "Build not configured" screen catches this in `main.dart`. Never commit credentials.

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
- One `remaining_balance` per loan; no payment waterfall; no interest accrual engine yet.

## Backend gotchas

- **Migration filenames must be `<14-digit-timestamp>_name.sql`** — anything else is silently ignored by `supabase db push` (this already happened once; full story in `supabase/MIGRATIONS.md`). Create with `supabase migration new <name>`. `supabase_migrations.schema_migrations` is the source of truth; after applying via MCP, write the local file with the *exact* stamped version or a later push re-runs it.
- **plpgsql bodies are not type-checked at CREATE time** — a broken function applies cleanly and fails on first call. Invoke it (inside a rolled-back transaction) before believing it works. Diff `pg_proc` before trusting that an RPC exists.
- **PostgREST returns 200 for an UPDATE that matches zero rows** — a silent no-op is indistinguishable from success; only a re-read or checking the returned row count proves a write landed.
- **RPCs in the `app` schema need `.schema('app').rpc(...)`** — a bare `.rpc()` targets `public` and 404s. Tables are in `public`.
- **PostgREST embeds must name the FK** when two exist between the same tables (`customers`→`business_members`, `agent_access_days`→`business_members`, `business_members`→`persons`), or PGRST201 kills the query.
- **All 67 public tables have RLS.** New tables match the existing pattern: `app.is_owner(business_id)` for owner-scoped, plus `app.is_active_agent(...)` / `app.agent_permission(...)` where agents need reach.

## Testing conventions

`flutter test` runs everything. `test/support/mana_harness.dart` pumps a whole screen with everything it expects — Riverpod scope, translation cache, secure storage, GoRouter — using the real `ManaTheme.light()`, because against Flutter's default theme the type scale differs and you'd measure a layout that doesn't exist.

- **Layout tests carry vendored translations on purpose** (`test/support/mana_translations_fixture.dart`): translated width is data, and without the fixture the "five languages" test measures narrower text than production.
- **Overflow is the recurring bug class** (shipped 4×; always a bare unflexible child beside a flexible one). It is invisible to `flutter analyze`. The harness checks it via `expectNoLayoutFault`, at text scales `[1.0, 1.3, 1.6, 2.0]` on a 360×640 surface. On device, the only reliable check is `adb logcat | grep overflowed`.
- **When a screen loads in `initState`, seed its provider** rather than letting it reach the network — otherwise the test lays out an empty state and proves nothing.

## Docs

`docs/01_Global_Rules_Guide.md` holds the locked business rules (BR-001…BR-240+); `docs/15_Calculation_Engine.md` holds the locked formulas. Per project convention, final BR and calculation-engine documents are authored at the *end* — decisions are recorded in code comments and commit messages as they are made, not by editing the specs mid-flight.

# MANA LINE

A field lending app for rural India. Owners run a lending line,
agents collects Door to Door, customers and investors see their own position.

Flutter + Supabase (Postgres, RLS, Edge Functions). Two languages:
English and Telugu.

**Money correctness is a safety property here.** A confidently wrong number
on a collection screen is worse than a crash, because nobody notices it.
Most of the conventions below exist because of a specific bug, and the
comments in the code say which one.

---

## Status

Real screens across all workspaces, wired to a live Supabase project.

| | |
|---|---|
| Screens | 57 |
| State / API files | 38 |
| Migrations applied | 79 |
| Edge Functions | 10 (auth: login, OTP, PIN, password reset) |
| Tests | 164 passing |
| `flutter analyze` | 0 issues |

Workspaces: `login_registration`, `owner_workspace`, `agent_workspace`,
`customer_workspace`, `investor_workspace`, `admin`, `support_admin`.

### Not yet true

- **No loan has ever been created on a real device.** The lending flow is
  built but unproven end to end. Until a loan exists, Collection Mode,
  penalties, Line Score and settlement are all unreachable — this is the
  single biggest gap.
- **Offline sync is not wired.** The `mana_line_offline_sync` path
  dependency is still commented out in `pubspec.yaml`.
- **Fonts are runtime-fetched.** `allowRuntimeFetching = true` in
  `main.dart`. For an app whose whole point is poor connectivity, first
  paint should not depend on a font CDN — bundle the files before shipping.

---

## Build and run

The app reads Supabase credentials from `--dart-define`. **Without them it
does not fail — it hangs**, because the fallback URL is a host that does
not exist. Symptoms are raw translation keys on every screen and a login
that reports "No internet connection". A "Build not configured" screen now
catches this case, but build it properly:

```bash
flutter build apk --debug --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Credentials live in `run.ps1.txt` (git-ignored). Never commit them.

---

## Money conventions

These are not style preferences. Each one is load-bearing.

**Every timestamp is IST.** All 87 timestamp columns are
`timestamp without time zone` — there are no `timestamptz` columns in
`public` — so a naive column is only coherent if every writer agrees which
wall clock it means. The database TimeZone is
`Asia/Kolkata`; the client writes through `manaTimestamp()` in
`lib/shared/mana_time.dart`, which derives the offset from UTC rather than
reading the handset. Before this, an audit row was observed stamped five
and a half hours in the future and a 24h lending cooldown ran ~29.5h.

**`business_date` is the Indian calendar day, deliberately.** A collection
taken at 00:30 IST belongs to that Indian business day, not the previous
UTC one. Deriving it from UTC would file money against the wrong day.

**ROI is ₹ per ₹100 per month**, not an annual percentage. Daily interest
is `principal × (roi/100) / 30`, on a 30-day month. Rounding is CEILING to
whole rupees — every money column is `numeric(_,0)`, so paise cannot be
stored.

**One `remaining_balance` per loan.** No payment waterfall; payments
subtract. There is no interest accrual engine yet.

**`loans.amount_given` is a GENERATED column** (`repayment − interest −
fee`). Never write it.

**BF is cash.** Only money that actually moved counts. Interest and fee
withheld from a disbursement never left the till, so they never return to
it as fresh cash — they arrive through the instalments. Adding them back
on top double counts. See `test/migration_loan_math_test.dart`, which pins
both the right answer and the wrong one by name.

**A cheti is an asset, not an expense.** Instalments paid in come back as
an availed lumpsum, so booking them as expenses would sink line profit
every period and then show one phantom gain. This reverses BR-061. See
`supabase/migrations/20260801192125_add_chetis.sql`.

**`day_ledger` is recomputed, never incremented.** Triggers on all eight
source tables call `app.recompute_day_ledger()`, which rebuilds the day
from scratch. Incrementing drifts — a failed retry double-counts, a
deleted row never un-counts. Backdated entries cascade forward, because
one day's closing is the next day's opening.

**BF is derived, never stored as a running total.** Both pots come out of
live rows: `app.recompute_agent_bf()` recomposes an agent's cash from its
events, and `app.recompute_business_bf()` sets
`businesses.owner_bf_balance` to the latest `day_ledger` closing minus
what the agents are holding. A grant, an agent-to-agent transfer and a
settlement handover move cash *between* pots without changing the total,
which is why none of them touch `day_ledger`.

The seed for day one is `businesses.opening_bf_declared_amount` — what
the Owner counted in the box — and never `owner_bf_balance`. Seeding from
a running total was the original defect: it drifted every time cash
moved, and `recompute_day_ledger_onward()` only walks forward, so the
seed row was never revisited. One business carried a phantom ₹10,00,000
across every ledger day this way.

The two non-negative CHECK constraints were dropped with this change. A
derived figure has to be allowed to state the truth; a recompute landing
negative would otherwise abort the delete that triggered it, and a failed
delete is a worse signal than a visible wrong balance. The pre-flight
guards inside `record_expense`, `create_loan_with_bf_check`,
`grant_agent_bf` and `record_cheti_payment` are what stop new spending
from going negative. See
`supabase/migrations/20260805035332_bf_derived_from_live_rows.sql`.

---

## Working on this repo

**The migration ledger and local filenames drift.** `supabase_migrations.
schema_migrations` is the source of truth. After applying a migration
through the MCP tool, write the local file using the *exact* stamped
version, or a later `db push` re-runs it. Diff `pg_proc` before trusting
that an RPC exists.

**plpgsql bodies are not type-checked at CREATE time.** A broken function
applies cleanly and fails on first call. Always invoke it — inside a
transaction you roll back — before believing it works.

**PostgREST returns 200 for an UPDATE matching zero rows.** A silent no-op
is indistinguishable from success. Only a re-read, or checking the
returned row count, proves a write landed.

**RPCs in the `app` schema need `.schema('app').rpc(...)`.** A bare
`.rpc()` targets `public` and 404s. Tables are in `public`.

**PostgREST embeds must name the FK** when two exist between the same
tables (`customers`→`business_members`, `agent_access_days`→
`business_members`, `business_members`→`persons`), or PGRST201 kills the
whole query.

**Never swallow an error into a plausible value.** `catch (_) => 0` on a
money screen produces a confident wrong number, which is worse than an
exception.

**All 67 public tables have RLS.** New tables match the existing pattern:
`app.is_owner(business_id)` for owner-scoped, plus
`app.is_active_agent(...)` and `app.agent_permission(...)` where agents
need reach.

---

## Testing

```bash
flutter test
flutter analyze
```

`test/support/mana_harness.dart` pumps a whole screen with everything it
expects — Riverpod scope, translation cache, secure storage, GoRouter —
using the real `ManaTheme.light()`, because against Flutter's default
theme the type scale differs and the test measures a layout that does not
exist.

**Layout tests carry vendored translations on purpose.** Translated width
is *data*. The fake cache falls back to the raw key, and raw keys are
short ASCII, so without the fixture a "five languages" test quietly
measures narrower text than production.

Overflow is invisible to `flutter analyze` and to looking at one phone at
one font size. It has shipped four times (LR-007, LR-003, LR-013, and
OW-019 — caught pre-merge, overflowing 213px at 1.0x). The recurring cause
is always the same: **a bare unflexible child beside a flexible one.**

When testing a screen that loads in `initState`, seed the provider rather
than letting it reach the network — otherwise the test lays out an empty
state and proves nothing. That mistake nearly hid the OW-019 overflow.

### Device testing

`adb` is not on PATH:
`$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.

```bash
adb -s <device> logcat -c && adb -s <device> logcat -d | grep overflowed
```

That grep is the only reliable overflow check. Screenshots are 1080x2400
and display scaled — multiply by 1.2 for real tap coordinates.

---

## Layout

```
lib/
  app/            router.dart — one route per locked screen ID
  design/         tokens (colors, typography, spacing), components, theme
  features/       login_registration, owner_workspace, agent_workspace,
                  customer_workspace, investor_workspace, admin, support_admin
  shared/         mana_time.dart, translation_service.dart, local_auth_store.dart,
                  network_error_handler.dart, settings_screen.dart
supabase/
  migrations/     79 applied
  functions/      10 Edge Functions (auth)
test/
  support/        mana_harness.dart, translation fixtures
```

`ManaText` enforces the locked Title Case standard in code rather than
leaving it to screen-by-screen memory. `ManaText.raw()` is the carve-out
for free text and system IDs.

---

## Design

Built for outdoors, one-handed, under time pressure, by people managing
cash against a paper ledger.

- **Palette** — ledger-ink `#1B2B4B` primary, brass `#C68A2E` reserved for
  primary actions. Status colours are desaturated for direct-sunlight
  legibility and map 1:1 to the spec's own vocabulary (Balanced/Short/
  Excess, Active/Penalty/Grace). No invented statuses.
- **Type** — Manrope for headers, Inter for body and data, tabular figures
  for money.
- **Signature** — the Green/Red Verification Ring (BR-191/GC-002) is the
  app's shape language. Cards use a quieter `ManaRadius.md` so the
  signature is not diluted.

---

## Specs

`docs/` holds the business rules and schema. Per project convention the
final BR and calculation-engine documents are authored at the *end* of the
project — decisions are recorded in code comments and commit messages as
they are made, not by editing the specs mid-flight. Commit messages here
explain *why*, and are worth reading before changing money code.

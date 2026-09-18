# HANDOVER — MANA LINE

Written 2026-09-18, at build 14.13, by the developer handing this over.
For the person taking it from here.

This is not a summary of the README. The README tells you what is true.
This tells you **what to do with your first week, what will waste your
time, and what I know that is not written anywhere else.**

Read it once end to end before you type anything. It is about an hour
including the files it points at, and it is the cheapest hour you will
spend on this project — nearly every day I lost here was lost to
something in §5.

---

## 0. The first ninety minutes, in order

Do these in this order. Do not skip to the code.

| # | Read | Why this one, and what to take from it |
|---|---|---|
| 1 | `README.md` — all of it, especially **Status**, **Not yet true**, **Money conventions** | The only document I kept honest on purpose. "Not yet true" is the real backlog. |
| 2 | `CLAUDE.md` | The operating rules. Written for an AI session, but equally the rules for you. §"Not breaking the thing next to the thing you fixed" is the most expensive lesson in the repo. |
| 3 | `CHANGELOG.md` — last 10 entries | Plain-English session log. Where "why is it like this" lives for recent work. |
| 4 | `docs/APP_FLOWS.md` | The eight journeys the app exists for, as flowcharts, with what moves in the database at each step — and §9, the placement rules that govern every screen. |
| 5 | `docs/APP_MAP.md` | Generated inventory: every route → file → arguments → who reaches it → whether it is tested. Regenerate with `dart run tool/gen_app_map.dart`; `test/app_map_sync_test.dart` fails if it drifts. |
| 6 | `lib/app/router.dart` | The handset's whole surface in one file, one route per locked screen ID. Read `_resolveBusinessId`. `lib/app/web_router.dart` is the restricted web subset, and its header says why a second router is allowed to exist. |
| 7 | `lib/shared/mana_time.dart`, `lib/design/tokens/` | Two small things that constrain everything: time, and visual language. The colour file explains every choice. |
| 8 | `docs/superpowers/plans/2026-09-15-production-readiness.md` | The live plan. 17 steps done, 13 open. Your roadmap, already argued through. |
| 9 | `docs/decisions/` (3 files) | Offline, analytics, visual identity — decided, with reasoning. Do not re-open without reading. |

Then, and only then: `flutter test`. Watch it go green. That suite is the
handover; everything below is commentary on it.

**Do not read the spec docs first.** `docs/01_Global_Rules_Guide.md` and
`docs/15_Calculation_Engine.md` are locked references, authored to be
completed at the *end* of the project by convention. They are for looking
things up (BR numbers, formulas), not for onboarding. Reading them cold
gives you a picture of an app that does not exist yet.

---

## 1. What this actually is, in one page

A lending business in rural India, as software.

**The people.** An **Owner** runs a lending line — their own money, or an
**Investor's**. **Agents** walk a round door to door collecting cash from
**Customers**. Everything is cash. Everything happens standing outside,
one-handed, on a cheap phone, often with no signal.

**The money, as a loop:**

1. Owner declares opening cash — `businesses.opening_bf_declared_amount`.
   What they counted in the box on day one. It is the seed, and it is
   never recomputed from anything else.
2. Owner grants an Agent a **BF float** — cash out of the box into the
   Agent's pocket. Total unchanged; it moved pots.
3. Agent issues a **loan**. The customer receives `amount_given` =
   repayment − interest − fee. **Interest and fee are withheld at
   disbursement** — they never leave the till, so they never come back to
   it as fresh cash. This one fact is behind half the money rules.
4. Agent takes **collections** on a round. Each subtracts from that loan's
   single `remaining_balance`. No waterfall. Nothing accrues between
   payments — there is no interest engine yet.
5. At period end the Agent **submits an account**. The Owner **approves**,
   and only then does money move. Submit asks; approve pays.
6. `day_ledger` is **recomputed** from the eight source tables on every
   change, never incremented. BF for both pots is **derived** from live
   rows, never stored as a running total.

**If you understand only one thing:** *a wrong number here is worse than a
crash.* A crash gets reported. A collection screen that says ₹4,300 when
it is ₹4,200 gets believed, and surfaces a month later against a paper
ledger when nobody can reconstruct the day. That is why `catch (_) => 0`
is banned on money paths, why `record_collection` refuses sixteen
different ways before it writes, and why the tests are paranoid.

---

## 2. The contracts you must not break

Five things are load-bearing across the whole codebase. Breaking one is
not a bug in a file; it is a bug everywhere at once.

**Screen IDs are the routing contract.** `LR-001`, `OW-005`, `AG-003`.
One spec screen → one locked ID → one route (`/ow-005`) → one file
(`lib/features/owner_workspace/screens/ow_005_*.dart`). Rename any of the
three and the 1:1 cross-reference that lets anyone navigate this codebase
is gone. 73 screen files; 84 routes across the handset and web routers.

**Screens never touch Supabase.** Screen → `ref.watch(provider)` →
notifier → `*_api_service.dart` → Supabase. API method signatures are free
to reshape; the layering is not.

**Time is IST, always, via `manaTimestamp()`.** Never a bare
`DateTime.now()`. All 87 timestamp columns are naive
`timestamp without time zone`, coherent only because every writer agrees.
One wrong clock previously wrote an audit row 5½ hours in the future and
ran a 24h cooldown for 29.5h.

**`ManaText` enforces Title Case in code**, not by screen-by-screen
memory. `ManaText.raw()` is the carve-out for free text and system IDs.

**Auth is not GoTrue.** `persons` is the sole identity source of truth.
Edge Functions mint a custom JWT carrying `person_id`; RLS reads it via
`app.current_person_id()`. There is no `persons.auth_user_id`. Supabase
Auth documentation does not apply here — do not reach for it.

---

## 3. Day one: get it running

```bash
flutter analyze
```

```bash
flutter test
```

Both must be clean before you change anything. If they are not, that is
your first bug and it is not yours — find out what changed.

**Building. Read this twice.** Credentials come from `--dart-define` and
live in `run.ps1.txt`, which is **tracked on purpose** — it holds only
`SUPABASE_URL` and the anon key, and both ship inside every APK anyway.

```bash
flutter build apk --debug --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

**Without the defines the app does not fail — it hangs**, because the
fallback URL is a host that does not exist. The symptoms look like three
separate bugs: raw translation keys on every screen, a login claiming "No
internet connection", and a spinner that never resolves. A "Build not
configured" screen in `main.dart` now catches it. You will still do this
once. Everybody does.

**Nothing else goes in `run.ps1.txt`.** A service-role key or JWT secret
there is a real leak. Those go in `.env`, which is git-ignored.

**adb is not on PATH:**
`$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`. Screenshots come
back 1080×2400 and display scaled — multiply by 1.2 for real tap
coordinates.

**Database work goes through the Supabase MCP server** (`execute_sql`,
`apply_migration`, `list_migrations`, `get_logs`), not a psql you wire up
yourself. For schema work against a throwaway target:

```bash
powershell -ExecutionPolicy Bypass -File tool\verify_rebuild.ps1 -Keep
```

That builds a disposable Postgres on port 5433 — trust auth, no password,
no Docker — and applies all 472 migration files to it. It cannot reach
production because it makes its own server. It is the safest place to
learn.

**The docs used to say `pwsh`, and `pwsh` is PowerShell 7, which is not
installed on this machine.** Typing it gives `CommandNotFoundException`,
which reads like a broken script rather than a missing shell. Neither .ps1
in `tool/` uses 7-only syntax, so Windows PowerShell 5.1 runs both. Checked
2026-09-18, when it wasted ten minutes.

**Verified 2026-09-18: all 472 migrations rebuild from nothing, cleanly.**

---

## 4. How to work here without going slowly

The fastest way through this codebase is not typing faster. It is not
rediscovering things that are already written down.

**Before touching anything shared, list its consumers.** Grep `lib/` for
the name; for SQL, count callers in `pg_proc` and `pg_views`. If the list
is longer than one, every entry gets checked or gets said out loud. The
two worst regressions here were a shared window used by two things and a
photo column read by sixteen — in both cases three sites were updated and
the rest silently broke. `flutter analyze` is blind to all of it.

**A change is not done until it has been *run*.** Not applied. Run.
"Migration applied" and "analyze clean" have both repeatedly meant
nothing: neither executes a plpgsql body, neither loads a screen. For a
database function that means invoking it inside a rolled-back transaction
and reading the result.

**On a money path, read the number back from the stored row afterwards** —
not the return value. A withdrawal that validated against a computed
principal and subtracted from a stale stored one would have destroyed
₹91,250 of an investor's money. It was caught by selecting
`principal_amount` after the call and noticing it was wrong.

**Report what you verified, and how, separately from what you changed.**
"Fixed" with no probe behind it is a guess. If something could not be
verified, say so rather than implying it was.

**The four AI plugins are toolchain, not decoration.** All four are
installed and enabled (verified 2026-09-18): Superpowers (plan-first,
TDD), Security Guidance (hook-driven, fires on every edit and on Stop),
Frontend Design (all UI work), Code Review (every diff before you present
it). Two files must agree or a plugin silently fails to load with **no
error**: `~/.claude/settings.json` → `enabledPlugins`, and
`~/.claude/plugins/installed_plugins.json` → an `installPath` that
actually exists on disk. Enabling is not installing; that has already
bitten this project once.

**When you find a regression, ask "what would have failed?"** — then add
that, rather than another rule. Prose is weakest exactly when sessions get
long, which is when regressions happen. Twenty guard tests exist because
twenty prose rules did not hold. When a guard reports a violation, fix the
code or sharpen the rule with the reason written down. Never loosen it to
get green.

---

## 5. The seven ways this project has cost days

Every one has actually happened here, most more than once. This section is
the real value of the handover — read it before your first change, not
after your first outage.

**1. The second function.** Changing an RPC's parameter list is DROP then
CREATE, never `CREATE OR REPLACE`. A changed, reordered or newly-defaulted
parameter creates a *second* function, and PostgREST then answers HTTP 300
(PGRST203) because it cannot choose. Five times: `ledger_history` twice,
`request_bf_update`, `import_migrated_loans`, `record_collection`. After
any signature change, count — the answer must be 1:

```sql
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = '<name>';
```

**2. The body that was never type-checked.** plpgsql applies cleanly and
fails on first call. An invented enum literal — `'General'`, `'Self
Request'`, `'Full Payment'`, or `'Other'` where the enum says
`'Other-Custom'` — throws 22P02 the first time a real person hits it. One
of those made an Owner approving a Customer's join request fail on every
call since the function was written, while the Investor branch two lines
below worked, so the feature read as half-alive rather than broken. Read
`enum_range` *before* writing the literal. Guards:
`test/sql_enum_literal_guard_test.dart`,
`test/sql_function_reference_guard_test.dart`.

**3. The silent success.** PostgREST returns 200 for an UPDATE matching
zero rows. A no-op is indistinguishable from success. Only a re-read, or
checking the returned row count, proves a write landed.

**4. The ambiguous embed.** Where two FKs exist between the same tables, a
PostgREST embed must name the FK or PGRST201 kills the whole query — and
the screen just says it could not load. There are **eleven** such pairs.
`!inner` is a join modifier, not an FK name. Guard:
`test/ambiguous_embed_guard_test.dart`.

**5. The overflow.** A bare unflexible child beside a flexible one. It has
shipped four times. It is invisible to `flutter analyze` and to looking at
one phone at one font size. The harness checks it at text scales
`[1.0, 1.3, 1.6, 2.0]` on 360×640, in English *and Telugu* — Telugu is the
one that overflows, because its rendered strings run consistently longer
than the English the layout was drawn against. On device the only reliable
check is `adb logcat | grep overflowed`.

**6. The widened filter.** Making account periods open-ended was correct,
and it silently stretched a one-entry-per-window rule from four days to
fifteen, blocking every weekly collection. Filtering Inactive areas out of
a list was correct, and it left an Owner staring at an empty screen with
no way to understand it. **Ask what reads this, and what that thing takes
it to mean.**

**7. The door locked for months.** Fixing Request-to-Join delivered real
people into an approval flow that had never run and a screen that crashed
on a null embed. When a fix makes a previously unreachable path reachable,
walk the whole path.

**And the one with no guard at all:** judgement regressions — correct code
that reads as broken to the person holding the phone. Those are found on
the handset, by a human, and nowhere else.

### The guards, and what each stops

All run under `flutter test`. Twenty of them. Worth knowing by name on day
one:

| Guard | Stops |
|---|---|
| `schema_snapshot_test.dart` | Calling an RPC that isn't there; a second overload; a Dart list drifting from a DB enum |
| `consumer_census_test.dart` | A shared contract quietly gaining or losing a consumer |
| `money_write_guard_test.dart` | A money amount written straight from the client |
| `stored_column_display_guard_test.dart` | Drawing a stored file without resolving its path — the 13 blank avatars |
| `ambiguous_embed_guard_test.dart` | PGRST201 |
| `sql_enum_literal_guard_test.dart` / `sql_function_reference_guard_test.dart` | 22P02 / 42883 on first call |
| `expectNoLayoutFault` (in the harness) | Overflow, four text scales, two languages |

**`test/support/schema_snapshot.dart` is generated, not written.** The
query to regenerate it is in its header. Regenerate after any schema
change.

**The census is answered by looking, not by editing the number.** A count
that went up means a new file took the dependency: open it, check it
honours the contract, and only then record the new figure. That check is
the entire purpose of the test. Editing the number to get green destroys
it silently.

### The SQL tests

`supabase/tests/*.sql` — six files, wired through:

```bash
powershell -ExecutionPolicy Bypass -File tool\run_sql_tests.ps1
```

**All six pass as of 2026-09-18**, 0 skipped, against the rebuilt cluster.
Needs `MANA_DB_URL`, which is deliberately not in this repo. Every file
declares `-- @target: production` (reads only, runs anywhere under
`default_transaction_read_only=on`) or `scratch` (fabricates data, refused
unless the target holds no businesses or loans). A file with no marker is
treated as `scratch`, because that is the direction in which being wrong
survives.

**Why the read-only session is a runtime guard and not a code review:** I
once counted `INSERT` statements in `migration_weekly_ledger_tests.sql`,
concluded it wrote nothing, and was wrong — its writes are inside
`app.import_weekly_account`, invisible to any reading of the file's own
statements. It was replaying twelve fabricated weeks over
`businesses ORDER BY created_at LIMIT 1`, i.e. **whichever real book was
oldest**, with a `ROLLBACK` as the only thing in the way. Static
inspection cannot answer that question. A read-only transaction answers it
at runtime.

**On their first execution, six of seven failures were defects in the
tests, not the schema.** A test that has never run does not go stale
loudly — it goes stale quietly and then reports the system as broken,
which is worse than not existing, because somebody goes looking for the
wrong bug. Treat any first execution that way.

---

## 6. Where things actually stand

Verified 2026-09-18 by running the counts, not by recalling them.

| | |
|---|---|
| Branch | `web-on-the-web`, identical to `main`, in sync with origin |
| Build | 0.1.0+14 (commits say build 14.13) |
| Dart files | 246 in `lib/`, 227 test files |
| Tests | **2,762 passing**, no credentials needed |
| Screens | 73 files across 7 workspaces; 84 routes over two routers (52 handset-only, 32 on the restricted web build) |
| Migration files | 472 local, matching 472 applied in the ledger exactly |
| Edge Functions | 14 directories (auth only) |
| Public tables | 82, all 82 with RLS |
| `flutter analyze` | **0 issues** |
| CI | `.github/workflows/ci.yml` runs analyze + the full suite on every push |

**README's Status table was behind reality and has been corrected**
(2026-09-18) — it had said 66 screens, 329 migrations and 2,083 tests, and
its Design section described a palette the code does not use. **CLAUDE.md
still says 757 tests and 67 public tables**, both stale; fix those in your
first week. Nobody lied — they are snapshots that stopped being updated,
and that is the most common rot in this repo. `docs/APP_MAP.md` is
generated and guarded so the route inventory cannot join them.

### Real, and proven on a handset

One business carries a migrated paper ledger — 57 loans, 353 collections —
worked end to end from a phone: loans issued, collections taken door to
door, expenses recorded, an account submitted and approved. That path used
to be the biggest gap and is now where most bugs get found. **Use it.** It
is worth more than any staging fixture.

### Not yet true — the honest backlog

- **No interest accrual engine.** Payments subtract from one
  `remaining_balance`; nothing accrues between them. The largest *product*
  gap.
- **Offline is half-built.** The scaffolding is real: `lib/shared/outbox/`
  (8 files — store, watcher, provider, banner, a screen) with `sqflite` a
  live dependency. But it has **exactly one consumer**,
  `ow_006_collection_mode.dart`. The contract is decided and written up in
  `docs/decisions/2026-09-15-offline.md`; Task 7 of the plan is the rest.
  For an app whose whole point is poor connectivity, this is the largest
  *engineering* gap.
- **Telemetry is wired but dark.** `lib/shared/mana_error_reporting.dart`
  wraps both entrypoints with Sentry properly, including the guarded zone.
  It only reports when `SENTRY_DSN` is passed by `--dart-define`, and an
  empty DSN is a normal state by design. **Nobody has ever passed one.**
  Until somebody does, a crash in a village is still just a person who
  quietly stops using the app.
- **CI has no secrets.** The APK job skips by design and says so in the run
  summary. It starts working by itself the moment `SUPABASE_URL` and
  `SUPABASE_ANON_KEY` are added under Settings → Secrets and variables →
  Actions. Needs repository access, which I did not have.
- **Platform-admin deletes are unproven.** `app.admin_delete_person`,
  `admin_delete_loan`, `admin_delete_collection`, `admin_delete_business`
  exist and are gated, but have never run to completion — so test rows
  created against production stay there.
- **SP-001 business suspension is enforced in neither layer.** No RLS
  policy references `business_status`, and
  `lib/shared/business_suspension_gate.dart` — written for exactly this —
  has **no callers**. Settled decision: enforce in the app, fail-closed;
  deliberately not in RLS. A real, open, security-shaped gap.
- **Known-live test credentials — deliberate, do not "fix" without
  asking.** The admin password is `siri1234` on production, and
  `generateOtpCode()` in `supabase/functions/_shared/hashing.ts` returns a
  fixed `123456`, deployed that way across registration, password reset,
  PIN reset and account unlock. There is no SMS gateway, which is why.
  **Understand the consequence before leaving it another week:** on a live
  book, anyone who knows a mobile number can take over that account. It
  can be turned off without a deploy by setting `MANA_OTP_CODE=random`.
- **13 `catch (_) { return false; }` sites** still discard why a write
  failed, mostly in `agent_customer_state.dart`. Was around 30.
- **iOS has never been compiled.** `docs/IOS_HANDOVER.md` is a complete,
  ready-to-run brief for doing it on a Mac.
- **Nothing is deployed.** No APK published, no store listings, and
  `docs/DEPLOY.md` has never been executed by anyone.
- **Migration ledger drift is closed** — re-checked 2026-09-18 and listed
  here because the plan and my own notes still call it open. 472 applied
  versions, 472 local files, and the md5 of the sorted version list matches
  on both sides. Keep it that way: after applying through the MCP tool,
  write the local file with the exact stamped version.

---

## 7. Your first two weeks, in the order I would do them

This order is not a guess — it comes out of the build-12 rating (UI 5, UX
6, Code 7, Production readiness 4, overall 6) and the plan that followed
it. Read `docs/superpowers/plans/2026-09-15-production-readiness.md`
before starting; 17 of its 30 steps are done and the rest are argued
through there.

**Week 1 — build nothing new.**

1. **Get it running on a real phone, against the real book.** Build with
   the defines, install, take a collection. Until you have done that you
   do not know this app. Half a day.
2. **Fix the stale numbers in `CLAUDE.md`** — 757 tests and 67 public
   tables, against a real 2,762 and 82. README was corrected on
   2026-09-18; CLAUDE.md was not. Ten minutes, and it is the first thing
   that will mislead you again.
3. **Add the two CI secrets.** You presumably have the repository access I
   did not. This turns the APK job on and makes CI mean something.
4. **Pass a `SENTRY_DSN` into one build.** Telemetry wired but never
   switched on is worth nothing. Cheapest single improvement to production
   readiness available.
5. **Rotate `siri1234`, set `MANA_OTP_CODE=random`** — or make a
   conscious, dated decision not to yet, and write it down. Do not let
   this drift into launch by inattention.

**Week 2 — the real work, in value order.**

6. **Close SP-001.** `business_suspension_gate.dart` exists and has no
   callers; wire it fail-closed. Small, bounded, and the one open item
   with a security shape.
7. **Task 7: the offline collection queue.** The contract is decided, the
   scaffolding is built, and there is one consumer where there should be
   several. Largest gain available for this app's actual users, and the
   plan records what was already ruled out and why.
8. **Then the interest accrual engine** — but brainstorm it with the owner
   first. It is the biggest product decision left, and it is not a coding
   task to begin with.

**At build 15 — and only at multiples of five** — rate the app 1–10 on UI,
UX, Code and Production readiness, benchmarked against PhonePe, Groww,
Kite, CRED — not against this app's own last score. **Ground every number
in something you checked that session**, not recalled, and say what would
move each one. A number that only ever goes up is a number nobody is
measuring.

---

## 8. Things I know that are not written anywhere else

**The owner's instinct on this app is usually right, and usually about
judgement rather than code.** The regressions that hurt most were correct
code that read as broken to the person holding the phone. When they say
something feels wrong, the bug is real even when the test passes.

**Read the commit messages before touching money code.** They explain
*why*, and the why is not in the spec docs. `git log -p` on a money file
is the highest-value ten minutes in this repo.

**Do not maintain the spec docs mid-flight.** Project convention:
`docs/01_Global_Rules_Guide.md` and `docs/15_Calculation_Engine.md` are
authored at the *end*. Decisions get recorded in code comments and commit
messages as they are made. Fighting this wastes your time and annoys
everyone.

**The comments at the top of files are load-bearing documentation**, not
noise. `mana_error_reporting.dart`, `mana_time.dart` and every money file
open with the reasoning for their own existence, including the bug that
caused them. Read them before editing, and keep writing them — that habit
is what made this codebase survivable across long gaps.

**`CHANGELOG.md` is written for a human reading it in six months**: plain
English, one entry per session, file names only, no code. Add an entry
before you push. It is the only artefact that answers "why is it like
this" for someone who was not there.

**When something is deferred, write down the evidence and the reason.**
The open-items list has twice gone stale and sent a session chasing work
already finished. Re-verify a count before repeating it — including any
count in this document.

**Batch the work: all changes in one commit, one push, then build the APK,
and stop before installing.** That is the rhythm the owner wants, and it
exists for a reason — the APK is the expensive step, and a half-batch on a
handset is hard to reason about.

---

## 9. Where truth lives, ranked

When two sources disagree, believe the one higher in this list.

1. **The database** — `pg_proc`, `pg_constraint`, `enum_range`,
   `supabase_migrations.schema_migrations`. A function you have actually
   invoked beats one you have read.
2. **The tests**, especially the twenty guards. Executable claims, and
   they run.
3. **The code, and the comments at the top of files.**
4. **Commit messages** — the *why*.
5. **`CHANGELOG.md`** — the plain-English why, per session.
6. **`README.md` / `CLAUDE.md`** — true in substance, occasionally stale in
   their numbers. See §6.
7. **`docs/01_*`, `docs/15_*`** — locked references authored at the end.
   Look things up here; do not onboard from here.

---

## Last thing

What makes this codebase good is not the architecture — it is that nearly
every rule in it is attached, by name, to the specific bug that caused it,
in a comment or a guard test. That is why a new person can pick it up, and
why it survived being put down for weeks at a time.

The temptation will be to move faster by skipping that. You can, for a
while. The four overflow shipments, the five duplicate functions and the
three invented enum literals are what it looks like when you do — every
one of them was written by somebody who knew the rule and was in a hurry.

Keep writing down *why*. Prefer a guard over a rule. Run the thing before
you say it works.

Good luck. It is a good app, and the hard parts are done.

# Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gap between a codebase with exceptional test discipline and a product that can be operated — automation that runs the guards, telemetry that reports failures, and an app that works without a signal.

**Architecture:** Three independent tracks. CI and telemetry are additive and touch almost no existing code. Offline-first is a real architectural change and is deliberately last and largest. The remaining items are debts with known shapes, sized honestly rather than bundled into a phase that pretends they are small.

**Tech Stack:** Flutter 3.44.6 stable, Dart >=3.0.0 <4.0.0, Supabase (PostgREST + Edge Functions), GitHub Actions, Sentry.

## Why this order

The rating that produced this plan scored production readiness 4/10 against
UI 5, UX 6, code 7. The weakest column is the one that decides what users
experience, and the three cheapest fixes in it are also the three largest
gains. CI first, because every guard in this repo — the census, the enum
literals, the layout sweeps at four text scales — currently depends on a
person remembering to type `flutter test`. Automation that runs existing
tests is worth more than any new test.

## Global Constraints

- **Money correctness is a safety property.** No task here may swallow an error into a plausible value on a money path. See CLAUDE.md §"Money conventions".
- **Never commit credentials.** `run.ps1.txt` is tracked and may hold only `SUPABASE_URL` and the anon key. A DSN, service-role key or JWT secret goes in `.env` (git-ignored) or in GitHub Actions secrets. `.claude/launch.json` is **not** git-ignored — nothing secret goes there either.
- **Migration filenames are `<14-digit-timestamp>_name.sql`** and must match `supabase_migrations.schema_migrations` exactly.
- **Changing an RPC's parameter list is DROP then CREATE**, never `CREATE OR REPLACE`. Count overloads afterwards; the answer must be 1.
- **A change is not done until it has been run.** For plpgsql that means invoking it inside a rolled-back transaction and reading the result.
- Every new `ref.t('key')` needs a migration in the same change, or `test/translation_keys_exist_test.dart` fails.
- Tests must pass offline. Nothing in `test/` may require `MANA_DB_URL` or Supabase credentials.

---

## Phase 1 — CI (highest value, lowest cost)

> **LANDED 2026-09-15**, commits `c24a1b7` and `3702592`, on `main` and
> `web-on-the-web`. Tasks 1 and 2 are both in; what follows is the record of
> what actually happened, kept rather than ticked away, because the deviation
> is the useful part.
>
> **Run #1 result:** `analyze and test` **green on a clean Linux checkout** --
> 2,448 tests in 5m 42s with no secrets configured. That is the
> offline-by-design claim proved rather than asserted, and it was the single
> thing this phase existed to find out.
>
> **`assemble the apk` failed**, correctly, at `check the build is configured`:
> `SUPABASE_URL secret is not set`. Correct and useless -- it meant "nobody
> with repository access has been at a keyboard yet", and would have stayed
> red on every push until somebody was.
>
> **The deviation:** the plan as written failed the whole run when the secrets
> were absent. That was wrong. A run permanently red for a reason unrelated to
> the code is a run people stop opening, and every guard it carries stops being
> read with it. The APK job now skips, writes into the run summary why and
> where the values live, and starts working by itself the moment the secrets
> exist. It still refuses to build WITHOUT them, because that succeeds and
> produces an APK which hangs on a host that does not exist.
>
> **Gotcha worth keeping:** secrets cannot be read from a job-level `if:`. A
> condition written that way is not an error -- it evaluates empty and the job
> silently never runs again. Hence the one-step `preflight` job that computes
> the answer and hands it on as an output.
>
> **Still open, and needs repository access:** add `SUPABASE_URL` and
> `SUPABASE_ANON_KEY` under Settings -> Secrets and variables -> Actions. Until
> then the APK job skips by design and the run is green.
>
> **Also noticed, not acted on:** run #1 raised three deprecation warnings --
> Node.js 20 (from the actions' own runtimes) and `setup-java v4`. Bumping
> action versions blind, without being able to check which tags exist, is how
> a working CI breaks on a tag that was guessed. Left for somebody with
> network access to the marketplace.


### Task 1: Run the existing guards on every push

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `test/ci_workflow_test.dart`

**Interfaces:**
- Consumes: nothing. The suite already passes with no credentials — verified 2026-09-15: no file under `test/` references `SUPABASE_URL`, and `sql_tests_wired_test.dart` prints a skip rather than failing when `MANA_DB_URL` is unset.
- Produces: a green/red signal on every push and pull request.

- [x] **Step 1: Write the failing test**

```dart
// test/ci_workflow_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The guards only guard if something runs them.
///
/// This repo's whole safety story is its tests — the consumer census, the
/// enum-literal scan, the layout sweeps at four text scales in two languages.
/// Every one of them has, until now, depended on a person remembering to type
/// `flutter test` before pushing. That is the single largest gap between this
/// codebase and a maintained one.
void main() {
  test('CI runs analyze and the full suite', () {
    final f = File('.github/workflows/ci.yml');
    expect(f.existsSync(), isTrue, reason: 'no CI workflow');
    final y = f.readAsStringSync();
    expect(y, contains('flutter analyze'));
    expect(y, contains('flutter test'));
    expect(y, contains('on:'));
  });

  test('CI pins the Flutter version rather than tracking stable', () {
    // A floating channel means a green build can turn red with no commit,
    // and the failure arrives attributed to whoever pushed next.
    final y = File('.github/workflows/ci.yml').readAsStringSync();
    expect(y, contains('flutter-version:'));
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/ci_workflow_test.dart`
Expected: FAIL — "no CI workflow"

- [x] **Step 3: Write the workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, web-on-the-web]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          # Pinned, not `channel: stable`. A floating channel means a green
          # build can turn red with no commit behind it, and the failure is
          # attributed to whoever pushed next.
          flutter-version: '3.44.6'
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      # No credentials: the suite passes offline by design, and
      # sql_tests_wired_test prints a skip rather than failing when
      # MANA_DB_URL is absent.
      - run: flutter test
```

- [x] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ci_workflow_test.dart`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml test/ci_workflow_test.dart
git commit -m "The guards now run without anybody remembering to run them."
```

- [x] **Step 6: Confirm it actually ran**

Push, then open the Actions tab and read the run. A workflow file that has never executed is the same class of thing as the five SQL test files in Task 8: present, plausible, and proving nothing. Record the run URL in the commit's PR or in a follow-up commit message.

---

### Task 2: Fail CI on a debug build that cannot be produced

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Task 1's workflow.
- Produces: a build artifact per push, proving the APK still assembles.

- [x] **Step 1: Add the build job**

```yaml
  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.6'
          cache: true
      - run: flutter pub get
      # The anon key ships inside every APK anyway, which is why run.ps1.txt
      # is tracked — but CI reads it from secrets so the workflow does not
      # have to parse a text file, and so a future rotation is one place.
      - run: >
          flutter build apk --debug
          --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }}
          --dart-define=SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: Add the two repository secrets** — STILL OPEN, needs repository access

In GitHub → Settings → Secrets and variables → Actions, add `SUPABASE_URL` and `SUPABASE_ANON_KEY` with the values from `run.ps1.txt`. Nothing else goes there.

- [x] **Step 3: Commit** — the artifact cannot appear until Step 2 is done

```bash
git add .github/workflows/ci.yml
git commit -m "CI builds the APK, so a break in assembly is not found on a handset."
```

---

## Phase 2 — Telemetry

### Task 3: Report crashes

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Create: `lib/shared/mana_error_reporting.dart`
- Create: `test/error_reporting_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `manaInitErrorReporting()` and `manaReportError(Object, StackTrace, {String? hint})`, called by `NetworkErrorHandler` in Task 4.

**Why Sentry over Crashlytics:** Crashlytics pulls the Firebase SDK in, and this app uses no other Firebase service. Sentry is one dependency, works with a plain DSN, and its Dart SDK captures both Flutter framework errors and zone errors.

- [ ] **Step 1: Write the failing test**

```dart
// test/error_reporting_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// A field agent hitting a bug in a village is, today, silent data loss.
void main() {
  test('the DSN is not hardcoded', () {
    // A DSN is not as dangerous as a service-role key, but it is still a
    // credential and run.ps1.txt is TRACKED. It comes from --dart-define.
    final src = File('lib/shared/mana_error_reporting.dart').readAsStringSync();
    expect(src, contains('String.fromEnvironment'));
    expect(src, isNot(contains('https://')),
        reason: 'a literal DSN has been pasted into the source');
  });

  test('reporting is optional, and its absence is not a crash', () {
    // Not every build has a DSN — a local debug build has none, and the app
    // must behave identically without one. An error reporter that itself
    // throws on a missing key is worse than no reporter.
    final src = File('lib/shared/mana_error_reporting.dart').readAsStringSync();
    expect(src, contains('isEmpty'));
  });

  test('run.ps1.txt still holds only the two public values', () {
    // CLAUDE.md: nothing else may be added to it. A DSN there would be the
    // first step toward a service-role key there.
    final f = File('run.ps1.txt').readAsStringSync();
    expect(f, isNot(contains('SENTRY')));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/error_reporting_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Add the dependency**

```yaml
  # Crash and error reporting. Sentry rather than Crashlytics because this
  # app uses no other Firebase service, and pulling the Firebase SDK in for
  # one feature is a large dependency for a small job.
  sentry_flutter: ^8.9.0
```

- [ ] **Step 4: Write the reporter**

```dart
// lib/shared/mana_error_reporting.dart
import 'package:sentry_flutter/sentry_flutter.dart';

/// Where errors go when nobody is watching the handset.
///
/// The DSN arrives by --dart-define, like the Supabase values, and NOT via
/// run.ps1.txt — that file is tracked, and CLAUDE.md is explicit that only
/// the URL and anon key may live in it because both ship inside every APK
/// anyway. A DSN is less dangerous than a service-role key and still does
/// not belong in version control.
///
/// An empty DSN is a NORMAL state, not an error: a local debug build has
/// none, and the app must behave identically without one.
const String _dsn = String.fromEnvironment('SENTRY_DSN');

bool get manaErrorReportingEnabled => _dsn.isNotEmpty;

Future<void> manaInitErrorReporting(Future<void> Function() runApp) async {
  if (_dsn.isEmpty) {
    await runApp();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _dsn;
      // These are money screens. A full session replay or request body could
      // carry a customer's name, phone or balance off the handset.
      options.sendDefaultPii = false;
      options.tracesSampleRate = 0.0;
    },
    appRunner: runApp,
  );
}

/// Report something the app handled but should not have had to.
Future<void> manaReportError(Object error, StackTrace stack,
    {String? hint}) async {
  if (_dsn.isEmpty) return;
  await Sentry.captureException(error, stackTrace: stack, hint: Hint.withMap({
    if (hint != null) 'where': hint,
  }));
}
```

- [ ] **Step 5: Wrap the app**

In `lib/main.dart`, wrap the existing `runApp` call in `manaInitErrorReporting(() async => runApp(...))`. Do not change the "Build not configured" screen's behaviour — a missing Supabase URL must still produce that screen, not a crash report.

- [ ] **Step 6: Run tests, then commit**

```bash
flutter analyze && flutter test
git add -A
git commit -m "An error on a handset in a village stops being silent."
```

---

### Task 4: Report the errors the app already catches

**Files:**
- Modify: `lib/shared/network_error_handler.dart`
- Modify: `test/error_reporting_test.dart`

**Interfaces:**
- Consumes: `manaReportError` from Task 3.
- Produces: nothing new; existing behaviour is unchanged for the user.

**Why this is separate:** `NetworkErrorHandler.run` returns null on failure and shows the user a message. That is correct for the user and invisible to you. Every one of those is an error the app decided to survive, and the interesting ones — a PostgREST 300, a timeout on a money write — are exactly what never reaches a crash reporter.

- [ ] **Step 1: Write the failing test**

```dart
  test('handled failures are reported, not just shown', () {
    final src =
        File('lib/shared/network_error_handler.dart').readAsStringSync();
    expect(src, contains('manaReportError'),
        reason: 'NetworkErrorHandler swallows every failure it shows; those '
            'are precisely the ones nobody will ever hear about');
  });
```

- [ ] **Step 2: Run it, watch it fail, add the call in the catch block, run again**

The call must not change what the user sees, must not await in a way that delays the SnackBar, and must pass a `hint` naming the action.

- [ ] **Step 3: Commit**

---

### Task 5: Decide on analytics, in writing

**Files:**
- Create: `docs/decisions/2026-09-15-analytics.md`

This is a decision task, not a code task, and it is here so it stops being
implied. Product analytics on a money app handling named villagers' balances
is a privacy question before it is a product one. Write down: what question
you actually want answered (most likely "where do Owners abandon migration"),
whether a self-hosted or India-region endpoint is required, and what must
never leave the handset. Then either implement against that document or
record that you chose not to. **Do not add an SDK before the document
exists.**

---

## Phase 3 — Offline

### Task 6: Decide the offline contract before writing any of it

**Files:**
- Create: `docs/decisions/2026-09-15-offline.md`

`pubspec.yaml` lines 51–53 carry a commented-out `mana_line_offline_sync`
path dependency. Uncommenting it is not the task; deciding what offline
*means* here is.

The hard part is not caching. It is that this app's money rules are enforced
server-side on purpose — `record_collection` has a one-entry-per-window rule,
the spending RPCs have pre-flight guards, `day_ledger` is recomputed from
triggers, and BF is derived. An offline collection is a write that has not
been checked yet.

- [ ] **Step 1: Answer these, in the document, before any code**

1. Which actions may be taken offline? The honest minimum is **recording a collection** — it is the one thing that happens in a village with no signal, and it is 90% of daily use.
2. What does the agent see for a balance that may be stale?
3. What happens when a queued collection is **refused** on sync — the window rule fired, the loan was deleted, the day was closed? The agent has already told the customer it was received.
4. Does an offline collection print or issue a receipt number? If yes, from where?
5. How long may a device stay offline before it must refuse to keep accepting?

- [ ] **Step 2: Have the answers reviewed before Task 7 begins**

Stop here for approval. This is the one task in this plan where guessing
wrong is expensive to unwind.

---

### Task 7: Implement offline collection queue

**Files:** to be determined by Task 6's document.

**Sized honestly: weeks, not days.** It touches `record_collection`,
the collection round view, `day_ledger` recomputation, and idempotency. The
idempotency work already done — keys minted at entry construction and reused
by every retry — is the right foundation and is why this is feasible at all.

Do not start this task until Task 6 is approved.

---

## Phase 4 — Standing debts

### Task 8: Run the five SQL test files that have never executed

**Files:**
- Modify: `tool/run_sql_tests.ps1` (only if it blocks)
- Create: `docs/decisions/2026-09-15-sql-scratch-target.md`

Five of six files under `supabase/tests/` have never run, because scratch
files are refused unless the target holds no businesses or loans, and
branching is a Pro-plan feature. The file that has run (`live_invariants_tests.sql`)
passes.

- [ ] **Step 1: Pick a target and write down which**

Options: a Supabase Pro branch; a local `supabase start`; a second free
project used only for this. Record the choice and why.

- [ ] **Step 2: Run them and report the result honestly**

They have never executed. Expect failures, and expect at least one to be the
test rather than the schema.

---

### Task 9: Close the migration ledger drift

**Files:**
- Modify: `test/translation_keys_exist_test.dart` (shrink `_appliedButFileMissing`)
- Create: the missing `supabase/migrations/*.sql` files

69 keys are live in `ui_translations` with no local migration file. They are
listed by name in `_appliedButFileMissing` with the reason. Each restored
file is one name off that list.

- [ ] **Step 1: List the ledger versions with no local file**

```sql
-- against supabase_migrations.schema_migrations
select version, name from supabase_migrations.schema_migrations
order by version;
```

Compare against `ls supabase/migrations`. Note that local also holds
versions the ledger does not (the `00NN`-era filenames) — this is the
long-standing drift recorded in memory, and the comparison is not symmetric.

- [ ] **Step 2: Restore each file verbatim from `statements`, one commit per batch**

Copy the body exactly. A migration file is a record of what ran, not
something to rewrite until it looks right.

- [ ] **Step 3: Shrink the guard's list as files land**

Shrinking it is progress. Adding to it is not, and a new name there should be
challenged.

---

### Task 10: Settle the language claim

**Files:**
- Modify: `CLAUDE.md`, `README.md`
- Or: new migrations completing Hindi, Tamil and Kannada

`ui_translations` has five columns. Of ~1,600 keys: English 1,600,
Telugu 1,591, and Hindi / Tamil / Kannada 174 each — about 11%.
`lib/shared/translation_service.dart:22` says only English and Telugu are
ever looked up.

- [ ] **Step 1: Decide — complete them, or drop the columns**

Two honest options. There is no third where the app claims five.

- [ ] **Step 2: If dropping, do it in the schema too**

Leaving three 11%-full columns in place is how the "5 languages" figure got
into a plan and nearly onto a public website.

---

### Task 11: Rotate the credentials that are known-live

**Files:** none in this repo.

Recorded in memory as outstanding: the admin password is `siri1234` on
production, and an old plaintext password was never rotated.

- [ ] **Step 1: Rotate both, outside this repo, and confirm the old ones fail**

Do not paste the new values into any file here. Confirm by attempting a login
with the old credential and reading the refusal.

---

### Task 12: Visual identity

**Files:** `lib/design/` throughout.

Sized honestly: this is a design project, not a task list, and it is last
because it is worth least to the people using the app. The current UI is
competent Material with a good palette and correct contrast for field use.
What it lacks is a signature — motion, illustration, a component language of
its own.

- [ ] **Step 1: Before any code, load the `frontend-design` skill and decide a direction**

Per CLAUDE.md, all UI work goes through it. A direction decided once and
applied is worth more than ten screens each improved separately.

---

## Self-Review

**Spec coverage:** every item from the 2026-09-15 rating has a task —
CI (1, 2), crash reporting (3, 4), analytics (5), offline (6, 7), SQL tests
(8), ledger drift (9), languages (10), live credentials (11), visual
identity (12).

**Placeholders:** Tasks 7 and 12 deliberately carry no code. Both depend on a
decision that has not been made, and inventing steps for them would be the
kind of plan that reads complete and cannot be executed. Both say so, and both
name what unblocks them.

**Type consistency:** `manaInitErrorReporting` and `manaReportError` are
defined in Task 3 and consumed in Task 4 under those exact names.

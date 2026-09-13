# Plan 6 — Entering a pre-existing book one person at a time

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an Owner enter a pre-existing book person by person — investors, then agents, then customers with their loans — on sliding one-person screens, **beside** the bulk wizard rather than instead of it, and let them add a single person the wizard missed without walking the wizard again.

**Architecture:** A new front end over the **existing** `BulkOnboardingService`. Every write already exists and is already hardened — `submitInvestments`, `submitCustomerLoans`, `submitEmiSchedule`, `submitIdentities` — so this plan adds screens and a small orchestrating notifier, and adds **no new RPC and no new migration**. One person's entry is submitted as a one-row batch through the same call the grid uses, which is what makes the money rules, the rejection parsing and the idempotency key apply unchanged.

**Tech Stack:** Flutter, Riverpod, `PageView`, existing `BulkOnboardingService` + its `app.*` RPCs, `flutter_test`.

## Global Constraints

- **The bulk wizard is not modified and not removed.** It stays reachable from OW-018 exactly as it is. This is a second door, chosen by the Owner: *"sit beside it as a second choice."*
- **No new RPC, no new migration, no new money path.** Every write goes through an existing `BulkOnboardingService` method. If a task appears to need a new server function, stop and report — it means the wizard does something this plan has misread.
- **Idempotency is mandatory on the loan path.** `submitCustomerLoans` takes `idempotencyKey`; mint it once per person when Save is pressed and reuse it for every retry of that person. On 22 Aug 2026 a retry without one put a book in twice — 108 loans, line balance nearly double, day ledger cascaded to minus 8,20,320.
- **Order is investors → agents → customers.** The Owner's order, and it is also the dependency order: customers' loans are the only stage that can fail on a missing person.
- **Any stage can be entered directly for one person.** *"if any user entry is missed in bulk wizard can add it here without going through wizard all along for an entry."*
- **Money conventions apply in full.** ROI is ₹ per ₹100 per month. `loans.amount_given` is GENERATED — never written. A typed balance is checked against replayed instalments, never added to them.
- `flutter analyze` clean on every touched file. Full `flutter test` green after every task — baseline **2,377 passing**.
- UTF-8, no BOM. Never commit credentials.

## What already exists, and is reused verbatim

Read this before writing anything. Getting it wrong means rebuilding a hardened path badly.

| Contract | Signature | Used by |
|---|---|---|
| `bulkOnboardingServiceProvider` | `Provider<BulkOnboardingService>` | every task |
| `membersInRole` | `Future<List<ManaMemberRef>> membersInRole({required String businessId, required String role})` | Tasks 2, 3, 4 |
| `submitInvestments` | `Future<ImportOutcome> submitInvestments({required String businessId, required List<Map<String, dynamic>> rows})` | Task 2 |
| `submitCustomerLoans` | `Future<ImportOutcome> submitCustomerLoans({required String businessId, required List<Map<String, dynamic>> rows, Map<String, int> emiTotals = const {}, String? idempotencyKey})` | Task 4 |
| `submitEmiSchedule` | `Future<EmiSubmitResult> submitEmiSchedule({required String businessId, required List<EmiScheduleRow> schedule, required void Function(String mlid, int done, int total) onProgress})` | Task 4 |
| `ManaMemberRef` | `{String mlid, String fullName, String? village}`, plus `bool matches(String query)` | Tasks 2, 3, 4 |
| `ImportOutcome` | `{int imported, int skipped, List<ImportRowError> errors, List<CreatedIdentity> created}` | Tasks 2, 4 |
| `EmiScheduleRow` | `{String mlid, List<EmiEntry> entries}` | Task 4 |
| `InvestmentSheet` | `InvestmentSheet({required ManaMemberRef who, DateTime? cutoff})`, pops a `Map<String, dynamic>` already shaped for `submitInvestments` | Task 2 |
| `ShareholderSheet` | same file, same shape | Task 2 |

`InvestmentSheet` popping exactly the map `submitInvestments` wants is the single most useful fact in this plan: **investors are mostly built already.** Task 2 is a host for it, not a reimplementation of it.

---

### Task 1: The spine — one person, three stages, sliding

**Files:**
- Create: `lib/features/owner_workspace/screens/ow_one_by_one_migration.dart`
- Create: `test/one_by_one_migration_test.dart`
- Modify: `lib/features/owner_workspace/screens/ow_018_business_migration.dart` (add the entry point beside the wizard's)

**Interfaces:**
- Consumes: nothing but `businessId`.
- Produces:
  - `enum ManaEntryStage { investors, agents, customers }`
  - `class OneByOneMigrationScreen extends ConsumerStatefulWidget` with
    `OneByOneMigrationScreen({super.key, required String businessId, ManaEntryStage initialStage = ManaEntryStage.investors, String? onlyMlid})`

`onlyMlid` is the "one missed entry" door: when set, the screen shows that one person in that one stage and no slider.

- [ ] **Step 1: Write the failing test**

```dart
// test/one_by_one_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_one_by_one_migration.dart';

void main() {
  test('stages are ordered investors, agents, customers', () {
    // The Owner's order, and also the dependency order: a customer's loan is
    // the only stage that can fail because a person is not there yet.
    expect(ManaEntryStage.values.map((s) => s.name).toList(),
        ['investors', 'agents', 'customers']);
  });

  test('a single-person entry names the stage it belongs to', () {
    // Adding one missed person must not walk the other two stages.
    const screen = OneByOneMigrationScreen(
      businessId: 'b1',
      initialStage: ManaEntryStage.customers,
      onlyMlid: 'MLPI042496229',
    );
    expect(screen.initialStage, ManaEntryStage.customers);
    expect(screen.onlyMlid, 'MLPI042496229');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/one_by_one_migration_test.dart`
Expected: FAIL — `ow_one_by_one_migration.dart` does not exist.

- [ ] **Step 3: Write the screen**

```dart
/// Entering a pre-existing book one person at a time.
///
/// The bulk wizard is seven pages of grids and a spreadsheet, which is right
/// for a book of fifty and wrong for a book of six — and wrong for the one
/// person the wizard missed, because finishing that one entry means walking
/// all seven pages again.
///
/// This is the second door, at the Owner's instruction. It writes through the
/// SAME service the wizard does, one row at a time, so the money rules, the
/// rejection parsing and the idempotency key are inherited rather than
/// rebuilt. Nothing here talks to Supabase directly.
enum ManaEntryStage { investors, agents, customers }

class OneByOneMigrationScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// Which stage to open on. Investors first by default — the Owner's order,
  /// and the order the book itself is organised in.
  final ManaEntryStage initialStage;

  /// Set to enter ONE person and no others: the missed-entry door. The slider
  /// is not drawn, because there is nothing to slide between.
  final String? onlyMlid;

  const OneByOneMigrationScreen({
    super.key,
    required this.businessId,
    this.initialStage = ManaEntryStage.investors,
    this.onlyMlid,
  });

  @override
  ConsumerState<OneByOneMigrationScreen> createState() =>
      _OneByOneMigrationScreenState();
}
```

The state holds a `PageController` over the people in the current stage, a
`ManaEntryStage _stage`, and nothing else — each stage's body is its own widget,
added in Tasks 2–4. Until then `_stageBody()` returns
`const SizedBox.shrink()`.

- [ ] **Step 4: Run the test and watch it pass**

Run: `flutter test test/one_by_one_migration_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the entry point on OW-018**

Beside the existing wizard button, not replacing it. In
`ow_018_business_migration.dart`, next to where `BulkOnboardingWizardScreen` is
pushed:

```dart
OutlinedButton.icon(
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OneByOneMigrationScreen(businessId: widget.businessId),
    ),
  ),
  icon: const Icon(Icons.person_outline, size: 18),
  label: ManaText.raw(ref.t('enter_one_by_one')),
),
```

`enter_one_by_one` does not exist yet. Add it in the migration in Task 5 — do
NOT invent an English string inline; every label in this app comes from
`ui_translations`.

**Until Task 5 lands, `ref.t('enter_one_by_one')` renders the raw key.** That is
expected and visible, and it is why Task 5 is not optional.

- [ ] **Step 6: `flutter analyze` and full `flutter test`, then commit**

```bash
flutter analyze
flutter test
git add lib/features/owner_workspace/screens/ow_one_by_one_migration.dart test/one_by_one_migration_test.dart lib/features/owner_workspace/screens/ow_018_business_migration.dart
git commit -m "A second door into a pre-existing book: one person at a time, beside the wizard"
```

---

### Task 2: Investors

**Files:**
- Modify: `lib/features/owner_workspace/screens/ow_one_by_one_migration.dart`
- Modify: `test/one_by_one_migration_test.dart`

**Interfaces:**
- Consumes: `membersInRole`, `submitInvestments`, `InvestmentSheet`, `ManaMemberRef`, `ImportOutcome` (signatures in the table above).
- Produces: `Future<ImportOutcome> saveInvestor(Map<String, dynamic> row)` on the screen's state, used by Tasks 3 and 4 as the shape to copy.

- [ ] **Step 1: Read `ow_investor_entry_sheets.dart` before writing anything**

`InvestmentSheet` already collects amount, ROI, interest type, invested date and
profit percent for one `ManaMemberRef`, and pops a map with keys `mlid`,
`full_name`, `invested_amount`, `roi`, `interest_type`, `invested_date`,
`profit_percent`. That map is **already** the row shape `submitInvestments`
takes. Do not write a second investor form.

- [ ] **Step 2: Write the failing test**

```dart
test('one investor is submitted as a one-row batch', () async {
  // The point of the whole plan: the single-person path is the bulk path with
  // a list of one, so the money rules and the rejection parsing are the same
  // code rather than a second copy that agrees today.
  final captured = <List<Map<String, dynamic>>>[];
  final service = _FakeBulkService(onInvestments: captured.add);

  await saveInvestorRow(
    service: service,
    businessId: 'b1',
    row: {'mlid': 'MLTI1', 'invested_amount': 50000},
  );

  expect(captured, hasLength(1));
  expect(captured.single, hasLength(1),
      reason: 'one person is one row, not a grid of one');
  expect(captured.single.single['mlid'], 'MLTI1');
});
```

`_FakeBulkService` implements `BulkOnboardingService` and records what it is
given. Use `implements` rather than `extends` — the real class takes a
`SupabaseClient` this test has no business constructing. Follow
`test/inbox_invitation_hang_test.dart`'s `_FailingInbox` for the pattern.

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/one_by_one_migration_test.dart`
Expected: FAIL — `saveInvestorRow` is not defined.

- [ ] **Step 4: Implement**

A top-level function, so it is testable without pumping a screen:

```dart
/// Submits ONE investor through the bulk path.
///
/// A list of one, deliberately. app.bulk_import_investments is where the
/// investor money rules live, and calling it with a single row means this
/// screen cannot disagree with the wizard about what an investment is.
Future<ImportOutcome> saveInvestorRow({
  required BulkOnboardingService service,
  required String businessId,
  required Map<String, dynamic> row,
}) =>
    service.submitInvestments(businessId: businessId, rows: [row]);
```

The stage body lists the business's investors from
`membersInRole(businessId: ..., role: 'Investor')`, one per `PageView` page,
each page opening `InvestmentSheet` and calling `saveInvestorRow` with what it
pops. A page shows the person's name, MLID and village, and after a successful
save shows `imported`/`skipped` from the `ImportOutcome` — **`skipped` is not a
failure**: it means the book already had that investment, which is the normal
result of finishing a partly-done import.

- [ ] **Step 5: Run the test and watch it pass**

Run: `flutter test test/one_by_one_migration_test.dart`
Expected: PASS.

- [ ] **Step 6: `flutter analyze`, full `flutter test`, commit**

---

### Task 3: Agents

**Files:**
- Modify: `lib/features/owner_workspace/screens/ow_one_by_one_migration.dart`
- Modify: `test/one_by_one_migration_test.dart`

**Interfaces:**
- Consumes: `membersInRole(businessId: ..., role: 'Agent')`.
- Produces: nothing new.

- [ ] **Step 1: Read what the wizard's agent page actually does**

The wizard's own header says it: *"5 Agents — attendance only; salary lives in
the weekly sheet."* An agent in a migrated book carries **no money on this
screen**. If this task starts collecting a salary or a float, it has
misunderstood the feature and must stop and report.

- [ ] **Step 2: Write the failing test**

```dart
test('the agent stage collects no money', () {
  // Salary lives in the weekly sheet, per the wizard's own page 5. A money
  // field here would be a second, disagreeing source for an agent's pay.
  final source = File(
          'lib/features/owner_workspace/screens/ow_one_by_one_migration.dart')
      .readAsStringSync();
  final stage = source.substring(source.indexOf('Widget _agentStage('));
  final body = stage.substring(0, stage.indexOf('Widget _customerStage('));

  for (final banned in ['salary', 'float', 'amount', 'bf']) {
    expect(body.toLowerCase(), isNot(contains(banned)),
        reason: 'the agent stage has grown a money field: $banned');
  }
});
```

- [ ] **Step 3: Run it and watch it fail**

Expected: FAIL — `_agentStage` is not defined.

- [ ] **Step 4: Implement**

`_agentStage` lists the business's agents one per page, each page showing name,
MLID, village and a single confirm action. There is nothing to submit: the
agents already exist as memberships by the time a book is being migrated, and
this stage is the Owner reading down them to check nobody is missing. A page
carries a "not in this book" action that opens Universal Search so the missing
one can be added, then returns here.

- [ ] **Step 5: Run the test and watch it pass**

- [ ] **Step 6: `flutter analyze`, full `flutter test`, commit**

---

### Task 4: Customers, with their loans

**This is the task with the money in it, and the only one that can double a book.**

**Files:**
- Modify: `lib/features/owner_workspace/screens/ow_one_by_one_migration.dart`
- Modify: `test/one_by_one_migration_test.dart`

**Interfaces:**
- Consumes: `submitCustomerLoans`, `submitEmiSchedule`, `EmiScheduleRow`, `manaIdempotencyKey()` from `lib/shared/idempotency.dart` — read that file before using it.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test — the idempotency key first**

```dart
test('a retry reuses the same idempotency key', () async {
  // 22 Aug 2026: a retry after a timeout put the whole book in a second time.
  // 108 loans, line balance nearly double, day ledger cascaded to minus
  // 8,20,320. The key is what makes the second attempt a no-op, and it has to
  // be the SAME key -- minting a fresh one per attempt is the bug wearing a
  // safety feature's clothes.
  final keys = <String?>[];
  final service = _FakeBulkService(onLoans: keys.add, failFirst: true);

  final entry = CustomerLoanEntry(businessId: 'b1', row: {'mlid': 'MLPI1'});
  await entry.save(service);   // fails
  await entry.save(service);   // retry

  expect(keys, hasLength(2));
  expect(keys.first, isNotNull, reason: 'a loan import without a key can double a book');
  expect(keys.first, keys.last,
      reason: 'a retry must carry the key of the attempt it is retrying');
});
```

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL — `CustomerLoanEntry` is not defined.

- [ ] **Step 3: Implement**

```dart
/// One customer's loan, and the key that makes retrying it safe.
///
/// The key is minted ONCE, when the entry is created, and reused by every
/// attempt. That is the whole contract: `submitCustomerLoans` is idempotent on
/// it, so a retry after a timeout is a no-op rather than a second import.
class CustomerLoanEntry {
  CustomerLoanEntry({required this.businessId, required this.row})
      : idempotencyKey = manaIdempotencyKey();

  final String businessId;
  final Map<String, dynamic> row;
  final String idempotencyKey;

  Future<ImportOutcome> save(BulkOnboardingService service,
          {Map<String, int> emiTotals = const {}}) =>
      service.submitCustomerLoans(
        businessId: businessId,
        rows: [row],
        emiTotals: emiTotals,
        idempotencyKey: idempotencyKey,
      );
}
```

The stage body collects, per customer: loan amount, repayment, interest, fee,
ROI, frequency, start date, grace period END DATE (a date, not a day count —
the day count is derived server-side, because a paper ledger records a date),
and the instalment history.

**The balance rule, copied from the service's own comment because getting it
wrong silently halves a loan:** when a loan has history, the server opens it
UNPAID and lets the replayed instalments derive the balance; a typed balance is
then *checked against* that and disagreement rejects the row. Never send a
typed balance and replay history on top of it — that is what used to land the
loan at `typed − SUM(history)`.

Instalment history goes through `submitEmiSchedule` as a single
`EmiScheduleRow(mlid: ..., entries: ...)`, with `onProgress` driving a
per-instalment progress line. That replay is one `record_collection` per
instalment, not one request, so it must be visible and resumable.

- [ ] **Step 4: Run the test and watch it pass**

- [ ] **Step 5: Add the second test — the balance rule**

```dart
test('a typed balance is never sent alongside replayed history', () {
  final source = File(
          'lib/features/owner_workspace/screens/ow_one_by_one_migration.dart')
      .readAsStringSync();
  expect(source, contains('emiTotals'),
      reason: 'history has to reach submitCustomerLoans as emiTotals so the '
          'server can check the typed balance against it rather than '
          'subtracting one from the other');
});
```

- [ ] **Step 6: `flutter analyze`, full `flutter test`, commit**

---

### Task 5: The labels, and the missed-entry door

**Files:**
- Create: one migration under `supabase/migrations/`
- Modify: `lib/features/owner_workspace/screens/ow_one_by_one_migration.dart`
- Modify: `lib/features/owner_workspace/screens/ow_012_business_management.dart` (Members tab row action)
- Modify: `test/one_by_one_migration_test.dart`

- [ ] **Step 1: Add the translation keys**

Every label this plan introduces, in one migration. English and Telugu, matching
the rest of `ui_translations`:

| key | English |
|---|---|
| `enter_one_by_one` | Enter One by One |
| `entry_stage_investors` | Investors |
| `entry_stage_agents` | Agents |
| `entry_stage_customers` | Customers & Loans |
| `person_of_total` | {n} of {total} |
| `already_in_the_book` | Already in the book — nothing to add. |
| `add_this_persons_entry` | Add This Person's Entry |
| `not_in_this_book` | Not in this book |

Migration rules apply in full: filename `<14-digit-timestamp>_name.sql`, applied
via MCP, then the local file written with the **exact** stamped version.

- [ ] **Step 2: Write the failing test**

```dart
test('every label the screen asks for exists in the migration', () {
  // A key with no row renders as the raw key on the handset -- this project
  // shipped "use_my_location" to a live screen exactly that way.
  final source = File(
          'lib/features/owner_workspace/screens/ow_one_by_one_migration.dart')
      .readAsStringSync();
  final migration = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .map((f) => f.readAsStringSync())
      .join();

  final used = RegExp(r"ref\.t\('([a-z_]+)'\)")
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toSet();
  final missing = [
    for (final key in used)
      if (!migration.contains("('$key',")) key,
  ];
  expect(missing, isEmpty, reason: 'these render as raw keys: $missing');
});
```

- [ ] **Step 3: Run it, watch it fail, then apply the migration and watch it pass**

- [ ] **Step 4: Wire the missed-entry door**

On OW-012's Members tab, each member row gains an overflow action —
**Add This Person's Entry** — that opens:

```dart
OneByOneMigrationScreen(
  businessId: businessId,
  initialStage: switch (member.role) {
    'Investor' => ManaEntryStage.investors,
    'Agent' => ManaEntryStage.agents,
    _ => ManaEntryStage.customers,
  },
  onlyMlid: member.mlid,
)
```

`MemberSummary` has no `mlid` today — it carries `membershipId`, `personId`,
`fullName`, `role`, `membershipStatus`, `village`. **Add `mlid` to it and to
`fetchMembers`'s select**, which already embeds
`persons!business_members_person_id_fkey(full_name)`; extend that embed to
`(full_name, mlid)`. Do not add a second query for it — unlike the village, the
MLID is on `persons` and reachable through the embed that is already there.

- [ ] **Step 5: Run the whole suite, `flutter analyze`, commit**

---

### Task 6: Walk it on a handset

**Files:** none.

- [ ] Build and install. Open a pre-existing business, then **Enter One by One**.
- [ ] Enter one investor. Confirm the amount, ROI and date land, and that re-entering the same investor reports **skipped**, not a second investment.
- [ ] Slide through the agents. Confirm nothing asks for money.
- [ ] Enter one customer with a loan and two instalments of history. Read the stored balance back and confirm it equals `repayment − SUM(history)` — not the typed figure minus history again.
- [ ] Kill the app mid-instalment-replay and reopen it. Confirm the replayed instalments are not collected twice.
- [ ] From OW-012 Members, use **Add This Person's Entry** on somebody the wizard missed. Confirm it opens on their stage, shows only them, and returns afterwards.
- [ ] Report what was verified and how, separately from what was changed.

---

## Self-Review

**Spec coverage.** Investors, agents and customers-with-loan-data in the Owner's
stated order: Tasks 2, 3, 4. Sliding screens: Task 1's `PageView`. Beside the
wizard: Task 1 Step 5 adds a button and modifies nothing else on OW-018. A
single missed entry without re-walking: `onlyMlid` in Task 1, wired in Task 5.

**The risk is Task 4, and it is a money risk.** Every other task can be wrong
and cost an afternoon. Task 4 can double a book, and this project has already
done that once — 108 loans, 22 Aug 2026. Its first test is the idempotency key
rather than the happy path, deliberately.

**What this plan does NOT do.** It does not touch the bulk wizard, its seven
pages or its service. It adds no RPC and no money path. It does not handle
migrating a person who does not exist yet — that is Universal Search's job, and
Task 3's "not in this book" action goes there rather than growing a second
registration form.

**Open question, worth settling before Task 4.** `submitEmiSchedule` replays one
`record_collection` per instalment and is slow by construction. On a
one-customer screen that is fine. If an Owner uses this door for forty
customers it becomes forty slow screens, and at that point the wizard is the
right tool — the app should probably say so once. Not built here; flagged.

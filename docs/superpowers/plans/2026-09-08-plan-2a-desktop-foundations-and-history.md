# Plan 2a — Desktop Foundations and the History Workflow

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give MANA LINE a desktop layout for the history-and-accounts workflow, and build the three shared primitives every later workflow plan will use — proven by a real consumer rather than shipped as an untested library.

**Architecture:** Three breakpoints extend the existing token file. An adaptive shell swaps the bottom nav for a nav rail at desk width. A ledger table replaces the card list for history. Each workflow leaves the centred column only by adding its route to `kManaWideRoutes`, so an unconverted screen cannot escape by accident.

**Tech Stack:** Flutter, the existing `lib/design/` system (`ManaCard`, `ManaBottomNav`, `ManaAppShell`, `ManaLedgerAmount`, `ManaAmount`), `flutter_test`.

## Global Constraints

- **Android behaviour must not change.** Every layout branch is gated on width, and `ManaBreakpoints.compact` is 600 — above every handset this app targets. `ManaWebFrame` is additionally gated on `kIsWeb`. If an existing test's layout moves, a branch is firing at handset width and is wrong.
- **Money-path files are not touched.** Nothing under `*_ledger*` that computes a figure. NOTE: `lib/shared/ledger_history_view.dart` matches by name and IS in scope — it is a VIEW. No figure, rounding, sign convention or date-grouping rule in it may change; only how rows are laid out.
- **Screen IDs are the routing contract.** No route added, removed or renamed. `lib/app/router.dart` is not modified.
- **`ManaText` enforces Title Case.** `ManaText.raw()` is the carve-out for free text and system IDs. Column headers are UI copy and go through `ManaText`.
- **No new palette, no new typefaces, no new spacing values.** Every colour from `ManaColors`, every size from `ManaSpacing` (4/8/12/16/24/32), every radius from the existing radius scale, every style from `ManaType`. The five-language layout tests are pinned to this type scale.
- **Overflow is this project's recurring shipped bug — four times.** Widening layouts is how it recurs. Every touched screen gets `expectNoLayoutFault` at three widths, not one.
- `flutter analyze` clean on every touched file. The suite (2,207 passing) stays green after every task.
- UTF-8, no BOM. Never commit credentials.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/design/components/mana_adaptive_shell.dart` | Bottom nav below 1024, nav rail at or above it. One job: which navigation affordance. |
| `lib/design/components/mana_ledger_table.dart` | The ledger spread. Ruled rows, right-aligned money, tabular figures. |
| `lib/design/components/mana_form_grid.dart` | One column below 900, two at or above. Used by later plans; proven here by the statement screen's filters. |
| `test/mana_adaptive_shell_test.dart` | The rail appears only at desk width. |
| `test/mana_ledger_table_test.dart` | Columns align; money right-aligns; no overflow at three widths. |
| `test/mana_form_grid_test.dart` | Reflows at the breakpoint; no orphaned field. |

**Modified:**

| File | Change |
|---|---|
| `lib/design/tokens/breakpoints.dart` | Add `medium` (600) and `expanded` (1024); keep `compact` and `columnMax`. |
| `lib/shared/ledger_history_view.dart` | Table at expanded width, existing card list below it. |
| `lib/features/owner_workspace/screens/ow_013_account_review.dart` | Card grid at medium and above. |
| `lib/features/owner_workspace/screens/ow_017_statement_screen.dart` | Form grid for its filters. |
| `test/support/mana_harness.dart` | A three-width helper, so every later plan uses the same one. |

**Why the primitives ship inside this plan rather than before it:** a component library with no consumer is untested by construction. Each of the three is built and then immediately used by a real screen in the same plan.

---

### Task 1: Three breakpoints, and a three-width test helper

**Files:**
- Modify: `lib/design/tokens/breakpoints.dart`
- Modify: `test/support/mana_harness.dart`
- Create: `test/mana_breakpoints_test.dart`

**Interfaces:**
- Consumes: `ManaBreakpoints.compact` (600.0), `ManaBreakpoints.columnMax` (480.0), `kManaWideRoutes` — all existing.
- Produces:
  - `ManaBreakpoints.medium` = `600.0`, `ManaBreakpoints.expanded` = `1024.0`
  - `ManaBreakpoints.of(double width)` returning `ManaWidthClass.compact | medium | expanded`
  - `enum ManaWidthClass { compact, medium, expanded }`
  - In the harness: `Future<void> pumpAtWidths(WidgetTester tester, Widget widget, Future<void> Function() check)` running at 390, 820 and 1440.

- [ ] **Step 1: Write the failing test**

Create `test/mana_breakpoints_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// The width classes, and the one property that protects Android.
///
/// `compact` is 600 because every handset this app targets sits under it —
/// that is what makes every desktop branch incapable of firing on a phone.
/// It is asserted here rather than assumed, because the whole safety argument
/// for the web work rests on it.
void main() {
  test('a handset is compact', () {
    expect(ManaBreakpoints.of(360), ManaWidthClass.compact);
    expect(ManaBreakpoints.of(599.9), ManaWidthClass.compact);
  });

  test('a tablet is medium', () {
    expect(ManaBreakpoints.of(600), ManaWidthClass.medium);
    expect(ManaBreakpoints.of(1023.9), ManaWidthClass.medium);
  });

  test('a desk is expanded', () {
    expect(ManaBreakpoints.of(1024), ManaWidthClass.expanded);
    expect(ManaBreakpoints.of(1920), ManaWidthClass.expanded);
  });

  test('the boundaries are the documented numbers', () {
    // Guards against someone "tidying" these into round-ish numbers that no
    // longer match the comment explaining why 600 protects Android.
    expect(ManaBreakpoints.compact, 600.0);
    expect(ManaBreakpoints.medium, 600.0);
    expect(ManaBreakpoints.expanded, 1024.0);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/mana_breakpoints_test.dart
```

Expected: compile failure — `ManaWidthClass` and `ManaBreakpoints.of` do not exist.

- [ ] **Step 3: Extend the tokens**

Add to `lib/design/tokens/breakpoints.dart`, keeping everything already there:

```dart
/// Which of the three layouts a viewport gets.
///
/// Named for what the space affords rather than for a device, because the same
/// browser window changes class when somebody drags its edge — and a tablet in
/// portrait is a phone-shaped space regardless of what it is called.
enum ManaWidthClass { compact, medium, expanded }

// inside ManaBreakpoints:

  /// A tablet, or a browser window somebody has narrowed. Two columns fit;
  /// a nav rail does not, so the bottom nav stays.
  static const medium = 600.0;

  /// A desk. Wide enough for a nav rail beside content, and for the ledger
  /// table's columns to be read across without crowding.
  static const expanded = 1024.0;

  static ManaWidthClass of(double width) => width >= expanded
      ? ManaWidthClass.expanded
      : width >= medium
          ? ManaWidthClass.medium
          : ManaWidthClass.compact;
```

Note `compact` and `medium` are deliberately the same number: `compact` names the ceiling of the phone range, `medium` the floor of the tablet range. Keep both names — call sites read better for it, and the test above pins them together so they cannot drift apart.

- [ ] **Step 4: Run the test — expect PASS**

```bash
flutter test test/mana_breakpoints_test.dart
```

- [ ] **Step 5: Add the three-width harness helper**

In `test/support/mana_harness.dart`, beside `expectNoLayoutFault`:

```dart
/// Pump [widget] at a phone, a tablet and a desk, running [check] at each.
///
/// WHY THREE AND WHY THESE: overflow is this project's recurring shipped bug —
/// four times, always a bare unflexible child beside a flexible one, invisible
/// to `flutter analyze`. Widening a layout is exactly how it recurs, and a
/// layout tested only at 360 proves nothing about the width it was widened
/// for. 390 is a common handset, 820 a tablet, 1440 a laptop.
Future<void> pumpAtWidths(
  WidgetTester tester,
  Widget widget,
  Future<void> Function(double width) check,
) async {
  for (final width in const [390.0, 820.0, 1440.0]) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    await check(width);
  }
}
```

- [ ] **Step 6: Run analyze and the full suite**

```bash
flutter analyze lib/design/tokens/breakpoints.dart test/support/mana_harness.dart
flutter test
```

Expected: analyze clean, 2,207 + 4 new = 2,211 passing, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/design/tokens/breakpoints.dart test/support/mana_harness.dart test/mana_breakpoints_test.dart
git commit -m "Three width classes, and a helper that pumps every layout at all three"
```

---

### Task 2: The nav rail

**Files:**
- Create: `lib/design/components/mana_adaptive_shell.dart`
- Create: `test/mana_adaptive_shell_test.dart`

**Interfaces:**
- Consumes: `ManaBreakpoints.of`, `ManaWidthClass` (Task 1); existing `ManaBottomNav` and `ManaNavItem` from `lib/design/components/mana_header.dart`.
- Produces: `class ManaAdaptiveShell extends StatelessWidget { const ManaAdaptiveShell({super.key, required List<ManaNavItem> items, required int currentIndex, required Widget child, Widget? appBar}); }`

**Read `mana_header.dart`'s `ManaBottomNav` and `ManaNavItem` before writing anything.** The rail is the same items, the same indices and the same callbacks in a vertical arrangement — not a new navigation model. A rail whose items differ from the bottom nav's would mean two navigation contracts to keep in sync, which is the shape of this project's worst regressions.

- [ ] **Step 1: Write the failing test**

Create `test/mana_adaptive_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_adaptive_shell.dart';
import 'package:mana_line/design/components/mana_header.dart';

void main() {
  final items = [
    ManaNavItem(icon: Icons.home, label: 'home', onTap: () {}),
    ManaNavItem(icon: Icons.list, label: 'history', onTap: () {}),
  ];

  Widget shell() => MaterialApp(
        home: ManaAdaptiveShell(
          items: items,
          currentIndex: 0,
          child: const SizedBox(key: Key('content')),
        ),
      );

  testWidgets('a phone keeps the bottom nav and shows no rail', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(ManaBottomNav), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a tablet still keeps the bottom nav', (tester) async {
    // 820 is medium: two columns fit, a rail does not without crowding the
    // content it is supposed to sit beside.
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(ManaBottomNav), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a desk gets the rail and drops the bottom nav', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(ManaBottomNav), findsNothing);
  });

  testWidgets('the content is always present', (tester) async {
    for (final w in const [390.0, 820.0, 1440.0]) {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(shell());
      expect(find.byKey(const Key('content')), findsOneWidget,
          reason: 'content vanished at ${w}px');
    }
  });
}
```

If `ManaNavItem`'s constructor differs from the shape above, match the real one — read it first and adjust the test, not the widget.

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/mana_adaptive_shell_test.dart
```

Expected: compile failure — the shell does not exist.

- [ ] **Step 3: Write the shell**

Create `lib/design/components/mana_adaptive_shell.dart`. It renders a `Scaffold` whose `bottomNavigationBar` is the existing `ManaBottomNav` below `expanded`, and at `expanded` puts a `NavigationRail` in a `Row` beside the child with no bottom bar.

Requirements for the body of it:
- The rail's destinations are built from the SAME `items` list, in the same order, calling the same `onTap`. Do not accept a separate rail-items parameter.
- Use `ManaColors` for the rail's background and indicator, `ManaSpacing` for padding. No new values.
- Labels go through `ManaText`, not `Text` — Title Case is enforced in code here.
- The rail is `NavigationRailLabelType.all`: at desk width there is room, and an icon-only rail makes people guess.

Write the doc comment in house style, covering: why the rail appears only at `expanded` (a rail at 820 steals width from the content it exists to sit beside), and why items are shared rather than duplicated.

- [ ] **Step 4: Run the test — expect PASS**

```bash
flutter test test/mana_adaptive_shell_test.dart
```

- [ ] **Step 5: Analyze and full suite**

```bash
flutter analyze lib/design/components/mana_adaptive_shell.dart
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/design/components/mana_adaptive_shell.dart test/mana_adaptive_shell_test.dart
git commit -m "At desk width the bottom nav becomes a rail, from the same items"
```

---

### Task 3: The ledger table

**Files:**
- Create: `lib/design/components/mana_ledger_table.dart`
- Create: `test/mana_ledger_table_test.dart`

**Interfaces:**
- Consumes: `ManaBreakpoints`, `ManaColors`, `ManaSpacing`, `ManaType`, and the existing `ManaLedgerAmount` / `ManaAmount` for money rendering.
- Produces:
  - `class ManaLedgerColumn { const ManaLedgerColumn({required String label, required double flex, bool numeric = false}); }`
  - `class ManaLedgerTable extends StatelessWidget { const ManaLedgerTable({super.key, required List<ManaLedgerColumn> columns, required List<List<Widget>> rows, List<Widget>? dayHeaders}); }`

**This is the plan's signature element.** On a phone MANA LINE is a sequence — one thing at a time, because a collector at a doorstep can hold one thing. On a desk it becomes the artifact these businesses actually keep: a ledger spread, many rows at once, the rupee column aligned so the eye runs down it.

Design requirements, all derived from existing tokens:

- **Money right-aligns, in tabular figures.** A column whose digits do not line up cannot be scanned or added by eye, and misreading a figure is the failure this project treats as worse than a crash. Use `FontFeature.tabularFigures()` on numeric cells so digit widths are equal.
- **Rules, not cards.** A hairline `ManaColors` divider between rows; no card elevation, no per-row radius. The table is one object.
- **The header row is `ManaText`**, sticky at the top of the scroll area.
- **Row height and padding from `ManaSpacing`** — `md` vertical, `lg` horizontal.
- **The table scrolls horizontally inside its own container** if the columns cannot fit; the page must never scroll sideways.
- No zebra striping. The rules already separate rows, and alternating fills fight the status colours that money rows carry.

- [ ] **Step 1: Write the failing test**

Create `test/mana_ledger_table_test.dart` covering:
1. Every column header renders.
2. A numeric cell is right-aligned and a text cell is not — assert on the resolved alignment, not on pixel positions.
3. At 390, 820 and 1440 via `pumpAtWidths`, `expectNoLayoutFault` reports nothing.
4. With columns wider than the viewport, the horizontal scroll view exists and the page's own scroll extent does not grow — the table scrolls, the page does not.

Write real expectations, not placeholders. If a property cannot be asserted directly, assert the widget that carries it.

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/mana_ledger_table_test.dart
```

- [ ] **Step 3: Write the table**

Per the design requirements above. Keep it a pure layout component — it takes rows already built by the caller and knows nothing about ledgers, money rules or dates. That boundary is what lets OW-017 and AG-010 share it without sharing behaviour.

- [ ] **Step 4: Run the test — expect PASS**

- [ ] **Step 5: Analyze and full suite**

```bash
flutter analyze lib/design/components/mana_ledger_table.dart
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/design/components/mana_ledger_table.dart test/mana_ledger_table_test.dart
git commit -m "A ledger spread for desk width: ruled rows, and rupee columns that line up"
```

---

### Task 4: History becomes a table at desk width

**Files:**
- Modify: `lib/shared/ledger_history_view.dart`
- Modify: `lib/design/tokens/breakpoints.dart` (add the two routes to `kManaWideRoutes`)
- Create: `test/ledger_history_view_layout_test.dart`

**Interfaces:**
- Consumes: `ManaLedgerTable` (Task 3), `ManaBreakpoints.of` (Task 1).
- Produces: nothing new; the view's public constructor is unchanged.

**TWO CONSUMERS. This is the rule this codebase exists to enforce.** `ledger_history_view.dart` is used by OW-017 (Owner) and AG-010 (Agent). Its own doc comment records that the two carried 327 lines of duplication before being merged, and that what differs by role is whose balances show, whether the month band appears, and one label.

**Open both consumers before changing anything, and check both after.** Add `/ow-017` AND `/ag-010` to `kManaWideRoutes` in the same commit, or the Agent gets a table it was never laid out for — or worse, is left clamped while the Owner is not, and the two silently diverge.

- [ ] **Step 1: Read both consumers**

```bash
sed -n '1,60p' lib/features/owner_workspace/screens/ow_017_transaction_history.dart
grep -rn "ManaLedgerHistoryView" lib --include=*.dart
```

Record in your report every consumer you find, and confirm the list is exactly two. **If it is three, stop and report** — a third consumer means this plan's premise is wrong.

- [ ] **Step 2: Write the failing layout test**

Create `test/ledger_history_view_layout_test.dart`, seeding the notifier rather than letting it reach the network (a screen that loads in `initState` and is not seeded lays out an empty state and proves nothing — this is the harness convention). Assert:
1. At 390 the existing card list renders and no `ManaLedgerTable` is present.
2. At 1440 a `ManaLedgerTable` is present and the card list is not.
3. `expectNoLayoutFault` at all three widths.
4. The same seeded row count appears in both layouts — the table must not silently drop or duplicate rows.

Assertion 4 is the important one. A layout change that loses a row is a wrong ledger.

- [ ] **Step 3: Run it and watch it fail**

- [ ] **Step 4: Implement the branch**

In `build`, choose by `ManaBreakpoints.of(MediaQuery.sizeOf(context).width)`: `expanded` renders `ManaLedgerTable`, everything else renders exactly the list that renders today.

**Both paths must read from the same already-built row model.** Do not write a second data path for the table — one source, two presentations. A second path is how the two views drift and how a figure appears in one and not the other.

Do not change any figure, sign convention, rounding or day-grouping rule. Only presentation.

- [ ] **Step 5: Add both routes to `kManaWideRoutes`**

```dart
final Set<String> kManaWideRoutes = <String>{
  '/ow-017',
  '/ag-010',
};
```

Update that file's comment: it currently says the set is empty on purpose. It is not any more, and the comment must say which plan filled it and why those two arrived together.

- [ ] **Step 6: Run the layout test, then analyze and the full suite**

```bash
flutter test test/ledger_history_view_layout_test.dart
flutter analyze lib/shared/ledger_history_view.dart lib/design/tokens/breakpoints.dart
flutter test
```

- [ ] **Step 7: Commit**

```bash
git add lib/shared/ledger_history_view.dart lib/design/tokens/breakpoints.dart test/ledger_history_view_layout_test.dart
git commit -m "History reads as a ledger at desk width, for the Owner and the Agent together"
```

---

### Task 5: Account review, and the statement filters

**Files:**
- Modify: `lib/features/owner_workspace/screens/ow_013_account_review.dart`
- Modify: `lib/features/owner_workspace/screens/ow_017_statement_screen.dart`
- Create: `lib/design/components/mana_form_grid.dart`
- Create: `test/mana_form_grid_test.dart`
- Create: `test/ow_013_layout_test.dart`

**Interfaces:**
- Produces: `class ManaFormGrid extends StatelessWidget { const ManaFormGrid({super.key, required List<Widget> children, int columnsAtMedium = 2}); }` — one column below `medium`, `columnsAtMedium` at or above it.

`ManaFormGrid` is built here and used by Plans 2b, 2c and 2e. It gets a real consumer in this plan (the statement screen's filters) so it is not an untested library.

- [ ] **Step 1: Write the form-grid test**

Create `test/mana_form_grid_test.dart`: one column at 390, two at 820 and 1440, every child present at every width, `expectNoLayoutFault` at all three. An odd number of children must not leave a stretched orphan — assert the last child's width matches its row-mates.

- [ ] **Step 2: Run it and watch it fail**

- [ ] **Step 3: Write `ManaFormGrid`**

Spacing from `ManaSpacing.lg` between columns and `ManaSpacing.md` between rows. No new values.

- [ ] **Step 4: Test passes; then adopt it in the statement screen**

`ow_017_statement_screen.dart` is 174 lines and its filters are the natural first consumer.

- [ ] **Step 5: Card grid for OW-013**

`ow_013_account_review.dart` is a `ListView` of `ManaCard`s. At `medium` and above, flow them into two columns; at `expanded`, three. Create `test/ow_013_layout_test.dart` asserting the column count at each width and `expectNoLayoutFault` at all three, with the provider seeded.

Add `/ow-013` to `kManaWideRoutes`.

- [ ] **Step 6: Analyze and full suite**

```bash
flutter analyze lib/design/components/mana_form_grid.dart lib/features/owner_workspace/screens/ow_013_account_review.dart lib/features/owner_workspace/screens/ow_017_statement_screen.dart
flutter test
```

- [ ] **Step 7: Commit**

```bash
git add lib/design/components/mana_form_grid.dart test/mana_form_grid_test.dart lib/features/owner_workspace/screens/ow_013_account_review.dart lib/features/owner_workspace/screens/ow_017_statement_screen.dart test/ow_013_layout_test.dart lib/design/tokens/breakpoints.dart
git commit -m "Account review flows into columns, and the statement filters get a grid"
```

---

### Task 6: Look at it

**Files:** none — this task changes nothing and proves everything.

- [ ] **Step 1: Build and serve**

```bash
flutter build web --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Serve `build/web` (there is a `mana-web` config in `.claude/launch.json`).

- [ ] **Step 2: Look at the three widths**

390, 820 and 1440. Screenshot each. The rail appears only at 1440; history is a table there and a card list at 390.

- [ ] **Step 3: Check the thing the tests cannot**

Do the rupee columns actually line up? Tabular figures are asserted by the presence of a font feature, not by appearance. **Look at a column of real amounts and confirm the digits align.** A table whose figures do not line up has failed at its one job while passing every test.

- [ ] **Step 4: Confirm Android is untouched**

```bash
& .\tool\build_apk.ps1
```

Install, open the history screen, confirm it is the same card list as before. Note `pwsh` is not installed on this machine — use `& .\tool\build_apk.ps1`, and do not pipe it through `2>&1`, which turns Flutter's KGP warning into a terminating error under PowerShell 5.1.

- [ ] **Step 5: Report**

State what was verified and how, separately from what was changed.

---

## Self-Review

**Spec coverage.** Spec §4's history-and-accounts workflow → Tasks 3-5. The breakpoint token file it calls for → Task 1. `expectNoLayoutFault` at three widths → Task 1's harness helper, used by every layout test after. The shared-consumer warning about `ManaLedgerHistoryView` and AG-010 → Task 4, called out as the task's central risk.

**Placeholders.** Task 3 Step 1, Task 5 Steps 1 and 5 describe tests by their assertions rather than quoting code. That is deliberate for widget tests whose exact finders depend on the real constructors — every one names the specific properties to assert. Task 2 Step 3 and Task 5 Step 3 describe widgets by requirement rather than full source, because both are short and their shape depends on the existing `ManaBottomNav` and `ManaSpacing` values the implementer must read first. Inventing that source here is what produced three wrong constants in Plan 1.

**Type consistency.** `ManaWidthClass` and `ManaBreakpoints.of` — defined Task 1, used Tasks 2, 3, 4, 5. `ManaLedgerTable` / `ManaLedgerColumn` — defined Task 3, consumed Task 4. `ManaFormGrid` — defined and consumed in Task 5. `pumpAtWidths` — defined Task 1, used throughout. `kManaWideRoutes` — filled across Tasks 4 and 5.

**Scope.** Six tasks, 6 files created, 6 modified. Independently shippable: after Task 6 the history workflow has a real desktop layout and the three primitives exist, proven.

---

## The four plans after this one

**2b — Profile and settings.** `settings_screen.dart` (744) and `ow_016_profile.dart` (731) get the nav rail beside a content pane. First real use of `ManaAdaptiveShell` outside history. Note `settings_screen.dart` is shared by all four workspaces.

**2c — Pre-existing business.** OW-018 (1,292) and the bulk-onboarding wizard (2,115) get two-column forms via `ManaFormGrid`. The largest single screen in the app.

**2d — Subscription.** `/subscription` (205) puts its four tiers side by side. Small, once `ManaFormGrid` exists.

**2e — Login and registration.** LR-001…013, 12 files, 4,980 lines. Centred forms need the least desktop treatment; last on purpose.

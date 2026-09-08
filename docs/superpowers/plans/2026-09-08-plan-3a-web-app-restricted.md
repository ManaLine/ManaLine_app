# Plan 3a — the restricted web app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the web build from "the whole app, clamped" into a purpose-built five-workflow surface with its own entrypoint, its own router, and a landing screen that exists only on the web.

**Architecture:** A second entrypoint (`lib/main_web.dart`) drives a second router (`lib/app/web_router.dart`) registering only an allowlist of screen IDs, guarded by a test that fails if the two routers ever disagree. Android's `lib/main.dart` and `manaRouter` are untouched.

**Tech Stack:** Flutter, GoRouter, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-08-website-reframe-design.md`

## Global Constraints

- **Android behaviour must not change.** `lib/main.dart`, `manaRouter`, and every screen's own behaviour stay as they are. Any task that alters an Android-visible behaviour is written wrong.
- **Money-path files are not touched.** Nothing under `*_ledger*`, `*_collection*`, `*_loan_math*` is modified, except the deliberate revert in Task 1 which removes a LAYOUT branch only.
- **Screen IDs remain the routing contract.** No screen is renamed. The web router reuses existing IDs; it does not invent new ones except for the one new web-only screen, which takes a non-ID path.
- **No new palette, typefaces, or spacing values.** Everything from `ManaColors`, `ManaType`, `ManaSpacing`.
- **UI copy goes through `ManaText`** (Title Case enforced in code); `ManaText.raw()` only for free text and system IDs. Every new user-facing string needs a translation key.
- **Copy is intent, not transcription.** No phrase from the spec or these briefs reaches a screen verbatim.
- `flutter analyze` clean on every touched file.
- Full `flutter test` green after every task. Baseline is **2,242 passing, 0 failures**; Task 1 removes roughly 12.
- Layout branches read `LayoutBuilder` constraints, never `MediaQuery.sizeOf` — inside `ManaWebFrame`'s clamp, `MediaQuery` reports the window while the real width is 480. Found the hard way in Plan 2a.
- UTF-8, no BOM. Never commit credentials.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/features/web/screens/web_home_screen.dart` | The web-only landing hub. Role-aware, carries no figures. |
| `lib/app/web_router.dart` | The web router and its allowlist constant. |
| `lib/main_web.dart` | Web entrypoint. |
| `test/web_router_guard_test.dart` | Fails if the two routers drift. |
| `test/web_home_screen_test.dart` | The hub renders the right destinations per role. |

**Modified:**

| File | Change |
|---|---|
| `lib/shared/ledger_history_view.dart` | Remove the table branch; card list only. |
| `lib/design/tokens/breakpoints.dart` | Drop history routes from `kManaWideRoutes`; fix a stale comment. |
| `lib/design/components/mana_form_grid.dart` | Fix a stale comment. |
| `lib/main.dart` | `ManaLineApp` gains a router parameter, defaulting to `manaRouter`. |
| `lib/features/login_registration/screens/lr_013_role_selector.dart` | Role→home mapping becomes injectable. |

**Deleted:** `lib/design/components/mana_ledger_table.dart`, `test/mana_ledger_table_test.dart`, and the table half of `test/ledger_history_view_layout_test.dart`.

---

### Task 1: Delete the desk-width history work

**Files:**
- Delete: `lib/design/components/mana_ledger_table.dart`, `test/mana_ledger_table_test.dart`
- Modify: `lib/shared/ledger_history_view.dart`, `test/ledger_history_view_layout_test.dart`, `lib/design/tokens/breakpoints.dart`, `lib/design/components/mana_form_grid.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `kManaWideRoutes` reduced to `{'/ow-013'}`.

This is a deliberate revert of work that was built, reviewed and shipped in Plan 2a. It is being removed because the website no longer shows transaction history — not because it was wrong.

- [ ] **Step 1: Read what you are removing**

```bash
git log --oneline 07cf2e0 -6
```

`ledger_history_view.dart` gained a `_tableBody`, a `LayoutBuilder` branch, `_tableScroll`, and day-band construction. The card path (`_cardBody`) is the original and stays.

- [ ] **Step 2: Revert the view to card-only**

Remove `_tableBody`, the `LayoutBuilder`/width branch, `_tableScroll` and its disposal, and the `ManaLedgerTable` import. `_cardScroll` reverts to being the only controller — you may rename it back to `_scroll`.

**Do not touch any figure, rounding, sign convention or day-grouping rule.** The card path's behaviour must be byte-identical to what it was before Plan 2a's Task 4. Compare against `git show d17caa1:lib/shared/ledger_history_view.dart` to confirm.

- [ ] **Step 3: Delete the component and its test**

```bash
git rm lib/design/components/mana_ledger_table.dart test/mana_ledger_table_test.dart
```

- [ ] **Step 4: Remove the table half of the layout test**

`test/ledger_history_view_layout_test.dart` has tests for both layouts. Remove only those asserting the table — including the agent-at-expanded-width group. **Keep every card-list assertion**, and keep the row-count assertion for the card path.

- [ ] **Step 5: Fix the two stale comments**

`mana_form_grid.dart:13` and `breakpoints.dart:58` both reference `ManaLedgerTable`. Reword them to describe the boundary without naming a deleted class.

- [ ] **Step 6: Reduce the route set**

In `breakpoints.dart`, `kManaWideRoutes` becomes `{'/ow-013'}` — history and the statement screen leave. Update its comment to say which plan removed them and why.

- [ ] **Step 7: Verify**

```bash
flutter analyze
flutter test
```

Expected: analyze clean; suite green at roughly 2,230 (about 12 fewer). Any failure outside the removed tests is a real regression.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "The website shows accounts, not history, so the ledger table goes"
```

---

### Task 2: The web home

**Files:**
- Create: `lib/features/web/screens/web_home_screen.dart`, `test/web_home_screen_test.dart`

**Interfaces:**
- Consumes: `ManaSession` for the current person and role; `ManaAdaptiveShell`, `ManaFormGrid`, `ManaBreakpoints` from the design system.
- Produces: `class ManaWebHomeScreen extends ConsumerWidget`, routed at `/web-home` by Task 3.

**This is the most important screen in the plan.** It is the first thing a signed-in person sees, it exists only on the web, and it is what makes the site read as its own product rather than a reduced copy of the app.

- [ ] **Step 1: Read the design system first**

```bash
sed -n '1,60p' lib/design/components/mana_adaptive_shell.dart
sed -n '1,40p' lib/design/components/mana_form_grid.dart
sed -n '1,50p' lib/design/tokens/colors.dart
```

- [ ] **Step 2: Build the screen**

Requirements, all load-bearing:

- **No figures.** No balance, no count, no chart, no "3 loans". A number here would be a smaller version of the thing being removed from the site. Destinations and words only.
- **Role-aware.** Reads the active role from `ManaSession` and shows only that role's permitted destinations:

| Role | Destinations |
|---|---|
| Owner | Accounts, Pre-Existing Business, Subscription, Profile, Settings |
| Investor | My Investments, Profile, Settings |
| Customer | My Loan, Profile, Settings |
| Agent | Profile, Settings — and the app as the primary content |

- **The Agent case is the one to get right.** They authenticate successfully and there is genuinely nothing here for them, because their whole role is field work. Write it as what it is: the work they do happens on their phone, and this is where they get it. It must not read as an error, a permission failure, or an apology.
- **Every role gets the app.** Not only the Agent — an Owner who has just typed in an old book should be able to get the handset app too. It is secondary for them and primary for an Agent.
- Layout via `ManaFormGrid` so destinations flow into columns at width; `ManaAdaptiveShell` for the frame — **this is the shell's first production consumer**, which is why it exists.
- Translation keys for every string.

- [ ] **Step 3: Write the tests**

`test/web_home_screen_test.dart`, seeding `ManaSession` per role:
1. Each of the four roles renders exactly its own destination set — and, critically, **no destination outside it**. An Owner-only link appearing for a Customer is the failure this test exists for.
2. The Agent case renders the app route as its primary action.
3. `pumpAtWidths` + `expectNoLayoutFault` at 390/820/1440.
4. **No digit appears anywhere in the rendered text**, other than in a version string. This pins "no figures" as a property rather than an intention.

- [ ] **Step 4: Verify and commit**

```bash
flutter analyze lib/features/web/screens/web_home_screen.dart
flutter test test/web_home_screen_test.dart
flutter test
git add -A && git commit -m "A landing screen that belongs to the web rather than the handset"
```

---

### Task 3: The web entrypoint, router and drift guard

**Files:**
- Create: `lib/app/web_router.dart`, `lib/main_web.dart`, `test/web_router_guard_test.dart`
- Modify: `lib/main.dart`, `lib/features/login_registration/screens/lr_013_role_selector.dart`

**Interfaces:**
- Consumes: `ManaWebHomeScreen` from Task 2.
- Produces: `manaWebRouter`, `kManaWebAllowedRoutes`.

- [ ] **Step 1: Parameterise the app widget**

`ManaLineApp` currently hardcodes `manaRouter` (`lib/main.dart:109`). Give it a `GoRouter router` parameter defaulting to `manaRouter`, so `lib/main.dart`'s behaviour is unchanged and `main_web.dart` can pass its own.

- [ ] **Step 2: Make the role→home mapping injectable**

`lr_013_role_selector.dart:18` holds a private `_roleHomeRoutes` mapping all four roles to dashboards that do not exist in the web router. Make it an optional constructor parameter defaulting to the current map, so the web router can pass a map sending every role to `/web-home`.

**Check LR-001 and LR-012 for the same pattern** — anything else that routes to `/ow-001`, `/ag-001`, `/cw-001` or `/iw-001` must also be reachable-safe on web. Report what you find; do not silently leave a dead route.

- [ ] **Step 3: Write the router**

`lib/app/web_router.dart`: `kManaWebAllowedRoutes` as an explicit `Set<String>`, and `manaWebRouter` registering exactly those, reusing the same screen widgets `manaRouter` uses.

The allowlist:

```
/lr-001 /lr-002 /lr-004 /lr-005 /lr-006 /lr-007 /lr-008 /lr-009
/lr-010 /lr-011 /lr-012 /lr-013
/web-home
/ow-013 /ow-016 /ow-018 /ow-bulk-onboarding /import /subscription
/ag-009
/cw-004 /cw-006
/iw-003 /iw-005
/profile /settings /ow-settings /ag-settings /cw-settings /iw-settings
/appearance /about
```

Anything not listed must not resolve. Give the router an `errorBuilder` that explains the screen lives in the app and offers the download — not a raw 404.

- [ ] **Step 4: Write the entrypoint**

`lib/main_web.dart`: mirror `lib/main.dart`'s setup — the same `Supabase.initialize`, the same `ProviderScope`, the same misconfigured-build guard — passing `manaWebRouter`. **Do not duplicate logic that could be shared**; extract what both need rather than copying it, and say in your report what you extracted.

- [ ] **Step 5: Write the drift guard**

`test/web_router_guard_test.dart` must fail when:
1. a route in `manaWebRouter` is absent from `manaRouter` (except `/web-home`);
2. the web router's route set differs from `kManaWebAllowedRoutes`;
3. a route in the allowlist is missing from `manaWebRouter`.

**Prove it fires.** Temporarily add a route to one side only, watch the guard fail, revert. Record that output — a guard nobody has seen fail is a guard nobody knows works.

- [ ] **Step 6: Verify**

```bash
flutter analyze
flutter test
flutter build web -t lib/main_web.dart --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

The Android build must still work unchanged:

```bash
flutter build apk --debug --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "The web gets its own door, and a guard so the two never disagree"
```

---

### Task 4: Walk it in a browser

**Files:** none — this task changes nothing and proves everything.

- [ ] **Step 1: Build and serve**

```bash
flutter build web -t lib/main_web.dart --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

- [ ] **Step 2: Sign in as each role available** and confirm the hub shows that role's destinations and nothing else.

- [ ] **Step 3: Try to reach a blocked screen by URL** — `#/ow-006`, `#/ow-005`, `#/ag-002`. Each must land on the explanatory error screen, not a collection screen and not a crash. **This is the check that proves the restriction is real**, and it cannot be done from a unit test.

- [ ] **Step 4: Confirm the clamp behaves** — Plan 2a found that `ManaWebFrame` did not re-evaluate on in-app navigation. That defect is still open. Verify whether the new router changes it, and report either way.

- [ ] **Step 5: Read the console** for `MissingPluginException` and any router assertion.

- [ ] **Step 6: Report** what was verified and how, separately from what was changed.

---

## Self-Review

**Spec coverage.** §6 deletion → Task 1. §3 the hub → Task 2. §4 entrypoint and guard → Task 3. §2 allowlist → Task 3 Step 3. §5 public site → **Plan 3b, not this plan.** §8 copy → Global Constraints and Task 2.

**Placeholders.** Task 2 Step 2 describes the hub's content rather than quoting code, deliberately — it is a new screen whose shape depends on the design system it is read against, and prescribing widget code from outside would repeat the errors Plan 2a's briefs made when they invented constructor signatures.

**Type consistency.** `kManaWebAllowedRoutes` and `manaWebRouter` are named identically in Task 3 and the guard. `ManaWebHomeScreen` is named identically in Tasks 2 and 3.

**Known open item carried in.** `ManaWebFrame` not re-evaluating on in-app navigation (Plan 2a browser walk, defect B) is unfixed. Task 4 Step 4 re-checks it under the new router rather than assuming the entrypoint change fixed or preserved it.

**Scope.** Four tasks. The public site is Plan 3b.

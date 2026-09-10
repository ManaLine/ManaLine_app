# Plan 4 — two ways to find a village: by PIN, or by cascade

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep PIN-code search exactly as it is and make it the default, and **add** a second way in — state, then district, then village name — so somebody who does not know their postal code can still find their own village.

**Architecture:** One index makes the cascade possible at all. New data-layer methods serve the three cascade steps, alongside the existing `searchByPin` which is untouched. One widget offers both modes with PIN selected by default, and the eleven screens that use the current picker adopt it.

**Revised 2026-09-11.** The first draft of this plan REPLACED PIN entry with the cascade. The owner corrected that: PIN search stays, is the default, and the cascade is an alternative the person can switch to. That is the better shape — for a user who does know their PIN, six digits is faster than three pickers, and nothing about the existing path needed fixing.

**Tech Stack:** Flutter, Riverpod, Supabase/PostgREST, `flutter_test`.

## Global Constraints

- **PIN search is not removed, changed, or deprecated.** `searchByPin`, its 3-letter rule and its behaviour stay exactly as they are, and PIN is the **default** mode. The cascade is added beside it. A change that makes the existing path worse in order to add a new one has failed.
- **Both rules are live at once.** PIN + ≥3 letters, and state + district + ≥3 letters prefix-first. Two search rules now exist deliberately, and the guard test must pin **both** rather than being switched from one to the other.
- **Money paths are untouched.** No file matching `*_ledger*`, `*_collection*`, `*_loan_math*` is modified.
- `flutter analyze` clean on every touched file. Full `flutter test` green after every task — baseline **2,245 passing**.
- **The two guard tests are EXTENDED to cover both rules, never loosened.** `village_search_rule_test.dart` and `village_lookup_guard_test.dart` exist because the search rule had already drifted across three copies. A second rule arriving beside the first is exactly the condition that produced that drift, so both guards must end up protecting more than they do today, not the same amount aimed elsewhere.
- **Minimum 3 letters** before a village search runs. Decided by the owner; unchanged from today.
- **No result cap** — the cascade bounds the list structurally. This is only safe with prefix matching (measured: 14–18 rows) and unsafe with substring (400–500 in the largest AP districts), which is why the fallback exists and is second.
- UTF-8, no BOM. Never commit credentials.

## Measured facts this plan rests on

| Fact | Value | Source |
|---|---|---|
| `lgd_villages` rows | 767,191 | `count(*)` |
| States / districts | 35 / 773 | `count(distinct …)` |
| Existing indexes | **one, on `pincode`** | `pg_indexes` |
| One village search today | **2,300 ms**, parallel seq scan, 383,588 rows discarded | `EXPLAIN ANALYZE` |
| Prefix match, worst AP district | 14–18 rows | Visakhapatnam, `pal%` |
| Substring match, same district | 467–500 rows | Visakhapatnam, `%pal%` |

The 2.3 s figure is the whole reason Task 1 exists and comes first.

---

### Task 1: Make the cascade possible

**Files:** Create one migration under `supabase/migrations/`.

**Interfaces:**
- Consumes: nothing.
- Produces: an index the data layer depends on.

- [ ] **Step 1: Confirm the diagnosis yourself**

```sql
explain (analyze, buffers)
select distinct village, mandal, district, state, pincode
from lgd_villages
where state = 'Andhra Pradesh' and district = 'Visakhapatnam'
  and village ilike 'pal%' order by village;
```

Expect a `Parallel Seq Scan` and roughly 2,300 ms. Record what you actually see — if it is already fast, the index may exist and this task changes.

- [ ] **Step 2: Add the index**

A btree on `(state, district)`. The hypothesis to test, not assume: narrowing to one district leaves at most ~8,500 rows, and an `ILIKE` scan over that is cheap enough that no index on `village` is needed.

**Test that hypothesis before adding more.** If `(state, district)` alone brings the query under ~50 ms, stop there — an unnecessary trigram GIN index on 767k rows costs write time and disk for nothing. If it does not, add what the plan actually requires and say why.

Migration rules apply in full: filename must be `<14-digit-timestamp>_name.sql` and must match the version stamped in `supabase_migrations.schema_migrations` exactly, or `supabase db push` silently ignores it. Apply via MCP, then rename the local file to the real stamp.

- [ ] **Step 3: Re-measure and record both numbers**

Run the same `EXPLAIN ANALYZE`. Report before and after. **A number you did not measure is not a result.**

- [ ] **Step 4: Commit**

---

### Task 2: The data layer

**Files:** Modify `lib/shared/location_api_service.dart`; create its test.

**Interfaces:**
- Produces:
  - `Future<List<String>> states()`
  - `Future<List<String>> districtsIn(String state)`
  - `Future<List<ManaVillage>> searchVillages({required String state, required String district, required String query})`

- [ ] **Step 1: Read the file first**

It already holds `searchByPin`, `minVillageLetters`, `resolveId`, `pinOptions`, `similarVillages`, `addIfMissing`. **Do not delete `searchByPin` in this task** — eleven screens still call the old flow and they migrate in Task 4. Removing it early breaks the app mid-plan.

- [ ] **Step 2: Prefix first, substring second**

`searchVillages` runs a prefix match (`village ilike '<q>%'`). **Only if that returns nothing** does it run a substring match (`village ilike '%<q>%'`).

Why that order, in a comment: prefix keeps the list at 14–18 rows in the largest AP district, which is what makes the owner's "no cap" decision safe. Substring in the same district returns 467. The fallback exists because LGD spellings diverge mid-word — *Ichapuram* and *Ichchapuram* are one place — and it fires rarely because a prefix already catches that pair.

Returns fewer than 3 letters → empty list, no query. Same rule as today.

- [ ] **Step 3: Order the results**

Village name ascending. State and district are already fixed by the cascade, so ordering by them would be noise.

- [ ] **Step 4: Test it**

Cover: fewer than 3 letters returns empty and issues no request; a prefix hit does not run the substring query; a prefix miss falls back; results are ordered. Use the project's existing pattern for faking the Supabase client — read a neighbouring service's test rather than inventing one.

---

### Task 3: The picker

**Files:** Create `lib/shared/widgets/village_search_field.dart` and its test.

**Interfaces:**
- Consumes: Task 2's three methods.
- Produces: `ManaVillageSearchField({required ValueChanged<ManaVillage?> onPicked, String? label})` — a two-mode field, PIN by default, cascade on request. **Deliberately the same callback shape as `ManaVillagePickerField`**, so Task 4's eleven adoptions are a swap rather than a rewrite at each site.

- [ ] **Step 1: Read what you are extending, not replacing**

`lib/shared/widgets/village_picker_field.dart` — a PIN field and a query field. **That mode stays and keeps working.** Match its callback contract exactly, including emitting `null` when the person edits away a chosen village.

The new widget offers two modes with **PIN selected by default**. Reuse the existing PIN+query fields for that mode rather than reimplementing them — a second copy of a working search is how the two drift.

- [ ] **Step 1b: The mode switch**

A clear, plain control — two options, PIN first. Not a hidden setting, not an icon a person has to guess at.

Switching modes **clears the current selection**, because a village found by PIN and a village found by cascade are the same row reached two ways, and carrying a half-finished selection across the switch is how someone submits an address they did not choose.

Default is PIN on every open. Do not remember the last mode: the person who used the cascade once is usually someone who did not know that PIN, and next time they may be entering a different address entirely.

- [ ] **Step 2: Build the cascade's three steps**

State → district → village name. Each step reveals the next; changing an earlier step clears the later ones. A person who picks the wrong district must not be left with a stale village selection — that is how a customer ends up filed in a district nobody collects from.

Every result row shows **village, mandal, district, state and PIN**, because that is what lets someone recognise their own place. The PIN is displayed, never typed.

- [ ] **Step 3: 35 states and 773 districts are lists, not free text**

Both are pickers. Free text on either would reintroduce the spelling problem this whole change exists to remove.

- [ ] **Step 4: Test at three widths**

`pumpAtWidths` + `expectNoLayoutFault` at 390/820/1440. Overflow is this codebase's recurring shipped bug — four times, always a bare unflexible child beside a flexible one, invisible to `flutter analyze`.

Also test: changing state clears district and village; fewer than 3 letters shows no results; picking emits the village; editing after picking emits null.

---

### Task 4: Adopt it, and rewrite the guards

**Files:** the eleven consumer screens, `lib/shared/widgets/add_village_sheet.dart`, `test/village_search_rule_test.dart`, `test/village_lookup_guard_test.dart`.

**This is the task with eleven consumers. It is where this plan's risk lives.**

- [ ] **Step 1: List them and confirm the list**

```bash
grep -rln "ManaVillagePickerField\|searchByPin\|manaShowAddVillageSheet" lib --include=*.dart
```

Expected: `ag_004`, `cw_006`, `iw_005`, `lr_004`, `ow_000`, `ow_004`, `ow_012`, `ow_014_profile_completion`, `ow_016`, `ow_018`, plus `add_village_sheet.dart` and `village_picker_field.dart`.

**If the list differs, stop and report.** A twelfth consumer means this plan's premise is wrong and the owner needs to know before code is written.

- [ ] **Step 2: Migrate them one at a time**

Each screen swaps `ManaVillagePickerField` for `ManaVillageSearchField`. The callback shape is identical, so the surrounding code should not change. A screen that collected a PIN separately keeps doing so — PIN entry is not being taken away.

- [ ] **Step 3: `add_village_sheet` — the one that is not a swap**

Adding a village the directory never recorded currently takes a PIN, and in PIN mode it still should. In CASCADE mode it takes state, district and mandal from the current selection instead, so a village added that way lands in the chosen district rather than wherever a typed PIN pointed. Both routes must reach `app.add_location_if_missing` with a consistent shape — read it before changing what is passed.

- [ ] **Step 4: Extend both guards to cover both rules**

`village_search_rule_test.dart` pins the PIN + 3-letters rule across its copies. **Keep every existing assertion** — that rule is still live — and **add** assertions for the cascade rule: 3-letter minimum, prefix before substring, state and district required.

`village_lookup_guard_test.dart` ensures a village search reads the LGD reference rather than `locations`. That intent now applies to two paths; extend it to cover the cascade as well.

**Do not weaken either to get green.** Two search rules coexist now, so both guards protect more than before, not less. If either ends up protecting less, say so explicitly with the reason.

- [ ] **Step 5: Delete nothing**

`searchByPin` and the PIN mode stay. There is no dead code to remove in this plan — the earlier draft's deletion step was removed when PIN search was kept. If you find something genuinely orphaned, report it rather than deleting it as part of this task.

---

### Task 5: Walk it on the handset

**Files:** none.

- [ ] Build, install, and enter an address on a real phone BY PIN first, confirming the default path is unchanged from build 5.
- [ ] Then switch to cascade mode and enter another address.
- [ ] Find a village you know. Confirm the row shows mandal, district, state and PIN.
- [ ] Pick the wrong district deliberately, then correct it — the village selection must clear.
- [ ] Type three letters in the biggest district you can find and confirm the list is short and arrives quickly.
- [ ] Add a village that is not in the directory and confirm it lands in the selected district.
- [ ] Report what was verified and how, separately from what was changed.

---

## Self-Review

**Decisions this plan encodes**, all the owner's: cascade rather than name-only search; state then district then village; minimum 3 letters; no cap; prefix first with substring fallback; PIN removed from entry but kept in data and display.

**Placeholders.** Task 2 and 3 describe behaviour rather than quoting widget code, deliberately — earlier plans in this project invented constructor signatures three times and implementers had to arbitrate. The contracts are named exactly; the code is read from the files.

**The risk is Task 4.** Eleven consumers of one widget, in a codebase whose recorded regressions are overwhelmingly "some call sites updated, the rest silently broke". Hence the explicit stop if the list differs.

**What this plan does not do.** It does not touch the 10,241 AP place-names still under two or more districts. It does not need to: the cascade makes the person choose the district, which is the resolution those rows were waiting for.

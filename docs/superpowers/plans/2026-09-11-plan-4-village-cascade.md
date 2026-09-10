# Plan 4 — village address by cascade, not by PIN

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PIN-code-first address entry with a cascade — state, then district, then village name — so somebody who does not know their postal code can still find their own village, and so the district ambiguity that has plagued this data is resolved by the person rather than inferred.

**Architecture:** One index makes the cascade possible at all. A new data-layer path serves three steps (states, districts in a state, villages in a district matching a prefix). A new picker widget replaces the PIN+village pair, and the eleven screens that use the old one adopt it.

**Tech Stack:** Flutter, Riverpod, Supabase/PostgREST, `flutter_test`.

## Global Constraints

- **The PIN is not deleted from the DATA, only from the ENTRY.** `lgd_villages.pincode` still exists, still displays in a result row, and is still stored on the address. Only the "type your PIN first" step goes.
- **Money paths are untouched.** No file matching `*_ledger*`, `*_collection*`, `*_loan_math*` is modified.
- `flutter analyze` clean on every touched file. Full `flutter test` green after every task — baseline **2,245 passing**.
- **The two guard tests are REWRITTEN to the new rule, never loosened.** `village_search_rule_test.dart` and `village_lookup_guard_test.dart` exist because the search rule had drifted across three copies. The rule is changing; the guarding is not.
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

**Files:** Create `lib/shared/widgets/village_cascade_field.dart` and its test.

**Interfaces:**
- Consumes: Task 2's three methods.
- Produces: `ManaVillageCascadeField({required ValueChanged<ManaVillage?> onPicked, String? label})` — **deliberately the same callback shape as `ManaVillagePickerField`**, so Task 4's eleven adoptions are a swap rather than a rewrite at each site.

- [ ] **Step 1: Read what you are replacing**

`lib/shared/widgets/village_picker_field.dart` — a PIN field and a query field. Match its callback contract exactly, including emitting `null` when the person edits away a chosen village.

- [ ] **Step 2: Build the three steps**

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

Each screen swaps `ManaVillagePickerField` for `ManaVillageCascadeField`. The callback shape is identical, so the surrounding code should not change. Where a screen also collected a PIN separately, that field goes.

- [ ] **Step 3: `add_village_sheet` — the one that is not a swap**

Adding a village the directory never recorded currently takes a PIN. It now takes state, district and mandal from the cascade's current selection, so a manually added village lands in the right place instead of wherever a typed PIN pointed. Read `app.add_location_if_missing` before changing what is passed to it.

- [ ] **Step 4: Rewrite both guards to the new rule**

`village_search_rule_test.dart` pins the old PIN+3-letters rule across its copies. Rewrite it to pin the new rule: 3-letter minimum, prefix before substring, state and district required. `village_lookup_guard_test.dart` ensures a search reads the LGD reference rather than `locations`; keep that intent, update it to the cascade.

**Do not weaken either to get green.** If a guard now protects less than it did, say so explicitly with the reason.

- [ ] **Step 5: Delete what is genuinely dead**

Once nothing calls `searchByPin`, remove it and `village_picker_field.dart`. Confirm by grep, not by assumption. If something still calls them, leave them and report what.

---

### Task 5: Walk it on the handset

**Files:** none.

- [ ] Build, install, and enter an address through the cascade on a real phone.
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

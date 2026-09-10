# Plan 5 — operating states and a local village cache

Date: 2026-09-11
Status: **decisions taken, plan not yet written.** Blocked behind Plan 4 by the
owner's instruction ("finish plan 4 first").

## The idea

An Owner chooses which **states** their business operates in, before creating
operating areas. Only those states' village rows reach the handset, instead of
all 767,191 LGD rows. Village search then runs against that local subset.

## Why it works — measured 2026-09-11

| Scope | Rows | Raw text |
|---|---|---|
| Andhra Pradesh | 30,367 | 1.76 MB |
| Telangana | 21,384 | 1.04 MB |
| **AP + Telangana** | **51,751** | **~2.8 MB** |
| Uttar Pradesh (largest single state) | 113,813 | 5.59 MB |
| All 35 states | 767,191 | ~40 MB |

A realistic operating footprint is under 3 MB. That is the whole case for the
idea, and it is why the answer to "will this work" is yes.

## Decisions taken

**1. No local database.** Decided by the owner. 52,000 rows of short strings
fit in memory; prefix-filtering them in Dart costs a millisecond or two. So:
fetch once, hold in memory, filter in Dart.

This is not merely sufficient, it is safer. This project lost `file_picker` to
an AGP 9 build failure, and `lib/shared/photo_compression.dart` records in its
own header that it is pure Dart *deliberately* for that reason. Adding
`sqflite` would reintroduce that class of risk to solve a problem plain Dart
already solves. SQLite would only earn its place if all 35 states had to be
available offline — which is precisely what this design avoids.

**2. Operating states get built.** They do not exist today. `operating_areas`
is village-level: it holds a `location_id` into `locations`, and no table or
column anywhere records a state. So this needs a schema change plus the UI to
choose states before areas.

**3. Only the Owner may choose or add states** — in both a pre-existing
business being migrated and a running one. An Agent inherits the business's
states and cannot change them.

The consequence to design for, rather than discover: an Agent standing just
over a district line, at a customer whose village is in a state the Owner did
not select, has **no way to proceed and no way to fix it themselves**.
That must fail legibly — telling the Agent to ask the Owner to add the state —
not silently return no results, which would read as "your customer's village
does not exist".

## Why this waits for Plan 4

Plan 4's Task 2 produces the seam this swaps behind:

- `states()`
- `districtsIn(String state)`
- `searchVillages({state, district, query})`

The cascade UI does not care whether those read PostgREST or a local list. So
Plan 5 changes one file rather than the interface or the screens. Redirecting
Plan 4 now would leave a half-built cascade and a half-built cache, neither
working.

## Open question for Plan 5

**Staleness.** LGD data changes, and this project has already been bitten by
it — a migration named *"two district spellings and two districts that never
existed"* exists because of it. A cached copy needs a version and a refresh
path, or a handset will keep offering a district that was renamed a year ago.
Not yet decided: what triggers a refresh, and what a stale cache is allowed to
serve in the meantime.

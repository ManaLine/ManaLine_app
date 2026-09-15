# Analytics: what we would ask, and what must never leave the handset

**Status: DECIDED AND BUILT 2026-09-15 — no SDK.** Task 5 of
`docs/superpowers/plans/2026-09-15-production-readiness.md`.

**What was built:** `migration_furthest_step` and `migration_step_touched_at`
on `businesses`, written by `app.set_migration_wizard_step`, in migration
`20260915133840`. No SDK, no new dependency, nothing leaving the handset that
was not already there.

**Why that, of the three options.** `migration_wizard_step` already existed but
answers the wrong question: it follows an Owner BACKWARDS when they navigate
back, so it says where somebody is rather than how far they got. And without a
timestamp, "stopped at step 4" cannot be told from "is on step 4 right now" —
abandonment is a question about time, not position. Two columns fix both.

Verified by invocation in a rolled-back transaction: set to 6, then back to 2 —
current becomes 2, furthest stays 6, touched_at set.

**The question it answers**, runnable today:

```sql
select migration_furthest_step, count(*), max(migration_step_touched_at)
from businesses
where migration_locked = false
  and migration_step_touched_at < now() - interval '14 days'
group by 1 order by 1;
```

The reasoning that led here is kept below.

---

## Why this is a privacy question before it is a product one

Every screen in this app carries somebody's name, village, phone number and
outstanding balance. The people in that database are villagers who signed up
to borrow money, not to be measured. Most could not meaningfully be asked, and
several cannot read the language a consent notice would be written in.

A general-purpose analytics SDK dropped into a Flutter app does, by default,
roughly the opposite of what that implies: automatic screen tracking, device
identifiers, session recording in some products, and a default endpoint
outside India.

So the question is not "which analytics tool". It is **what single question do
we want answered**, and what is the least data that answers it.

## The one question worth answering

**Where do Owners abandon migration?**

That is the highest-value unknown in the product right now. Bringing a
pre-existing book across is the longest, hardest flow in the app, it is the
first thing a new business does, and if it fails they never become a user at
all. The whole one-at-a-time door was built this month on a *guess* about that
flow, and nothing measures whether the guess was right.

Everything else — daily active use, collection counts, feature adoption — is
already visible in the database itself. `businesses`, `loans`, `collections`
and `day_ledger` are a better product-analytics source than any SDK, and they
are already yours, already in India, and already governed by RLS.

**That is worth saying plainly: most of what an analytics tool would tell you,
a SQL query would tell you better, with no new data leaving the handset.**

## What would actually need a client event

Only things that happen *before* a row is written:

| Event | Why a query cannot answer it |
|---|---|
| `migration_step_reached` | An abandoned wizard writes nothing |
| `migration_step_abandoned` | Same |
| `one_by_one_vs_wizard_chosen` | The choice is not persisted anywhere |
| `loan_entry_validation_failed` | The row is refused, so it never exists |

Four events. No screen names, no free text, no identifiers beyond
`business_id`.

## What must never leave the handset

- Any `person_id`, MLID, name, phone, Aadhaar, village or address
- Any money amount — balance, collection, BF, instalment
- Screen names or route paths, which leak who is being looked at
- Automatic screen tracking, session replay, crash screenshots
- The device advertising identifier

`business_id` is the one identifier I would argue for keeping, because
"abandoned at step 4" is uninteresting without knowing whether it was one
business five times or five businesses once.

## Where it would go

**Recommendation: self-hosted, or an India region, or nothing.**

Not because a US endpoint is illegal, but because this data is about people who
cannot be asked, and "we sent the minimum, and we sent it somewhere we control"
is a defensible sentence in a way that "we used the default" is not.

If neither is available, **the honest answer is to add no SDK at all** and
answer the migration question with a database column instead —
`migration_progress` already tracks wizard position, and a nullable
`abandoned_at_step` would answer most of it with zero new infrastructure.

---

## The three answers I need from you

1. **Is the migration-abandonment question the one you actually want answered?** If there is a different one, the whole shape changes.
2. **Self-hosted, India region, or no SDK?** If the answer is "no SDK", I would do the `migration_progress` column instead and this document closes.
3. **Is `business_id` acceptable to send?** If not, the events still work, they just cannot distinguish one business struggling five times from five businesses struggling once.

## What I would do if you said "just decide"

Add no SDK. Extend `migration_progress` with the furthest step reached and a
last-touched timestamp, and answer the question with SQL. It is smaller, it
ships sooner, nothing leaves the handset, and it is reversible — which is more
than can be said for a tracking SDK once it is in a release.

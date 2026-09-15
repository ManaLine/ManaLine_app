# Visual identity: the direction

**Status: APPLIED TO ONE SCREEN — the collection round, 2026-09-16.**
`lib/shared/collection_round_view.dart`, shared by AG-002 and OW-006, so both
rounds got it from one widget. What landed is at the bottom, under "The first
application". Everything between here and there is the direction as it was
decided, unchanged.

**Was: DIRECTION PROPOSED, NOT YET APPLIED.** Task 12 of
`docs/superpowers/plans/2026-09-15-production-readiness.md`, whose own entry
says: *"A direction decided once and applied is worth more than ten screens
each improved separately."* This is that direction. Applying it is a separate,
larger piece of work.

Grounded in looking at the running app on a 375×812 viewport, not in theory.

---

## What is already right, and is not being changed

**The amber primary.** 8.48:1 against its ink, and chosen for the reason
hi-vis clothing is that colour: a high-luminance surface with dark marks
survives glare. Glare adds a roughly constant luminance to every pixel and
compresses every contrast ratio toward 1, so the pairs that stay legible
longest are the ones that started highest. This is the most defensible colour
decision in the app.

**`brandDeep` for anything text-bearing**, at 7.19:1. The lighter `brand` is
for icons, borders and selected states and is never a background under text.

**Manrope and Inter, bundled rather than fetched.** First paint does not
depend on a network request in exactly the conditions this app is built for.

**"EVERY ₹ COUNTS".** This is already the identity and nobody seems to have
noticed. Wide-tracked small caps, and it puts the rupee sign — the actual
subject of the product — inside the tagline. It is specific, it is not
borrowable by another app, and it appears **once**, small, on one screen.

## The problem, stated from the screenshot rather than from taste

On the workspace chooser, content occupies the **top 45%** of the screen and
the bottom 55% is empty grey. The same top-anchored pattern runs through the
app.

This is a one-handed app used standing at a door. The thumb is at the bottom.
Every primary action is as far from it as the layout can put it, and the space
where the thumb actually rests is the space the design leaves blank.

That is not a taste problem. It is the layout working against the posture the
product is used in.

---

## The direction: the line

The app is called MANA LINE. In this trade a **line** is two things at once:
the round an agent walks, and the ruled column of the paper ledger the app
replaces. `line_balance`, `line_repayment_index` and Line Score are already in
the schema. The word is the product's own, not a borrowed metaphor.

So the signature is **one amber hairline rule**, used with discipline and
nowhere else:

- under the screen title, where it says which line you are on;
- as the day's progress through a collection round — filled for what has been
  collected, hollow for what has not;
- nowhere decorative.

A 2dp rule costs nothing to render on a cheap handset, survives 2.0x text
because it is not text, and carries no translation. It is the cheapest
possible signature and the only one drawn from the product's own vocabulary.

**Deliberately not** any of: a cream-and-serif treatment, a dark surface with a
single acid accent, or hairline-ruled newspaper columns. Those are what gets
produced for any brief. The rule here is amber because amber is already the
functional decision, and horizontal because a ledger is.

## Three changes that follow from it

**1. Anchor actions low.** Primary actions move to the bottom of the screen,
inside thumb reach. The dead space moves to the top, where it costs nothing.
Measured, not asserted: the workspace chooser currently puts its first tap
target 40% of the screen height away from the thumb.

**2. Amounts become the typography.** Money is what people came to look at and
it is currently set at body size. Inter is already bundled and already has
tabular figures — using them means a column of amounts aligns like a ledger
instead of shimmering. Larger, tabular, right-aligned in lists. This is
identity that also makes the primary job easier, which is the only kind worth
having here.

**3. The tagline earns its place.** "EVERY ₹ COUNTS" appears on the one screen
nobody spends time on. It belongs where the app is idle and waiting — the
empty round, the finished day, the outbox with nothing in it. An empty screen
is an invitation, and this app already owns a good sentence for it.

## What is explicitly not proposed

No motion. No new palette. No new typeface. No illustration.

An agent opening this app is not being delighted; they are standing at a door
in the sun with a cash bag, and every millisecond of animation is a
millisecond before they can read a number. Restraint here is the design
decision, not the absence of one.

## Why this is not being applied in the same pass

Seventy-one screens, `expectNoLayoutFault` at four text scales in two
languages, and Telugu strings that run consistently longer than the English
the layouts were drawn against. A layout change applied blind across all of it
would trade a measured 5/10 for an unmeasured one.

The honest sequence is: agree the direction, apply it to **one** screen —
the collection round, which is where an agent spends the day — test that on a
handset, and only then decide whether it earns the other seventy.

---

## The first application

Chosen because this document said to choose it: *"apply it to **one** screen —
the collection round, which is where an agent spends the day — test that on a
handset, and only then decide whether it earns the other seventy."*

**The line.** One 2dp amber hairline under the date, filled for the doors
collected and hollow for the rest. It is the signature, and it is also the
answer to a question the screen could not previously answer: the round listed
every door and said nothing about progress, so an agent halfway down a village
counted the rows they had already walked past.

Counted over the **whole round**, not the filtered view — narrowing to one
village must never make the day look finished.
`test/collection_round_line_test.dart` pins that, because it is exactly the kind
of thing that regresses quietly and ends a round two villages early.

**The amounts were the real find, and they were not a taste problem.** This
document asked for "amounts become the typography". On this screen the balance
rendered at **13sp** — below the **16sp floor `ManaAmount` itself declares for
money** — and neither figure used tabular figures, so a column of amounts did
not align. Both go through `ManaAmount` now: the floor, tabular figures, a
screen-reader label that says "rupees" rather than spelling the glyphs, and no
wrapping mid-number.

**Measured while there, and the number to carry into the next rating:** `lib/`
holds **180 `manaRupees(` call sites against 16 `ManaAmount` usages**, 79 of
them money interpolated into a `ManaText`. The component that exists to stop
money being set as small text is used in under a tenth of the places it applies.
A guard against the pattern would need a 79-entry exemption list today, which is
a chore rather than a guard — so it is recorded as a figure to move instead of
being dressed up as one.

**The tagline.** "EVERY ₹ COUNTS" sits under a finished round, and deliberately
**not** under "nothing matched what you typed" — one is the app idle at the end
of a day, the other is somebody mid-search, and a brand mark over a failed
filter is the app congratulating itself on the agent's behalf.

**Anchoring actions low was NOT applied here**, which is a decision rather than
an omission. This document's example is the workspace chooser, where a single
primary action sits 40% of the screen height from the thumb. This screen's
primary action is per-row — a Collect button on every door — so there is no one
control to move, and pushing the list down would put the first door furthest
from the eye. The direction still holds for the screens it was written about.

**What it cost.** One new key, `round_progress`, which has **no Telugu**:
English falls back, and English is what a Telugu reader sees. The test fixture
mirrors that rather than inventing a width no handset will draw, and
`mana_harness_test.dart` now names such keys in a list checked in **both**
directions — a key missing Telugu must be on it, and a key on it must still be
missing Telugu — so the list cannot rot into a place where checks go to die.

**Not yet judged on a handset.** This document's sequence ends "test that on a
handset, and only then decide whether it earns the other seventy", and that step
has not happened. Four text scales, two languages and four behaviour tests are
not the same as standing outside with the screen in the sun.

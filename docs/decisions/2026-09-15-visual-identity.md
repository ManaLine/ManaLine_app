# Visual identity: the direction

**Status: DIRECTION PROPOSED, NOT YET APPLIED.** Task 12 of
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

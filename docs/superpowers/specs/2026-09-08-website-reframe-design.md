# MANA LINE website — reframe

Date: 2026-09-08
Status: awaiting approval. Supersedes the shape decided in
`2026-09-07-website-design.md` §1 and §3.

## What changed, and why this is a reframe rather than an edit

The earlier spec built "the app, in a browser": one codebase, every route
reachable, unconverted screens rendered as a centred phone-width column. That
was the right shape for the goal it had — make the existing app usable at a
desk — and it is the wrong shape for the goal now stated:

> the website shouldn't look like an app copycat

A website that is the app, clamped, is by construction a copy of the app. So
the site becomes a promotional product with a small authenticated area inside
it, and the app stays where it belongs — on a handset.

Three decisions were taken by the owner and are recorded here as given:

1. **The desk-width transaction-history work is deleted**, not merely unrouted.
2. **A separate web entrypoint** with its own router, rather than an allowlist
   enforced inside the single router.
3. **Neither store listing exists yet**, so store badges are "coming soon" and
   the APK is a direct download.

## 1. What the website is

Two artifacts on one origin, as before — but the balance between them inverts.
The public half is now the larger half.

```
/            ->  site/       static HTML, the promotional product
/app/        ->  build/web/  a RESTRICTED Flutter build, five workflows only
```

The public half is static because a Flutter-rendered marketing page costs a
visitor on a rural connection ~5.8 MB before the first word appears, and paints
into a canvas no search engine reads. That measurement has not changed.

## 2. The five workflows, and who they belong to

The site's logged-in area serves **all four roles**. What each role may reach
differs, because "accounts" means something different to each.

### The reading this rests on — correct it if wrong

The instruction was "view accounts only (no history)" and "remove all the other
stuff like collection entries, loans".

Taken as: **viewing what you owe or are owed is in; doing the day's work is
out.** A Customer seeing their own loan balance is an account view. Recording a
collection, issuing a loan, closing a day, settling an agent — those are field
operations, and they belong on the handset.

If "no loans" was meant to exclude a Customer seeing their own loan, the
Customer's account view disappears entirely and item 2 becomes Owner-only. That
is a one-line change to the allowlist below, not a redesign — but it must be
decided before implementation, not after.

### The allowlist

| Item | Owner | Agent | Customer | Investor |
|---|---|---|---|---|
| 1 Login / registration | LR-001…013 (shared) |||| 
| 2 Accounts | OW-013 | — | CW-004 | IW-003 |
| 3 Pre-existing business | OW-018, bulk onboarding, `/import` | — | — | — |
| 4 Subscription | `/subscription` | — | — | — |
| 5 Profile & settings | OW-016 | AG-009 | CW-006 | IW-005 |
| 5 Shared settings | `/settings`, `/appearance`, `/about`, per-role settings routes ||||

**The Agent has no account view.** An agent's standing is their BF and their
settlement with the owner, and both are field operations rather than a
statement. If that is wrong, AG-006 is the screen to add.

Everything else is absent from the web router: all four dashboards, collection
mode, new loan, loan distribution, day closure, reports, workforce, investor
management, customer management, group loans, cheti, trash, admin, support.

## 3. The web home — a screen that does not exist yet

Excluding the four dashboards leaves nowhere to land after login. OW-001,
AG-001, CW-001 and IW-001 are built around collections and loans — the precise
content being removed — so they cannot be reused, and blocking them without a
replacement would strand every user at the moment they sign in.

So the web gets **one new screen**: a hub that names the permitted destinations
for whichever role signed in, and says plainly that the day's work happens in
the app, with a link to download it.

This is the single most important screen for the stated goal. It is the first
thing a signed-in person sees, it exists only on the web, and it is what makes
the site read as its own product rather than a reduced copy of the app.

It is NOT a dashboard. It carries no figures, no charts, no counts — a number
on it would be a smaller version of the thing being removed.

## 4. Why a separate entrypoint, and the risk it carries

`lib/main_web.dart` with `lib/app/web_router.dart`, registering only the
allowlist. `ManaLineApp` becomes router-parameterised.

The owner chose this over an allowlist inside the existing router, having been
told the trade: **this project's core invariant is one route per screen ID in
one router**, and two routers drift the first time somebody adds a screen.

That risk is real and is mitigated, not accepted:

`test/web_router_guard_test.dart` fails if
- a route in the web router is absent from the main router,
- the same screen ID resolves to a different screen in the two routers,
- or the web router's route set differs from a declared allowlist constant.

The allowlist constant is the spec, expressed as code. Adding a screen to the
web then requires editing the allowlist deliberately, which is the point.

Builds become `flutter build web -t lib/main_web.dart`. Android is untouched:
`lib/main.dart` and `manaRouter` keep their exact current behaviour.

## 5. The public site

`site/`, plain HTML and one stylesheet. No framework, no build step.

| Page | Holds |
|---|---|
| `index.html` | What MANA LINE is, who it is for, the five languages, the promotional case |
| `videos.html` | A slideable carousel — **dummy slides for now**, real videos later |
| `plans.html` | Tiers and caps, generated from `kOwnerTiers`, **no rupee figures** |
| `download.html` | The APK, plus "coming soon" store badges |
| `legal.html` | The Terms & Privacy PDF already in `assets/legal/` |
| `contact.html` | Email, phone |

### 5.1 Videos (item 6)

A slideable carousel with placeholder slides, built so that replacing a slide's
content is a one-line edit and adding a real video is dropping in an embed. It
must work without JavaScript for its basic reading order — a carousel that
shows nothing when a script fails is worse than a list.

### 5.2 Store redirects (item 7)

Neither listing exists. Both badges render in a visibly disabled "coming soon"
state, each wired to a single constant. When a listing goes live, one URL
changes and the badge activates. **No dead links, and no claim that the app is
on a store when it is not.**

The APK is the working download today.

### 5.3 Promoting the app (item 8)

What the space is for, in priority order:

1. **What this is, in one line, above the fold.** A local lender arriving from a
   WhatsApp link decides in seconds.
2. **The problem it replaces** — the paper ledger, the missing collection, the
   figure nobody can reconstruct. This audience recognises the problem faster
   than any feature list.
3. **Proof it is real**: screenshots of the actual app, the five languages
   named, the fact that agents work offline in the field.
4. **What it costs** — tiers and caps, honestly, with no figure until billing
   exists.
5. **Get it** — the APK, and the store badges when they are real.
6. **Who stands behind it** — contact, and the legal terms.

Constraints on all of it: the app's own palette and type, no stock photography
of people who are not users, no invented testimonials, no invented metrics.
Nothing on the public site may claim a capability the app does not have —
`README.md` has a "Not yet true" section, and it is the reference for what may
be said.

## 6. What is deleted

`lib/design/components/mana_ledger_table.dart` and its test; the table branch in
`lib/shared/ledger_history_view.dart`; the history routes in `kManaWideRoutes`;
two comments that reference the table.

**Kept**, because they are not history-specific and items 2 and 5 use them:
`breakpoints.dart`, `ManaFormGrid`, `ManaAdaptiveShell`, `ManaWebFrame`, and
OW-013's card grid.

Roughly −800 lines and ~12 tests.

## 7. What this does not become

No SSR. No JS framework. No PWA offline mode. No billing. No public prices. No
analytics or tracking beyond what the host provides by default. No account
creation flows that differ from the app's — registration is the app's own
LR-004, not a second implementation.

## 8. Open decision

**Does a Customer see their own loan account on the website?** §2 assumes yes,
on the reading that viewing a balance is not "doing loans". If no, CW-004 and
IW-003 leave the allowlist and item 2 becomes Owner-only.

Nothing else in this document depends on the answer.

# Plan 3b — the public site

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the promotional half of manaline.in — static pages that explain what MANA LINE is, show what it will cost, hold the videos when they exist, and get the app onto a phone.

**Architecture:** Plain HTML and one stylesheet in `site/`. No framework, no build step, no dependency to upgrade. The one generated file is the plans page, produced from `kOwnerTiers` so the published tiers cannot drift from the app's.

**Tech Stack:** HTML, CSS, a little vanilla JS for the carousel. Dart for the plans generator. Cloudflare Pages.

**Spec:** `docs/superpowers/specs/2026-09-08-website-reframe-design.md` §5

## Global Constraints

- **Nothing on this site may claim a capability the app does not have.** `README.md`'s "Not yet true" section is the reference, and it is not optional reading.
  - **Do not claim offline working.** README: *"Offline sync is not wired… For an app whose whole point is poor connectivity this is the largest remaining gap."* The spec's own §5.3 listed offline as proof; that was wrong and is corrected here.
  - Do not claim interest accrual — payments subtract from one balance, nothing accrues on its own.
  - No invented testimonials, no invented metrics, no stock photography of people presented as users.
- **No prices.** Tiers and caps only. Billing does not exist, and a published figure is an offer.
- **No store listings exist.** Badges are visibly "coming soon", each wired to one constant.
- **Copy is written, not transcribed.** No phrase from this plan or the spec reaches a page verbatim. The reader is a local lender deciding whether this helps them get their money back — not someone who wants the software explained.
- Brand colours come from the app so the two read as one product: brand `#007ACC`, deep `#005A99`, faint `#E3F2FB`, accent `#FFB616`. Take the rest from `lib/design/tokens/colors.dart` rather than inventing.
- English only. The five languages are a claim about the APP, not a promise about these pages.
- Every page must be legible and navigable with **JavaScript disabled**. JS may enhance; it may not gate content.
- UTF-8, no BOM. `test/source_encoding_test.dart` is widened to `site/` in Task 5.
- Never commit credentials.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `site/index.html` | The promotional case |
| `site/plans.html` | **Generated.** Tiers and caps, no figures |
| `site/videos.html` | Slideable carousel, placeholder slides |
| `site/download.html` | APK, and coming-soon store badges |
| `site/legal.html` | Terms & Privacy |
| `site/contact.html` | Email, phone |
| `site/style.css` | One stylesheet, brand tokens at the top |
| `site/site.js` | Carousel only. Nothing else depends on it |
| `tool/gen_site_plans.dart` | Generates `plans.html` from `kOwnerTiers` |
| `test/site_plans_sync_test.dart` | Fails if the page drifts, or if a price appears |
| `site/_headers`, `site/_redirects` | Cloudflare Pages config |

**Modified:** `test/source_encoding_test.dart` (widen to `site/`).

---

### Task 1: The foundation and the home page

**Files:** Create `site/style.css`, `site/index.html`

**Interfaces:**
- Consumes: brand colours from `lib/design/tokens/colors.dart`.
- Produces: the stylesheet and page structure every later task reuses.

- [ ] **Step 1: Read what may be claimed**

```bash
sed -n '1,60p' README.md
```

Read the "Status" and "Not yet true" sections in full before writing a word of copy. **Offline working is not true.** Interest accrual is not true.

- [ ] **Step 2: Write the stylesheet**

Brand tokens as CSS custom properties at the top, taken from the app. One stylesheet for the whole site. Mobile-first — a substantial share of visitors will arrive on a phone from a shared link, and the site must be usable at 360px.

- [ ] **Step 3: Write the home page**

The priority order, which is the page's structure:

0. **A way in.** Sign In and Register, in the site header on **every page**, pointing at `/app/`. Added 2026-09-08 after the owner could not find them: the priority order below ran from "what this is" to "who stands behind it" and never included a door to the authenticated half. The site has a logged-in area serving four roles, and a returning Owner landing on the home page had no way to reach it. Signing in is not a promotional step, which is why it belongs in the chrome — persistent, visible, and not competing with the download action for the same space.
1. **What this is, in one line, above the fold.** Someone arriving from a WhatsApp link decides in seconds.
2. **The problem it replaces** — the paper ledger, the collection nobody recorded, the figure that cannot be reconstructed. This audience knows this problem better than any feature list can describe it.
3. **Proof it is real** — real screenshots of the app, the five languages, the four roles. Not offline.
4. **What it costs** — a pointer to the plans page, honest that billing is not live.
5. **Get it** — a pointer to download.
6. **Who stands behind it** — contact and legal.

Screenshots: take them from the running app rather than mocking them up. If that is not possible in this task, leave a clearly-marked placeholder and say so — **do not fabricate a screenshot**.

- [ ] **Step 4: Verify without JavaScript**

Disable JS and confirm the page reads top to bottom with working navigation.

- [ ] **Step 5: Commit**

```bash
git add site/ && git commit -m "A page that says what this is before it says what it does"
```

---

### Task 2: The plans page, generated

**Files:** Create `tool/gen_site_plans.dart`, `site/plans.html`, `test/site_plans_sync_test.dart`

**Interfaces:**
- Consumes: `kOwnerTiers` from `lib/features/owner_workspace/state/subscription_state.dart`.
- Produces: a generated page and a guard.

The tiers, for reference — **caps only, no money**:

| Tier | Agents | Customers | Investors |
|---|---|---|---|
| Starter | 4 | 150 | 20 |
| Growth | 10 | 500 | 75 |
| Business | 25 | 1,500 | 200 |
| Enterprise | unlimited | unlimited | unlimited |

- [ ] **Step 1: Write the generator**

`tool/gen_site_plans.dart` reads `kOwnerTiers` and emits the tier table into `site/plans.html`. It emits `name`, `agents`, `customers`, `investors`. **It must not emit `monthly` or `yearly`.**

- [ ] **Step 2: Write the guard first, and watch it fail**

`test/site_plans_sync_test.dart` asserts:
1. every tier name in `kOwnerTiers` appears in `site/plans.html`;
2. every cap figure matches;
3. **no rupee symbol and no price string appears anywhere in the file.**

Assertion 3 is the one that matters. It makes publishing a price something that **fails a test**, rather than something that slips through the next time somebody regenerates the page.

Run it before the page exists, watch it fail, record the output.

- [ ] **Step 3: Generate, and make the page honest**

The page states plainly that billing is not live and nothing is being charged. The app's own `planned_prices_note` says this to signed-in Owners; the public page needs its own wording to the same effect.

- [ ] **Step 4: Verify and commit**

```bash
dart run tool/gen_site_plans.dart
flutter test test/site_plans_sync_test.dart
git add -A && git commit -m "Plans come from the app's own tiers, and a test refuses to let a price onto the page"
```

---

### Task 3: The videos page

**Files:** Create `site/videos.html`, `site/site.js`

There are no videos yet. This is a real carousel with placeholder slides, built so that dropping in an embed later is a one-line edit.

- [ ] **Step 1: Build the carousel**

Requirements:
- **It must work with JavaScript disabled.** Without JS the slides render as a readable vertical list. A carousel that shows nothing when a script fails is worse than no carousel.
- Swipeable on touch, arrow keys on desktop, and visible previous/next controls. Not swipe-only — a mouse user must be able to drive it.
- Each slide is a titled placeholder describing the video that will go there: what the app is, registering, adding a customer, recording a collection, closing the day. Those are the videos worth making, and naming them now makes the page useful before they exist.
- No autoplay. No carousel that moves on its own.

- [ ] **Step 2: Make replacement obvious**

A comment at the top of the slide markup saying exactly what to replace and where. The next person doing this will not have read this plan.

- [ ] **Step 3: Verify and commit**

Check with JS on and off, and at 360px. Commit.

---

### Task 4: The download page

**Files:** Create `site/download.html`

- [ ] **Step 1: One constant per store**

Two constants at the top of the page's script or markup — `PLAY_STORE_URL`, `APP_STORE_URL` — both empty. Empty means the badge renders **visibly disabled with a "coming soon" state**. Setting one URL activates that badge and nothing else changes.

**No dead links. No badge that looks live and goes nowhere. No claim the app is on a store when it is not.**

- [ ] **Step 2: There is no download yet**

**Changed 2026-09-08 by the owner: do NOT host the APK. Testing is unfinished.**

This step originally read "the APK is the real download". It is not. Handing a build to strangers before its own testing is complete is how a lending app loses someone's money in a way nobody can reconstruct — and this app's own guard culture exists precisely because that class of failure is expensive here.

So the page states plainly that MANA LINE is in testing and not yet publicly available. No APK link, no release asset, no file anywhere on the site.

The tone is the whole difficulty. This must read as a product being built carefully, not as a product that is late or broken. It is neither — it is being tested before it is handed to people whose money depends on it, which is a reason to trust it rather than to wait doubtfully.

**Do not invent a way to be notified.** There is no mailing list, no signup backend and no CRM. A form that collects an address and drops it is worse than no form. Point at the contact page, which is a real person.

- [ ] **Step 3: iPhone**

There is no iOS build. Say so plainly rather than leaving an inert badge to imply one is coming imminently.

- [ ] **Step 4: Verify and commit**

---

### Task 5: Legal, contact, and the encoding guard

**Files:** Create `site/legal.html`, `site/contact.html`; modify `test/source_encoding_test.dart`

- [ ] **Step 1: Legal**

Serve `assets/legal/MANALINE_Terms_and_Privacy_v1.0.pdf`. Copy it into `site/` rather than linking into the app's asset tree — the two are deployed separately.

- [ ] **Step 2: Contact**

Email and phone. `manaline.in@gmail.com` is the address on record; confirm before publishing, since putting a personal address on a public page is not reversible once indexed.

- [ ] **Step 3: Widen the encoding guard**

`test/source_encoding_test.dart` covers `lib/`, `tool/` and `pubspec.yaml`. Add `site/`, scanning `.html`, `.css` and `.js`. The rupee symbol and em dashes will appear in this copy, and mojibake on a public page is worse than in source — it is the first thing a stranger sees.

Confirm the guard's "scanned enough files" assertion still holds after the widening.

- [ ] **Step 4: Verify and commit**

---

### Task 6: Deploy

**Files:** Create `site/_headers`, `site/_redirects`

- [ ] **Step 1: Routing**

`/` serves `site/`, `/app/*` serves the Flutter build from `lib/main_web.dart`.

**No SPA rewrite is needed.** The app uses hash routing — verified in Plan 1 — so `/app/#/ow-013` never sends the route to the server. Do not add a rewrite for a problem that does not exist; confirm hash routing still holds before relying on this.

- [ ] **Step 2: Headers**

A Content-Security-Policy. The spec pairs it with the session-storage decision from Plan 1 — the JWT lives in `sessionStorage`, and CSP is the other half of that story.

- [ ] **Step 3: Document the deploy**

Write the steps down: what to build, with which entrypoint, which `--dart-define` values, and what to put where. Someone will do this on a day nobody remembers the details.

- [ ] **Step 4: Do not deploy without approval.** Publishing to a live domain is an outward-facing act. Present what would be published and stop.

---

### Task 7: Walk it

- [ ] Every page at 360px and 1440px, with JS on and off.
- [ ] Every link resolves — including the APK and the legal PDF.
- [ ] The plans page shows no price.
- [ ] Both store badges read as coming soon and neither navigates.
- [ ] The carousel works by touch, by arrow key and by button; and reads as a list with JS off.
- [ ] No claim on any page contradicts README's "Not yet true".
- [ ] Report what was verified and how, separately from what was changed.

---

## Self-Review

**Spec coverage.** §5 pages → Tasks 1–5. §5.1 videos → Task 3. §5.2 store redirects → Task 4. §5.3 promotion → Task 1 Step 3. §8 copy → Global Constraints.

**A spec error corrected here.** §5.3 listed offline working as proof the product is real. README's "Not yet true" says offline sync is not wired and calls it the largest remaining gap. The plan forbids the claim; the spec should be amended too.

**Placeholders.** Copy is described rather than written throughout, deliberately — writing marketing copy inside a plan produces text that reads like a plan. The constraints on it are specific and testable.

**No screenshots exist yet.** Task 1 Step 3 permits a marked placeholder and forbids fabricating one.

**Scope.** Seven tasks, one of which is verification. No task depends on a store listing existing.

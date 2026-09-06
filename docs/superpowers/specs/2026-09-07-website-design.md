# MANA LINE on the web — design

Date: 2026-09-07
Status: approved (design). Two decisions still open, listed in section 11.

## The problem

MANA LINE is an Android app. There is no web presence at all: no public page
that says what the product is, and no way for an Owner to do desk work — read
a statement, type in an old book, check which plan they are on — without a
handset in their hand.

Two audiences, and they are not the same person:

- someone who has never heard of MANA LINE and lands on a link,
- an Owner who already uses the app daily and wants a keyboard and a big
  screen for the paperwork parts.

Most users use the app. The website is not a replacement for it and is not
scoped as one.

## What was measured first

Nothing in this document rests on an assumption about whether Flutter web
works here. It was built before the design was written.

```
flutter build web --dart-define=SUPABASE_URL=x --dart-define=SUPABASE_ANON_KEY=y
Compiling lib\main.dart for the Web...   160.0s
OK Built build\web
```

| Fact | Value |
|---|---|
| The app compiles to web today, unmodified | exit 0, `build/web/main.dart.js` written |
| `main.dart.js` | 5,864,669 bytes |
| Routes in `lib/app/router.dart` | ~85 |
| Edge Function CORS | `Access-Control-Allow-Origin: *` — browser origins already work |
| Breakpoints in the design system | **zero** — no `MediaQuery...size.width` in `lib/design/` or `lib/shared/` |
| Plans in the database | **none** — the tiers are `kOwnerTiers`, a Dart const |
| `MaterialApp.router` already has a `builder:` | `lib/main.dart:166`, for text scaling |
| Files that touch a web-hostile API | 7 |

Two of these changed the design rather than decorating it. 5.8 MB ruled Flutter
out for the public pages. The absence of a plans table turned the pricing page
from a content task into a code-generation task.

**Compiling is not running.** The build succeeding says the graph resolves; it
says nothing about `camera` or `dart:io` at runtime. Section 6 is about that
gap, and it is the section most likely to be underestimated.

## 1. Shape

Two artefacts, one origin:

```
/          ->  site/       hand-written static HTML/CSS, no build step
/app/      ->  build/web/  the existing Flutter app, base-href /app/
/app/*     ->  rewrite to /app/index.html   (deep links)
```

The Flutter app does not fork. Same `lib/`, same router, same RLS, same Edge
Functions — a fifth platform target, not a second codebase.

**This is the load-bearing decision.** A separate web front-end would mean a
second implementation of the money rules, and a confidently wrong number on a
collection screen is the failure this project treats as a safety property. One
codebase makes that impossible by construction rather than by care.

The public site is static because of the 5.8 MB measurement: a Flutter-rendered
marketing page costs a visitor on a rural connection 5.8 MB before the first
word appears, and paints into a canvas that no search engine reads.

## 2. The public site — `site/`

Plain HTML and one stylesheet. No framework, no build step, no dependency that
needs upgrading later.

| Page | Holds |
|---|---|
| `index.html` | What MANA LINE is, who it is for, the five languages, screenshots |
| `plans.html` | The four tiers |
| `download.html` | The APK, and what Android needs in order to install it |
| `legal.html` | Serves `assets/legal/MANALINE_Terms_and_Privacy_v1.0.pdf` |
| `contact.html` | Email, phone |

### 2.1 The plans page is generated, not written

The tiers live in `lib/features/owner_workspace/state/subscription_state.dart`
as `kOwnerTiers`: Starter ₹99/₹999, Growth ₹199/₹1,999, Business ₹349/₹3,499,
Enterprise custom, each with agent/customer/investor caps. There is no
subscription table in any migration. The prices exist in exactly one place, in
Dart.

Typing them into HTML would make two copies of one fact, and the copy on the
public internet is the one that becomes a promise to a customer. So:

- `tool/gen_site_plans.dart` generates the plans table from `kOwnerTiers`.
- `test/site_plans_sync_test.dart` fails when `site/plans.html` stops matching.

Same pattern as `test/support/schema_snapshot.dart`: generated, guarded, never
maintained by remembering.

### 2.2 Publishing prices is an outward-facing act

The app currently says, in `planned_prices_note`: *"Nothing is being charged
yet. These are the planned prices, shown so you can see which one fits your
business."*

Showing a figure to a logged-in Owner and publishing it on the open web are
different acts — the second reads as an offer, and billing is not built. The
page therefore carries that same sentence verbatim, at the same prominence as
the figures.

If that is not wanted, the fallback is a plans page listing tiers and limits
with no rupee figures at all. That is a content switch in the generator, not a
redesign.

## 3. The centred column

Choice made: every screen stays reachable on the web; screens outside the five
workflows render as a centred, phone-width column rather than being blocked.

Blocking was considered and rejected. Login lands an Owner on OW-001, which is
not one of the five, and every one of the five is reached by navigating from a
screen that is not. Blocking the landing screen would force a web-only
dashboard to be invented — more work, not less, and a stranded Owner just
telephones.

**One insertion point.** `MaterialApp.router` already carries a `builder:` at
`lib/main.dart:166` for text scaling. The width clamp goes there. All ~85
routes inherit it from a single edit; there is no per-screen step to forget on
screen 61.

**Below 600 px the clamp is inert, so the Android build is unaffected.** That
property matters more than the feature it enables: it means shipping a website
cannot regress the app that people actually use.

## 4. Responsive, across the five workflows

New `lib/design/tokens/breakpoints.dart`, in the shape of the existing token
files. This is new ground, not a retrofit — the design system has no breakpoint
today.

| Workflow | Screens | Lines |
|---|---|---|
| 1. Login / registration | LR-001…013, 12 files | 4,980 |
| 2. History and accounts | `ManaLedgerHistoryView`, OW-013, OW-017 statement | ~640 |
| 3. Pre-existing business | OW-018, bulk onboarding wizard, `/import` | 3,622 |
| 4. Subscription plans | `/subscription` | 205 |
| 5. Profile and settings | OW-016, `SettingsScreen`, appearance, about | ~1,000 |

Roughly 20 screens, ~10,200 lines — a fifth of the app.

**History is free leverage.** `ow_017_transaction_history.dart` is a 32-line
wrapper around `ManaLedgerHistoryView`, which AG-010 also uses. Laying that
view out once makes the Agent's history responsive at no additional cost. It
also means the change has two consumers, so both get checked — the rule about
listing consumers before changing anything shared applies here by name.

**Overflow is this project's recurring shipped bug — four times, always a bare
unflexible child beside a flexible one, and invisible to `flutter analyze`.**
Widening layouts is precisely how it recurs. `expectNoLayoutFault` therefore
runs these screens at three widths, not one.

## 5. What this does not become

Out of scope, deliberately: no SSR, no JS framework, no PWA offline mode, no
billing integration, no responsive work on the other ~65 screens, no changes to
any money-path file.

## 6. The runtime holes

Four plugins have no web implementation. They compile and throw
`MissingPluginException` on first call. `dart:io` is worse: the web SDK ships it
as a stub that compiles and throws on use, which is why the build passed with
`dart:io` imported in three services.

Seven files, and two of the five workflows contain them:

| File | Breaks on | In the five? |
|---|---|---|
| `lib/shared/live_face_capture_screen.dart` | `camera`, `google_mlkit_face_detection` | Yes — customer onboarding |
| `lib/features/owner_workspace/state/import_service.dart` | `dart:io` | Yes — pre-existing business |
| `lib/features/owner_workspace/state/bulk_onboarding_service.dart` | `dart:io` | Yes — pre-existing business |
| `lib/features/owner_workspace/state/backup_export_service.dart` | `dart:io` | Yes — reached from Settings |
| `lib/shared/ledger_statement_service.dart` | `dart:io` | Yes — statements |
| `lib/shared/mana_biometric.dart` | `local_auth` | No |
| `lib/shared/mana_location.dart` | `geocoding` | No |

Each gets a `kIsWeb` branch with an honest fallback — never a silent failure and
never a crash:

| Instead of | On the web |
|---|---|
| `dart:io` file paths | `file_selector` for input, a browser download for output |
| Live camera face capture | Upload a photo, with the same validation applied |
| Fingerprint unlock | Password, the path that already exists |
| "Use my location" | PIN code plus village name — the reference flow already built |

`test/web_plugin_fallback_test.dart` fails when a new call site into any of the
four plugins or `dart:io` is added without a `kIsWeb` branch. A prose rule here
would hold exactly until the next long session; a guard does not.

**Each fallback must be exercised in a browser before it is called done.** The
whole reason this section exists is that a successful build proved nothing.

## 7. Session storage on the web — a real difference from Android

`flutter_secure_storage` on the web is `localStorage` plus WebCrypto. This is
confirmed rather than inferred: the wasm dry run named
`flutter_secure_storage_web` pulling in `dart:html`.

`ManaSession` persists the custom JWT carrying the `person_id` claim. On
Android that token sits in the Android Keystore. In `localStorage` it is
readable by any XSS on the origin. The one-hour expiry bounds the blast radius;
it does not remove it.

**Recommendation:** on web only, hold the token in memory plus `sessionStorage`
so it dies with the tab, and serve a Content-Security-Policy header. The cost is
that a web user re-enters their PIN after closing the tab. For a lending book
that trade is worth taking, and it is far cheaper to decide now than to migrate
a live session store later.

This is open decision (a) in section 11.

## 8. Guards

Following the project rule: prefer adding a guard to adding a rule.

| Guard | Stops |
|---|---|
| `test/web_plugin_fallback_test.dart` | An unguarded call into the four plugins or `dart:io` |
| `test/site_plans_sync_test.dart` | The public price page drifting from `kOwnerTiers` |
| `expectNoLayoutFault` at three widths | Overflow reappearing as layouts widen |
| `test/source_encoding_test.dart`, widened to `site/` | Mojibake — the bug that mangled the version label |

The existing suite must stay green throughout. It is the regression net for
every screen not being touched.

## 9. Phases

Each phase is independently shippable. Phase 0 alone yields a working web app.

| # | Ships | Verified by |
|---|---|---|
| 0 | Web shell: real `index.html`, manifest, title, base-href, the centred clamp, version footer | Every route reachable in a browser; Android behaviour unchanged |
| 1 | The seven `kIsWeb` fallbacks, plus the guard | Each fallback exercised in a browser — not inferred from the code |
| 2 | Responsive across the five workflows | Layout-fault tests at three widths; screens read correctly at 1440 px |
| 3 | Public site, plans generator, plans guard | Pages load; generated figures match `kOwnerTiers` |
| 4 | Deploy | The five workflows walked end-to-end against the real URL |

## 10. Verification

The in-app browser can drive the deployed site directly, including a real
login. The five workflows get walked end-to-end on the real URL rather than
handed over as a link with a request to check.

Reported the way this project requires: what was verified and how, stated
separately from what was changed. Anything that could not be verified gets said
plainly instead of being implied.

## 11. Open decisions

**(a) Session storage on the web.** Recommendation in section 7: memory plus
`sessionStorage`, plus a CSP header, at the cost of re-entering a PIN after the
tab closes. Default if unanswered: implement the recommendation, because it is
the reversible direction — loosening later is a config change, tightening later
means migrating live sessions.

**(b) Hosting and domain.** SPA rewrites are required for `/app/*` deep links.
Cloudflare Pages and Netlify both do this in a two-line config on a free tier;
Cloudflare's edge is nearer to Indian users. GitHub Pages cannot rewrite and
would force hash URLs, so it is ruled out. The domain is unconfirmed —
`manaline.in` is inferred from the project's contact address and has not been
verified as owned.

Neither decision blocks phases 0 to 3.

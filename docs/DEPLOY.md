# Deploying manaline.in

Two builds go to one Cloudflare Pages project. `/` is the static public
site (`site/`); `/app/` is a restricted Flutter web build. They deploy
together, in one upload, because Cloudflare Pages serves one project per
domain and `_headers`/`_redirects` apply project-wide.

**FIRST RUN DONE, 2026-09-18.** The Pages project `manaline` exists and
production is live at `https://manaline.pages.dev` — `/` serves the static
site, `/app/` serves the Flutter build, both 200, both CSPs correct.
`manaline.in` is NOT attached yet: the custom domain and its DNS are a
dashboard step that has not been taken, so the public name still does not
resolve.

Two things this file got wrong, found by running it:

1. **The build command does not work in Git Bash.** See the base-href trap
   below. It fails silently — a warning, then a broken artifact.
2. **`wrangler pages deploy` tags the deploy with your CURRENT GIT BRANCH**,
   and a tag that is not the project's production branch produces a PREVIEW
   deployment. Deploying from `web-on-the-web` put the whole site on
   `web-on-the-web.manaline.pages.dev` while `manaline.pages.dev` answered
   404, with nothing in the output calling that out — the word "preview"
   never appears. Pass the branch explicitly:

   ```bash
   npx wrangler pages deploy build/publish --project-name manaline --branch main
   ```

   Then check `https://manaline.pages.dev/` rather than the URL wrangler
   prints, which is the per-deployment hash either way and tells you nothing
   about which environment it landed in.

Keep following it slowly, diff every assumption against what actually
happens, and update this file when reality disagrees with it.

## What is NOT ready — do not deploy assuming otherwise

- No APK has been published anywhere.
- Neither app-store listing (Play Store, App Store) exists.
- The site is English only.
- `web_home_*` and `web_route_unavailable_*` translation keys exist in the
  database but have no Telugu (or any other language) rows yet — a
  non-English visitor to `/app/` sees English on those specific strings
  even though the rest of the app is localized.

Do not link to an app store, do not claim multi-language support, and do
not imply an APK is downloadable until these are actually true.

## The two builds

| | Static site | Flutter web build |
|---|---|---|
| Source | `site/` | `lib/` via `lib/main_web.dart` |
| Serves | `/` | `/app/` |
| Command | none — static files, upload as-is | `flutter build web` |
| Output | `site/*` | `build/web/*` |

### Building the Flutter half

```bash
flutter build web -t lib/main_web.dart --base-href /app/ \
  --dart-define=SUPABASE_URL=<value> \
  --dart-define=SUPABASE_ANON_KEY=<value>
```

- **`-t lib/main_web.dart`** — the restricted entrypoint. It calls the same
  `bootstrapManaApp()` as the Android build (`lib/main.dart`) but drives
  navigation with `manaWebRouter` (`lib/app/web_router.dart`), an allowlisted
  route set — collections, loans, day closure and reports are intentionally
  absent from the web build. Building with the default `lib/main.dart`
  entrypoint would ship the full app, including screens never meant to be
  reachable from a browser.
- **RUN THE BUILD FROM POWERSHELL, NOT GIT BASH** (found 2026-09-18, on the
  machine this project is developed on). Git Bash is MSYS, and MSYS rewrites
  an argument that looks like a Unix absolute path into a Windows one: typed
  in Git Bash, `--base-href /app/` arrives as
  `--base-href "C:/Program Files/Git/app/"`. Flutter prints

  ```
  Received a --base-href value of "C:/Program Files/Git/app/"
  --base-href should start and end with /
  ```

  and then **builds anyway**, producing a `build/web/index.html` that still
  says `<base href="/">` — the exact broken artifact the next bullet is about,
  with a warning instead of an error in front of it. Use
  `powershell -NoProfile -Command "flutter build web ..."`, or prefix the
  command with `MSYS_NO_PATHCONV=1`. Always confirm afterwards:

  ```bash
  grep -o '<base href="[^"]*"' build/web/index.html    # must print /app/
  ```
- **`--base-href /app/`** — required, and easy to forget. Without it the
  build's `<base href="/">` stays `/`, so `flutter_bootstrap.js` and every
  asset resolve against the site root instead of `/app/`, and the app fails
  to load with a 404-turned-MIME-type console error (`Refused to execute
  script ... because its MIME type ('text/html') is not executable`) — the
  static site's own `index.html` gets served for the JS request instead.
  This was hit and fixed while verifying this file.
- **`--dart-define=SUPABASE_URL=...` / `SUPABASE_ANON_KEY=...`** — the exact
  same two values already used for Android builds, read from
  `run.ps1.txt` (tracked on purpose: it holds only the URL and the anon
  key, both of which ship inside every APK anyway — see CLAUDE.md). Without
  them the build does not fail; it hangs, falling back to a host that does
  not exist, exactly like an unconfigured Android build.
- No `--wasm` flag. The default build target is `dart2js` + CanvasKit,
  which is what was verified below. Do not switch to a WebAssembly build
  without re-verifying the CSP — the script-src/connect-src rules below are
  shaped around CanvasKit's specific loading behavior.

### The static half

`site/` needs no build step. Upload it as-is — it is already the deploy
artifact.

## Laying out the upload

Cloudflare Pages deploys one directory. Combine the two builds into one
before uploading (a temp directory, not a repo folder):

```bash
rm -rf /tmp/publish && mkdir -p /tmp/publish
cp -r site/* /tmp/publish/
mkdir -p /tmp/publish/app
cp -r build/web/* /tmp/publish/app/
```

**A repo-local copy, for checking the layout without Cloudflare.**
`build/publish` is the same assembly under the git-ignored `build/`
directory, and `.claude/launch.json` has a `mana-publish` entry that serves
it on port 8082:

```bash
powershell -NoProfile -Command "flutter build web -t lib/main_web.dart --base-href /app/ --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY"
```

then copy `site/*` to `build/publish/` and `build/web/*` to
`build/publish/app/`, and open the `mana-publish` preview at
`http://localhost:8082/app/`.

**This checks the LAYOUT, not the headers.** A plain static server applies
no `_headers` at all, so it proves the base href and the two directories
sit where they should, and proves nothing whatever about the CSP. For that
it has to be `wrangler pages dev`, as the Verification section below
records.

`/tmp/publish` now has `_headers`, `_redirects` (if present), `index.html`,
etc. at its root (the static site) and everything from `build/web` under
`app/`. That whole directory is what gets uploaded to Cloudflare Pages
(dashboard upload, or `wrangler pages deploy /tmp/publish` once the owner
approves an actual deploy — **do not run that command without the owner's
explicit go-ahead**, per the standing rule that this procedure documents
but does not execute).

## `site/_headers`

Sets security headers for the whole domain, with a **different
Content-Security-Policy for `/app/*`** than for everything else.

**Why two policies, and why it's not simpler:** Cloudflare Pages'
`_headers` file merges matching rules rather than letting a more specific
path override a less specific one — a request under `/app/*` also matches
the `/*` block, and if both set `Content-Security-Policy`, Cloudflare
joins the two values with a comma into one header. Per the CSP spec, a
comma-joined (multiple) CSP is enforced as the *intersection* of both
policies, directive by directive — so the static site's strict policy
would have silently clamped down the app's policy too, blocking Supabase
and CanvasKit while still reporting "200 OK, page loaded" with a blank
canvas. This was reproduced locally (see Verification below) before being
fixed with `! Content-Security-Policy` under `/app/*`, which removes the
inherited header before the app-specific one is set.

**The `/app/*` policy, and why each piece is there** (all confirmed
against a real build — see Verification):

- `script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://www.gstatic.com blob:`
  — CanvasKit is fetched from `https://www.gstatic.com/flutter-canvaskit/...`
  by default (there is no local-CanvasKit config in this build), and
  compiling its `.wasm` needs `'wasm-unsafe-eval'` or Chrome refuses
  `WebAssembly.compileStreaming` with a CSP error. `blob:` covers Flutter's
  worker scripts.
- `connect-src ... https://www.gstatic.com https://fonts.gstatic.com
  https://*.supabase.co wss://*.supabase.co` — the Flutter engine fetches
  the CanvasKit `.wasm` and the Roboto fallback font via `fetch()`
  (governed by `connect-src`, not `font-src`, in Chrome), and the app talks
  to Supabase over both HTTPS (REST/RPC) and WebSocket (Realtime).
- `font-src ... https://fonts.gstatic.com` — belt-and-suspenders for
  browsers that do check `font-src` for font fetches.
- `style-src 'self' 'unsafe-inline'` / extra `img-src ... blob:` — Flutter
  web sets inline styles and uses blob/data URLs for some rendering paths.
- `worker-src 'self' blob:` — Flutter's canvas/font workers.
- Camera, microphone and geolocation are denied for **all** paths
  (`Permissions-Policy: camera=(), microphone=(), geolocation=()`) — the
  Android app uses camera and geolocation, but this web build has neither,
  so there is nothing to allow.

**What was deliberately left out, and why:**
- No `report-uri`/`report-to` — nothing is set up to receive CSP violation
  reports yet. Add one before relying on the policy to page anyone.
- No `Strict-Transport-Security` — this was left "for Cloudflare's own
  defaults"; **the defaults do not include it**. Checked on the live
  deployment 2026-09-18: `strict-transport-security` comes back null. Turn it
  on in the dashboard (SSL/TLS → Edge Certificates → HSTS) before a custom
  domain carries a real login, or set it here — but not both.
- The static site's policy has **no** `'unsafe-inline'` on `style-src` —
  `site/` has no inline `style=` attributes and no `<style>` blocks
  (verified by grep), so it doesn't need the allowance the app does.
- Neither policy includes a `nonce` or `hash` source — this project is not
  set up to generate per-request nonces (Cloudflare Pages is a static
  host, not a template renderer), so `'unsafe-inline'` where it's needed
  is deliberate, not an oversight.

## `site/_redirects`

**Not created.** Two things this file might otherwise be for, both
checked and both unnecessary:

- **A SPA rewrite for `/app/*`.** The Flutter web build uses hash routing
  (`manaWebRouter` is a plain `GoRouter` with no `usePathUrlStrategy` call
  anywhere in `lib/` — reconfirmed while writing this) — so a route like
  `/app/#/ow-013` never leaves the fragment for the server to see. A
  catch-all rewrite would solve a problem that does not exist, while
  risking swallowing requests meant for the static site.
- **`/app` (no trailing slash) reaching `/app/`.** Cloudflare Pages does
  this itself — confirmed locally: a request for `/app` comes back
  `308 Permanent Redirect` to `/app/` with no configuration at all.

If a real routing need shows up later (a marketing short-link, a legacy
path), add `_redirects` then, scoped narrowly — not as a general SPA
catch-all.

## Verification performed for this task

**This task did not deploy anything.** Cloudflare Pages was never
touched; DNS was never touched. Everything below was run against a local
copy.

1. Built the real artifact:
   `flutter build web -t lib/main_web.dart --base-href /app/
   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
   using the same values `run.ps1.txt` carries for Android builds.
2. Assembled `/tmp/publish` exactly as described above: `site/*` at the
   root, `build/web/*` under `app/`, `_headers` copied in.
3. Served it with `npx wrangler pages dev /tmp/publish` — Cloudflare's own
   local emulator, which parses and applies `_headers`/`_redirects` the
   way the real edge does (a plain `python -m http.server` does not apply
   headers at all, so it can't be used to check a CSP).
4. Loaded `/app/` in a real browser (Claude's browser tool) and read the
   console.
   - **First pass failed**: `flutter_bootstrap.js` 404'd against the site
     root instead of `/app/`, because the build had been made without
     `--base-href /app/`. Fixed by rebuilding with the flag (see above).
   - **Second pass** (correct base href, first CSP draft) surfaced two
     real violations: `WebAssembly.compileStreaming()` blocked by
     `script-src` (missing `'wasm-unsafe-eval'`), and a `connect-src`
     block on `https://fonts.gstatic.com/.../KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2`
     (the Roboto fallback font, fetched via `fetch()`, not a stylesheet
     `@font-face`). Both fixed in the CSP above.
   - **Third pass**: zero console errors. `window.flutterCanvasKit` was
     defined (confirmed via `javascript_tool`, not inferred from a lack of
     errors). The app rendered the workspace-choice screen, and clicking
     through to "Mana Finance" reached the real login screen
     (`Mobile Number` / `Password` fields, Register link, language
     selector) with still no console errors — this exercises the second
     `main.dart.js` chunk and route transition, not just the initial
     paint.
5. Separately verified the additive-header problem: with a single shared
   `Content-Security-Policy` line under both `/*` and `/app/*`, the served
   header for `/app/*` came back as **both policies comma-joined into one
   header value** — reproduced with `curl -I`, not assumed from
   documentation. Fixed with `! Content-Security-Policy` under `/app/*`.
6. Verified the static site separately, after tightening its `style-src`
   to drop `'unsafe-inline'` (grep found no inline styles in `site/`):
   loaded `/` and `/videos.html` — the one page with a JS-driven carousel
   (`site.js`) — and confirmed zero console errors on both.
7. Confirmed `/app` (no slash) already 308-redirects to `/app/` with no
   `_redirects` rule, via `curl -I`.

Not verified: the production Cloudflare Pages edge itself (only the local
`wrangler pages dev` emulator), Safari/Firefox (only the browser tool's
Chromium was used), and a WebAssembly (`--wasm`) build — this project
builds with the default `dart2js` target.

## Post-deploy checklist

Do this immediately after any real deploy, before telling anyone the site
is live:

1. Load `/` — check title, check `videos.html`'s carousel still runs
   (open the console; it should be silent).
2. Load `/app/` — open the browser console. A silent load with a
   workspace-choice screen is success; a blank canvas with CSP errors
   means the policy above didn't survive the copy/paste into whatever
   deploy tool was used (dashboard upload strips or reformats `_headers`
   more often than the CLI does).
3. Click through to a login screen (`Mana Finance` → mobile/password
   form) to confirm the second JS chunk and a route transition both work,
   not just the first paint.
4. Check `curl -I https://manaline.in/app` returns a redirect to `/app/`.
5. Check response headers on both `/` and `/app/` (`curl -I`) actually
   carry the two different CSPs — a redeploy that merges `_headers`
   wrongly will pass step 2 from cache and still be broken for a fresh
   visitor.

## Re-verified 2026-09-18, with one open question

**Still not deployed. `manaline.in` does not resolve** — checked from this
machine on 2026-09-18, `curl` returns "Could not resolve host". There is no
Cloudflare Pages project behind it yet, so the first run of this procedure is
a CREATE (project, custom domain, DNS), not an update, and the rollback
section below has nothing to roll back to.

The artifact was rebuilt and reassembled on the day the bulk-onboarding menu
was added (86 routes). What was checked, and what was not:

| Checked | Result |
|---|---|
| `--base-href /app/` survives the build | Only from PowerShell — see the trap above |
| `build/publish` layout, served on 8082 | `/app/` loads, `<base href="/app/">`, workspace-choice screen renders |
| Translations reach the browser | Real strings, not raw keys — so the `--dart-define` values are in the bundle |
| Hash routing under `/app/` | `#/lr-002` and `#/settings` both resolve; a signed-out visit to `#/ow-bulk-onboarding-menu` redirects to the workspace choice, which is the guard doing its job |
| The CSP | **Re-checked under `wrangler pages dev`.** Both policies apply, separately: `/` keeps the strict one, `/app/` gets its own, and the two are NOT comma-joined -- the `! Content-Security-Policy` removal does what it was added to do |
| Bundle size | 46.7 MB for both halves together, CanvasKit included |

**ONE UNCAUGHT DART EXCEPTION AT BOOTSTRAP, and it is not understood.**
Loading `/app/` logs exactly one `Uncaught {dartException: ...}` from
`main.dart.js` and then carries on: the app paints, routes and reads
translations normally.

**The "zero console errors" line in the third pass below is stale — do not
rely on it.** I first saw this on a plain static server and hoped the
difference was the missing CSP; it is not. Re-run under `wrangler pages dev`,
with both real policies applied, it throws identically. It also reproduces on
a build made BEFORE the bulk-onboarding menu existed, so it is not from that
work either. Two things it is NOT: a CSP violation (the console carries no
CSP text) and a load failure (nothing 404s).

Do not treat it as cosmetic because the app looks fine. A caught-and-ignored
failure at startup is how an app ends up silently running without a piece of
itself — `flutter_secure_storage` is the obvious suspect, it is `dart:html`
based on web (the build says so), and `ManaSession` persists through it.

To name the throwing frame, build with source maps (`--profile`, or dart2js
source maps on a release build) and reproduce under
`npx wrangler pages dev build/publish`. The `mana-publish-wrangler` entry in
`.claude/launch.json` runs exactly that on port 8083.

## Rollback

Cloudflare Pages keeps every previous deployment. Rolling back is
promoting an older deployment to production from the Pages dashboard's
**Deployments** tab (or `wrangler pages deployment list` /
`wrangler pages deployment tail` to inspect, and the dashboard's "Rollback
to this deployment" action to act) — there is no destructive step and no
DNS change involved. Do this the moment the post-deploy checklist above
fails; do not attempt to patch forward under live traffic.

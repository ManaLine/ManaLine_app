# Deploying manaline.in

Two builds go to one Cloudflare Pages project. `/` is the static public
site (`site/`); `/app/` is a restricted Flutter web build. They deploy
together, in one upload, because Cloudflare Pages serves one project per
domain and `_headers`/`_redirects` apply project-wide.

**Nobody has run this procedure yet.** Follow it slowly the first time,
diff every assumption against what actually happens, and update this file
when reality disagrees with it.

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
- No `Strict-Transport-Security` — left for Cloudflare's own defaults
  rather than duplicated here; confirm what Cloudflare Pages already sends
  before adding a second one.
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

## Rollback

Cloudflare Pages keeps every previous deployment. Rolling back is
promoting an older deployment to production from the Pages dashboard's
**Deployments** tab (or `wrangler pages deployment list` /
`wrangler pages deployment tail` to inspect, and the dashboard's "Rollback
to this deployment" action to act) — there is no destructive step and no
DNS change involved. Do this the moment the post-deploy checklist above
fails; do not attempt to patch forward under live traffic.

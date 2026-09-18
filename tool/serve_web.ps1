<#
.SYNOPSIS
  Build the web app, CHECK THE ARTEFACT, and assemble it for serving.

.DESCRIPTION
  One command instead of four, because the four went wrong twice in one
  afternoon and in opposite directions:

    * once with the credentials right and MANA_SITE_URL pointing at a domain
      that was never registered, so the sign-in page linked to nothing;
    * once with the site URL right and `--dart-define=SUPABASE_URL=$URL`
      against an unset shell variable, which does not OMIT the define -- it
      supplies the empty string. Dart then returns '' instead of the declared
      default, dart2js folds the REPLACE-ME placeholder out as unreachable,
      and the "Build not configured" screen never appeared either.

  PowerShell does not warn about an unset variable, and neither did we. The
  fix is to stop typing the values: they are read from run.ps1.txt, which is
  tracked on purpose (it holds only the project URL and the anon key, both of
  which ship inside every APK anyway -- see CLAUDE.md).

  The checks below run against the BUILT BUNDLE rather than the source,
  because that is where this class of mistake is visible at all.

.PARAMETER SiteUrl
  Overrides MANA_SITE_URL. Leave it unset for testing: the default in
  lib/shared/mana_site.dart is the free origin that is actually serving.
  Pass a real domain only once DNS answers for it.

.PARAMETER BaseHref
  '/app/' matches the deployed layout (static site at /, app under /app/).
  Pass '/' to serve the app alone on a local port.

.EXAMPLE
  # Build, check, assemble, and serve it on http://localhost:8083
  powershell -ExecutionPolicy Bypass -File tool\serve_web.ps1 -Serve

.EXAMPLE
  # Build and check only, e.g. before deploying
  powershell -ExecutionPolicy Bypass -File tool\serve_web.ps1
#>
param(
  [string] $SiteUrl = '',
  [string] $BaseHref = '/app/',

  # Start a local server on the assembled directory when the build is done.
  #
  # ADDED BECAUSE THE NAME PROMISED IT. Asked "step 1: serve_web.ps1, step 2:
  # open the site -- is that correct?", and it was not: the script built and
  # assembled, then stopped, and serving was a second command nobody had been
  # told about. Documenting that would have been documenting a mistake in the
  # name rather than fixing it.
  #
  # wrangler rather than a plain static server, because it applies _headers --
  # so the CSP and HSTS are the real ones. A static server applies no headers
  # at all and cannot tell a correct policy from a missing one.
  [switch] $Serve,
  [int] $Port = 8083
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# --- credentials, from the one file that has them ------------------------
$runFile = Join-Path $repo 'run.ps1.txt'
if (-not (Test-Path $runFile)) {
  throw "run.ps1.txt is missing. It carries SUPABASE_URL and the anon key; see CLAUDE.md."
}
$runText = Get-Content $runFile -Raw

$urlMatch = [regex]::Match($runText, 'SUPABASE_URL=([^\s]+)')
$keyMatch = [regex]::Match($runText, 'SUPABASE_ANON_KEY=([^\s]+)')
if (-not $urlMatch.Success -or -not $keyMatch.Success) {
  throw "Could not read SUPABASE_URL / SUPABASE_ANON_KEY out of run.ps1.txt."
}
$supabaseUrl = $urlMatch.Groups[1].Value
$anonKey     = $keyMatch.Groups[1].Value

# The project ref is what proves the credentials reached the bundle.
$refMatch = [regex]::Match($supabaseUrl, 'https://([a-z0-9]+)\.supabase\.co')
if (-not $refMatch.Success) { throw "SUPABASE_URL does not look like a project URL: $supabaseUrl" }
$projectRef = $refMatch.Groups[1].Value

Write-Host "Project ref : $projectRef"
Write-Host "Base href   : $BaseHref"
if ($SiteUrl -ne '') { Write-Host "Site URL    : $SiteUrl (override)" }
else { Write-Host "Site URL    : default (the free origin, see mana_site.dart)" }

# --- build ----------------------------------------------------------------
$buildArgs = @(
  'build','web','-t','lib/main_web.dart',
  "--base-href", $BaseHref,
  "--dart-define=SUPABASE_URL=$supabaseUrl",
  "--dart-define=SUPABASE_ANON_KEY=$anonKey"
)
if ($SiteUrl -ne '') { $buildArgs += "--dart-define=MANA_SITE_URL=$SiteUrl" }

Write-Host "`nBuilding..." -ForegroundColor Cyan
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) { throw "flutter build web failed." }

# --- check the artefact ---------------------------------------------------
# Reading the thing that will actually be uploaded. Source review cannot see
# any of these: they are all decided by build flags.
$bundle = Join-Path $repo 'build\web\main.dart.js'
if (-not (Test-Path $bundle)) { throw "No bundle at $bundle" }
$js = Get-Content $bundle -Raw
$fail = @()

if ($js -notmatch [regex]::Escape($projectRef)) {
  $fail += "the Supabase project ref is NOT in the bundle -- the credentials did not reach the build"
}
# Grep the DEFAULTS by their full names. A correct bundle contains the bare
# string 'REPLACE-ME' exactly once, as the argument isPlaceholder compares
# against, so checking for that alone fires on every good build.
if ($js -match 'REPLACE-ME\.supabase\.co' -or $js -match 'REPLACE-ME-ANON-KEY') {
  $fail += "the placeholder defaults are in the bundle -- built with no credentials"
}
if ($SiteUrl -eq '' -and $js -match 'https://manaline\.in') {
  $fail += "the bundle links to manaline.in, which is not registered"
}

$indexHtml = Get-Content (Join-Path $repo 'build\web\index.html') -Raw
if ($indexHtml -notmatch [regex]::Escape("<base href=`"$BaseHref`"")) {
  $fail += "index.html does not carry <base href=`"$BaseHref`"> -- MSYS mangles this in Git Bash; run from PowerShell"
}

if ($fail.Count -gt 0) {
  Write-Host "`nARTEFACT CHECK FAILED" -ForegroundColor Red
  foreach ($f in $fail) { Write-Host "  - $f" -ForegroundColor Red }
  throw "Not assembling a bundle that would be broken once served."
}
Write-Host "Artefact checks passed." -ForegroundColor Green

# --- assemble -------------------------------------------------------------
# The same shape the deploy uploads: static site at the root, app under /app/.
$pub = Join-Path $repo 'build\publish'
if (Test-Path $pub) { Remove-Item -Recurse -Force $pub }
New-Item -ItemType Directory -Force $pub | Out-Null
Copy-Item -Recurse -Force (Join-Path $repo 'site\*') $pub
New-Item -ItemType Directory -Force (Join-Path $pub 'app') | Out-Null
Copy-Item -Recurse -Force (Join-Path $repo 'build\web\*') (Join-Path $pub 'app')

$mb = '{0:N1}' -f ((Get-ChildItem $pub -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "`nAssembled build\publish ($mb MB)" -ForegroundColor Green
if ($Serve) {
  Write-Host "`nServing on http://localhost:$Port  (Ctrl+C to stop)" -ForegroundColor Cyan
  Write-Host "This is LOCAL. It does not change https://manaline.pages.dev --" -ForegroundColor DarkGray
  Write-Host "that only changes when somebody runs 'wrangler pages deploy'." -ForegroundColor DarkGray
  & npx --yes wrangler pages dev $pub --port $Port
} else {
  Write-Host @"

Nothing is being served yet. Either:

  re-run with -Serve                       starts wrangler on $Port for you
  npx wrangler pages dev build\publish     the same thing, by hand

and then open http://localhost:$Port.

LOCAL IS NOT LIVE. https://manaline.pages.dev only changes when somebody
runs: npx wrangler pages deploy build\publish --project-name manaline --branch main
"@
}

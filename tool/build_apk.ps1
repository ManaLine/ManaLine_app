<#
.SYNOPSIS
  Bumps the build number, then builds the debug APK with the Supabase
  credentials already in run.ps1.txt.

.DESCRIPTION
  Two problems this removes.

  THE BUILD NUMBER NEVER MOVED. pubspec had no `+N`, so Flutter defaulted
  Android's versionCode to 1 on every build ever made. `dumpsys package` showed
  versionCode=1 / versionName=0.1.0 whatever was installed, so the only way to
  tell whether a phone had the latest code was to compare the APK's file mtime
  against the newest .dart file. A tester holding the handset could not answer
  the question at all.

  THE CREDENTIALS WERE COPIED BY HAND. Every build meant reading
  SUPABASE_URL and SUPABASE_ANON_KEY out of run.ps1.txt and pasting them into
  --dart-define. Forgetting them does NOT fail the build -- the app installs
  and then hangs on a host that does not exist, showing raw translation keys
  and "No internet connection". That is a slow, confusing failure for a
  mistake a script should never let happen.

.PARAMETER Release
  Build a release APK instead of debug.

.PARAMETER NoBump
  Rebuild without incrementing -- for a second APK of the SAME code, where a
  new number would be a lie about which build it is.

.NOTES
  Bumps BOTH pubspec.yaml's `+N` and manaBuildNumber in
  lib/shared/app_version.dart, because Android reads one and the screen reads
  the other. test/app_version_test.dart fails if they ever disagree.

.EXAMPLE
  pwsh tool/build_apk.ps1
#>
[CmdletBinding()]
param(
  [switch]$Release,
  [switch]$NoBump
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pubspecPath = Join-Path $root 'pubspec.yaml'
$versionPath = Join-Path $root 'lib/shared/app_version.dart'

foreach ($p in @($pubspecPath, $versionPath, (Join-Path $root 'run.ps1.txt'))) {
  if (-not (Test-Path $p)) {
    Write-Host "Missing $p" -ForegroundColor Red
    exit 2
  }
}

# --- the build number -------------------------------------------------------

# UTF-8 explicitly, on BOTH read and write.
#
# The first run of this script corrupted every non-ASCII character in the two
# files it edits. Windows PowerShell 5.1's `Get-Content -Raw` decodes using the
# system ANSI codepage, not UTF-8, so `—` came back as three cp1252 characters;
# `Set-Content -Encoding utf8` then wrote those back as UTF-8 and also prepended
# a BOM. pubspec's description line and the version label both broke, and the
# APK built from it displayed the separator in the version label as two
# stray characters on screen. (Not quoted here on purpose -- writing the
# corrupt bytes into this file would trip test/source_encoding_test.dart,
# which is the guard that now covers tool/ precisely because of this.)
#
# [System.IO.File] does neither: UTF8Encoding($false) is UTF-8 with no BOM, and
# ReadAllText with the same encoding decodes what is actually on disk.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$pubspec = [System.IO.File]::ReadAllText($pubspecPath, $utf8NoBom)
$m = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $m.Success) {
  Write-Host 'pubspec.yaml has no `version: X.Y.Z+N` line to bump.' -ForegroundColor Red
  Write-Host 'Without the +N, Android defaults versionCode to 1 for every build.'
  exit 2
}
$semver = $m.Groups[1].Value
$current = [int]$m.Groups[2].Value
$build = if ($NoBump) { $current } else { $current + 1 }

if (-not $NoBump) {
  $pubspec = $pubspec -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+\s*$', "version: $semver+$build"
  [System.IO.File]::WriteAllText($pubspecPath, $pubspec, $utf8NoBom)

  $dart = [System.IO.File]::ReadAllText($versionPath, $utf8NoBom)
  if ($dart -notmatch 'const manaBuildNumber = \d+;') {
    Write-Host 'app_version.dart has no `const manaBuildNumber = N;` to bump.' -ForegroundColor Red
    exit 2
  }
  $dart = $dart -replace 'const manaBuildNumber = \d+;', "const manaBuildNumber = $build;"
  # A new build number starts at revision 0, or build 15 would announce itself
  # as 15.1 because 14.1 happened to be the last thing cut.
  $dart = $dart -replace 'const manaBuildRevision = \d+;', 'const manaBuildRevision = 0;'
  [System.IO.File]::WriteAllText($versionPath, $dart, $utf8NoBom)

  Write-Host "Build number $current -> $build" -ForegroundColor Green
} else {
  Write-Host "Build number left at $build (-NoBump)" -ForegroundColor Yellow
}

# --- credentials ------------------------------------------------------------

# From run.ps1.txt, which is tracked on purpose: it holds only the URL and the
# anon key, both of which ship inside every APK anyway. A service-role key or
# JWT secret there would be a real leak -- those belong in .env.
$runLine = [System.IO.File]::ReadAllText((Join-Path $root 'run.ps1.txt'), $utf8NoBom)
$url = [regex]::Match($runLine, 'SUPABASE_URL=(\S+)').Groups[1].Value
$key = [regex]::Match($runLine, 'SUPABASE_ANON_KEY=(\S+)').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
  Write-Host 'Could not read SUPABASE_URL / SUPABASE_ANON_KEY from run.ps1.txt.' -ForegroundColor Red
  Write-Host 'Building without them produces an APK that installs and then hangs.'
  exit 2
}
Write-Host ("Credentials read: url {0} chars, key {1} chars" -f $url.Length, $key.Length)

# --- build ------------------------------------------------------------------

$mode = if ($Release) { 'release' } else { 'debug' }
Write-Host "Building $mode APK..." -ForegroundColor Cyan

& flutter build apk "--$mode" "--dart-define=SUPABASE_URL=$url" "--dart-define=SUPABASE_ANON_KEY=$key"
$code = $LASTEXITCODE
if ($code -ne 0) {
  Write-Host "flutter build apk failed ($code)." -ForegroundColor Red
  exit $code
}

$apk = Join-Path $root "build/app/outputs/flutter-apk/app-$mode.apk"
Write-Host ''
Write-Host ("Built build $build -> $apk") -ForegroundColor Green
Write-Host 'Install with:'
Write-Host ('  $env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe -s <device> install -r "' + $apk + '"')
exit 0

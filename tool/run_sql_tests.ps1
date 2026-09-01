<#
.SYNOPSIS
  Runs the SQL tests in supabase/tests, and refuses to run the destructive ones
  against anything it cannot identify as a scratch database.

.DESCRIPTION
  These files have existed for months and never run. Five of them, and the
  assertions added most recently -- no customer with a live loan outside an
  active operating area, no village recording a state the PIN directory does
  not carry, no SECURITY INVOKER trigger reaching into the app schema -- had
  never been executed even once. A guard nobody runs is worth nothing, which is
  worse than worth little, because it reads like cover.

  TWO KINDS OF FILE, declared by the file itself in a `-- @target:` line.

    @target: production   Read-only. Safe against a live book, and only
                          meaningful there -- a stranded customer or a mistyped
                          state cannot be reproduced with fixtures, so against
                          an empty branch these pass trivially and prove
                          nothing. Run with default_transaction_read_only=on,
                          so a write raises 25006 rather than merely breaking a
                          convention.

    @target: scratch      Fabricates persons, businesses and loans. Must never
                          touch a real book. Refused unless the target database
                          is empty of them.

  A file with no @target line is treated as scratch, because that is the
  direction in which being wrong is survivable.

  WHY THE READ-ONLY SESSION AND NOT A GREP. The previous version of this script
  said "prefer a branch" and left it there. Reviewing which files were safe, I
  counted INSERT statements and concluded migration_weekly_ledger_tests.sql
  wrote nothing -- its writes are inside app.import_weekly_account, invisible to
  any reading of the file's own statements. Static inspection cannot answer this
  question. A read-only transaction answers it at runtime, which is why that is
  the mechanism here.

.PARAMETER DatabaseUrl
  A libpq connection string. Defaults to $env:MANA_DB_URL.

  NOT stored in this repo and never will be. run.ps1.txt holds the anon key
  because that ships inside every APK anyway; a database password does not, and
  putting one in a tracked file would be a real leak.

.PARAMETER AllowNonEmpty
  Run the scratch files even though the target already holds businesses or
  loans. For a branch someone has seeded deliberately. It does NOT lift the
  refusal on the production project ref, which has no override.

.EXAMPLE
  $env:MANA_DB_URL = "postgresql://postgres:<password>@<host>:5432/postgres"
  pwsh tool/run_sql_tests.ps1
#>
[CmdletBinding()]
param(
  [string]$DatabaseUrl = $env:MANA_DB_URL,
  [switch]$AllowNonEmpty
)

$ErrorActionPreference = 'Stop'

# The live project. Not a secret -- it is in run.ps1.txt and inside every APK --
# but it is the one host that must never see a fixture.
$ProductionRef = 'vjhxssqgqlvyesndubor'

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  Write-Host 'MANA_DB_URL is not set, so the SQL tests cannot run.' -ForegroundColor Yellow
  Write-Host 'Set it to a libpq connection string and run this again:'
  Write-Host ''
  Write-Host '  $env:MANA_DB_URL = "postgresql://postgres:<password>@<host>:5432/postgres"'
  Write-Host '  pwsh tool/run_sql_tests.ps1'
  exit 2
}

$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
  $fallback = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
  if (Test-Path $fallback) { $psql = $fallback }
}
if (-not $psql) {
  Write-Host 'psql was not found on PATH.' -ForegroundColor Red
  exit 2
}

$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem (Join-Path $root 'supabase/tests') -Filter '*.sql' | Sort-Object Name
if ($files.Count -eq 0) {
  Write-Host 'No SQL test files found.' -ForegroundColor Red
  exit 2
}

# --- Identify the target ------------------------------------------------------

function Invoke-Scalar([string]$sql) {
  $out = New-TemporaryFile
  $err = New-TemporaryFile
  $p = Start-Process -FilePath $psql `
    -ArgumentList @('--no-psqlrc', '-t', '-A', '-v', 'ON_ERROR_STOP=1', $DatabaseUrl, '-c', $sql) `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $value = (Get-Content $out -Raw)
  $problem = (Get-Content $err -Raw)
  Remove-Item $out, $err -Force
  if ($p.ExitCode -ne 0) { return @{ ok = $false; error = $problem } }
  return @{ ok = $true; value = $value.Trim() }
}

$isProductionRef = $DatabaseUrl -like "*$ProductionRef*"
$scratchSafe = $true
$why = ''

if ($isProductionRef) {
  $scratchSafe = $false
  $why = "the connection string names the production project ($ProductionRef)"
} else {
  $probe = Invoke-Scalar 'SELECT (SELECT count(*) FROM businesses) + (SELECT count(*) FROM loans);'
  if (-not $probe.ok) {
    $scratchSafe = $false
    $why = 'the target could not be probed, so it cannot be identified as a scratch database'
    Write-Host $probe.error -ForegroundColor DarkGray
  } elseif ([int]$probe.value -gt 0) {
    if ($AllowNonEmpty) {
      Write-Host ("  NOTE   target holds {0} business/loan row(s); -AllowNonEmpty was given" -f $probe.value) -ForegroundColor Yellow
    } else {
      $scratchSafe = $false
      $why = "the target already holds $($probe.value) business/loan row(s), so it is somebody's book"
    }
  }
}

if ($scratchSafe) {
  Write-Host 'Target looks like a scratch database. Running everything.' -ForegroundColor Green
} else {
  Write-Host "Fixture-building tests will be SKIPPED: $why." -ForegroundColor Yellow
  if ($isProductionRef) {
    Write-Host 'There is no override for the production project ref.' -ForegroundColor Yellow
  } else {
    Write-Host 'Pass -AllowNonEmpty if this really is a scratch database.' -ForegroundColor DarkGray
  }
}
Write-Host ''

# --- Run ----------------------------------------------------------------------

$totalFailures = 0
$ran = 0
$skipped = 0

foreach ($file in $files) {
  $head = Get-Content $file.FullName -TotalCount 40
  $marker = $head | Select-String -Pattern '^\s*--\s*@target:\s*(\S+)' | Select-Object -First 1
  $target = if ($marker) { $marker.Matches[0].Groups[1].Value.ToLower() } else { 'scratch' }
  if (-not $marker) {
    Write-Host ("  NOTE   {0} declares no @target; treating it as scratch" -f $file.Name) -ForegroundColor Yellow
  }

  if ($target -eq 'scratch' -and -not $scratchSafe) {
    Write-Host ("  skip   {0} -- builds fixtures" -f $file.Name) -ForegroundColor DarkGray
    $skipped++
    continue
  }

  # A production-targeted file gets a read-only session. That forbids DDL too --
  # CREATE TEMP TABLE and CREATE FUNCTION both raise 25006 -- so these files
  # cannot use the temp-results harness the scratch files open with. Verified by
  # running it; the assumption that temp tables were exempt was wrong.
  if ($target -eq 'production') {
    $env:PGOPTIONS = '-c default_transaction_read_only=on'
  } else {
    Remove-Item Env:PGOPTIONS -ErrorAction SilentlyContinue
  }

  # Start-Process rather than a redirect: psql writes NOTICE and WARNING to
  # stderr, and Windows PowerShell wraps native stderr in ErrorRecords when
  # 2>&1 is used, which turns a passing run into a reported failure.
  $out = New-TemporaryFile
  $err = New-TemporaryFile
  $proc = Start-Process -FilePath $psql `
    -ArgumentList @('--no-psqlrc', '--quiet', '-v', 'ON_ERROR_STOP=1',
                    $DatabaseUrl, '-f', $file.FullName) `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err

  $stderr = Get-Content $err -Raw
  $stdout = Get-Content $out -Raw
  Remove-Item $out, $err -Force
  Remove-Item Env:PGOPTIONS -ErrorAction SilentlyContinue

  # The convention: every assertion that fails raises a WARNING saying FAIL.
  $failures = @()
  if ($stderr) {
    $failures = @($stderr -split "`n" | Where-Object { $_ -match 'WARNING' -and $_ -match 'FAIL' })
  }

  $ran++
  if ($proc.ExitCode -ne 0) {
    Write-Host ("  ERROR  {0} -- psql exited {1}" -f $file.Name, $proc.ExitCode) -ForegroundColor Red
    if ($stderr) { Write-Host $stderr }
    $totalFailures++
    continue
  }

  if ($failures.Count -gt 0) {
    Write-Host ("  FAIL   {0} -- {1} assertion(s)" -f $file.Name, $failures.Count) -ForegroundColor Red
    $failures | ForEach-Object { Write-Host ('           ' + $_.Trim()) }
    $totalFailures += $failures.Count
  } else {
    Write-Host ("  ok     {0} [{1}]" -f $file.Name, $target) -ForegroundColor Green
  }

  if ($VerbosePreference -eq 'Continue' -and $stdout) { Write-Host $stdout }
}

Write-Host ''
if ($totalFailures -gt 0) {
  Write-Host ("{0} assertion(s) failed across {1} file(s), {2} skipped." -f $totalFailures, $ran, $skipped) -ForegroundColor Red
  exit 1
}

# Nothing ran is not success. That is the whole failure mode being designed out.
if ($ran -eq 0) {
  Write-Host ("No SQL tests ran ({0} skipped). Point this at a scratch database." -f $skipped) -ForegroundColor Red
  exit 3
}

Write-Host ("All SQL assertions passed across {0} file(s), {1} skipped." -f $ran, $skipped) -ForegroundColor Green
exit 0

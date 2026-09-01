<#
.SYNOPSIS
  Runs every SQL test in supabase/tests and fails if any assertion does.

.DESCRIPTION
  These files have existed for months and never run. Five of them, and the
  assertions added most recently -- no customer with a live loan outside an
  active operating area, no village recording a state the PIN directory does
  not carry, no SECURITY INVOKER trigger reaching into the app schema -- had
  never been executed even once. A guard nobody runs is worth nothing, which
  is worse than worth little, because it reads like cover.

  Each file follows the same convention: a temp results table, one DO block
  per assertion, RAISE NOTICE on PASS and RAISE WARNING 'FAIL ...' on failure,
  and a ROLLBACK at the end so nothing is left behind. This runner leans on
  exactly that -- it counts WARNING lines mentioning FAIL and exits non-zero
  if there are any.

.PARAMETER DatabaseUrl
  A libpq connection string. Defaults to $env:MANA_DB_URL.

  NOT stored in this repo and never will be. run.ps1.txt holds the anon key
  because that ships inside every APK anyway; a database password does not,
  and putting one in a tracked file would be a real leak.

.NOTES
  PREFER A BRANCH OVER PRODUCTION. Every file rolls back, and all five were
  checked for exactly one ROLLBACK before this was written -- but "it rolls
  back" is a property of the file as written, not a guarantee about the file
  somebody edits next month. Supabase branching exists for this.

.EXAMPLE
  $env:MANA_DB_URL = "postgresql://postgres:<password>@<host>:5432/postgres"
  pwsh tool/run_sql_tests.ps1
#>
[CmdletBinding()]
param(
  [string]$DatabaseUrl = $env:MANA_DB_URL
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  Write-Host 'MANA_DB_URL is not set, so the SQL tests cannot run.' -ForegroundColor Yellow
  Write-Host 'Set it to a libpq connection string -- a branch database for'
  Write-Host 'preference -- and run this again:'
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

$totalFailures = 0
$ran = 0

foreach ($file in $files) {
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
    Write-Host ("  ok     {0}" -f $file.Name) -ForegroundColor Green
  }

  if ($VerbosePreference -eq 'Continue' -and $stdout) { Write-Host $stdout }
}

Write-Host ''
if ($totalFailures -gt 0) {
  Write-Host ("{0} assertion(s) failed across {1} file(s)." -f $totalFailures, $ran) -ForegroundColor Red
  exit 1
}

Write-Host ("All SQL assertions passed across {0} file(s)." -f $ran) -ForegroundColor Green
exit 0

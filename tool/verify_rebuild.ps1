<#
.SYNOPSIS
  Can this repo rebuild the database from nothing?

.DESCRIPTION
  supabase/MIGRATIONS.md carried this as an open question from 2026-07-30:

    "Nothing has verified that running all 58 files in order against an EMPTY
     database reproduces the current schema... Until someone does it, treat
     'the repo can rebuild the database' as probable but unproven."

  It is proven now, and the answer is NO. This script is how that was
  established and how it is re-checked.

  It creates a DISPOSABLE Postgres cluster on port 5433 with trust auth, in a
  temp directory. It touches neither production nor any local database you
  already have -- it does not need a password, because it makes its own server.

.NOTES
  WHAT IT FOUND on 2026-09-15, in the order the failures appeared:

    after  6 files -- type "repayment_frequency_enum" does not exist
    after  7 files -- relation "loan_templates" does not exist
    after 21 files -- function storage.foldername(text) does not exist
    after 23 files -- cannot change return type of existing function
                      (app.submit_draft, in module16)

  The first two are the app's own and are now in supabase/rebuild_bootstrap.sql:
  two enum types and one table that exist in production and in NO migration.
  All three predate the 2026-07-30 filename repair, which renamed files and
  rewrote the ledger but could not capture objects made by hand in the
  dashboard, because nothing recorded that they had been.

  The third is scaffolding -- a Supabase storage helper -- and is stubbed.

  THE FOURTH IS A REAL DEFECT AND IS STILL OPEN. A migration uses
  CREATE OR REPLACE FUNCTION on a function whose return type changed, which
  Postgres refuses. It works against production only because the function
  already existed there in a shape that made the replace legal. Against an
  empty database it cannot run. This is the DROP-then-CREATE rule CLAUDE.md
  records, caught on the one path that can catch it.

  Fixing it means editing a historical migration, and a migration file is a
  record of what ran. That is a decision, not a tidy-up, so it is left here
  rather than taken quietly.

.EXAMPLE
  pwsh tool/verify_rebuild.ps1
#>
[CmdletBinding()]
param(
  [int]$Port = 5433,
  [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin',
  # Keep the cluster afterwards, to poke at what was built.
  [switch]$Keep
)

$ErrorActionPreference = 'Continue'
$repo = Resolve-Path "$PSScriptRoot/.."
$data = Join-Path $env:TEMP "mana_rebuild_cluster"
$db = 'mana_rebuild'

foreach ($t in @('initdb', 'pg_ctl', 'psql')) {
  if (-not (Test-Path "$PgBin\$t.exe")) {
    Write-Error "$t not found in $PgBin. Install the PostgreSQL client and server tools, or pass -PgBin."
    exit 2
  }
}

function Psql([string]$database, [string[]]$extra) {
  & "$PgBin\psql.exe" -h localhost -p $Port -U postgres -d $database -w @extra
}

# A cluster of its own, so nothing here can reach a database somebody cares
# about. Trust auth because it is local, disposable, and holds nothing.
if (Test-Path $data) {
  & "$PgBin\pg_ctl.exe" -D $data stop -m immediate 2>&1 | Out-Null
  Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
}
Write-Host 'Creating a disposable cluster...'
& "$PgBin\initdb.exe" -D $data -U postgres --auth=trust --encoding=UTF8 2>&1 | Out-Null
Start-Process -FilePath "$PgBin\pg_ctl.exe" `
  -ArgumentList @('-D', $data, '-o', "-p $Port", '-l', "$data\log.txt", 'start') `
  -NoNewWindow -Wait | Out-Null
Start-Sleep -Seconds 3

$up = Psql 'postgres' @('-At', '-c', 'select 1')
if ($LASTEXITCODE -ne 0) {
  Write-Error "The cluster did not start. See $data\log.txt"
  exit 1
}

Psql 'postgres' @('-q', '-c', "DROP DATABASE IF EXISTS $db") | Out-Null
Psql 'postgres' @('-q', '-c', "CREATE DATABASE $db") | Out-Null

Write-Host 'Applying supabase/rebuild_bootstrap.sql...'
Psql $db @('-q', '-v', 'ON_ERROR_STOP=1', '-f', "$repo\supabase\rebuild_bootstrap.sql") | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error 'The bootstrap itself failed.'; exit 1 }

$files = Get-ChildItem "$repo\supabase\migrations" -Filter '*.sql' | Sort-Object Name
Write-Host "Applying $($files.Count) migrations..."

$applied = 0
foreach ($f in $files) {
  $out = Psql $db @('-q', '-v', 'ON_ERROR_STOP=1', '-f', $f.FullName) 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host "STOPPED after $applied of $($files.Count) migrations" -ForegroundColor Red
    Write-Host "  at: $($f.Name)" -ForegroundColor Red
    ($out | Select-String -Pattern 'ERROR' | Select-Object -First 3) |
      ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'The repo cannot rebuild the database from empty. See the notes'
    Write-Host 'at the top of this script for what is known about why.'
    if (-not $Keep) { & "$PgBin\pg_ctl.exe" -D $data stop -m immediate 2>&1 | Out-Null }
    exit 3
  }
  $applied++
}

Write-Host ''
Write-Host "ALL $applied MIGRATIONS APPLIED CLEANLY" -ForegroundColor Green
Write-Host ''
Write-Host 'The schema rebuilt from nothing. The five scratch SQL test files in'
Write-Host 'supabase/tests/ can now be run against it -- they have never'
Write-Host 'executed, because until now there was no empty database to run them'
Write-Host 'on:'
Write-Host ''
Write-Host "  `$env:MANA_DB_URL = 'postgresql://postgres@localhost:$Port/$db'"
Write-Host '  pwsh tool/run_sql_tests.ps1 -AllowNonEmpty'

if (-not $Keep) {
  & "$PgBin\pg_ctl.exe" -D $data stop -m immediate 2>&1 | Out-Null
  Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
} else {
  Write-Host ''
  Write-Host "Cluster left running on port $Port (data: $data)."
}

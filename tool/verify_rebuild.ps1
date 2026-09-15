<#
.SYNOPSIS
  Can this repo rebuild the database from nothing?

.DESCRIPTION
  supabase/MIGRATIONS.md carried this as an open question from 2026-07-30:

    "Nothing has verified that running all 58 files in order against an EMPTY
     database reproduces the current schema... Until someone does it, treat
     'the repo can rebuild the database' as probable but unproven."

  As of 2026-09-15 the answer is YES, and this script is what says so. It
  creates a DISPOSABLE Postgres cluster on port 5433 with trust auth, in a temp
  directory, applies supabase/rebuild_bootstrap.sql and then every migration in
  order. It touches neither production nor any local database you already have
  -- it does not need a password, because it makes its own server.

  A zero exit means the schema rebuilt. Exit 3 means it stopped, and it names
  the file and the error.

.NOTES
  WHAT IT FOUND, in the order the failures appeared. Every one of these was
  invisible to `flutter analyze`, to `flutter test`, and to applying the
  migrations against production -- because production already had the objects
  each one failed to create.

    1. type "repayment_frequency_enum" does not exist        (file 6)
    2. relation "loan_templates" does not exist              (file 7)
       Two enum types and one table that exist in production and in NO
       migration, made by hand in the dashboard before the 2026-07-30 filename
       repair, which could not capture them because nothing recorded them.
       Now in supabase/rebuild_bootstrap.sql.

    3. function storage.foldername(text) does not exist      (file 21)
       Supabase scaffolding. Stubbed in the bootstrap.

    4. cannot change return type of existing function        (file 23)
       app.submit_draft in module16 used CREATE OR REPLACE where the return
       type changed. It worked against production only because the function
       was already there in a shape that made the replace legal. Fixed with
       DROP-then-CREATE, the rule CLAUDE.md already records.

    5. constraint "chk_businesses_owner_bf_nonneg" already exists   (file 95)
       22 migrations were present under TWO names -- a hand-named pre-apply
       draft and its ledger-stamped twin. The drafts had no ledger row and
       were deleted. 19 translation keys lived only in them; those and 21
       others became 20260915140000_restore_orphaned_translation_keys.sql.

    6. extension "pg_cron" is not available                  (file 95)
       Supabase provides it, stock PostgreSQL does not, and CREATE EXTENSION
       for something absent from disk cannot be made to succeed from SQL. The
       statement is neutralised through $platformExtensions below -- NAMED and
       printed every run -- and cron.schedule is stubbed in the bootstrap so
       the two purge schedules still record that they were asked for.

    7. column "village_code" of "lgd_villages" does not exist       (file 196)
       The CREATE had been rewritten to describe the end state, so the next
       migration dropped columns it no longer created. The ledger's own copy
       still had them. A migration edited to look right is the one thing in
       that directory that cannot be trusted.

    8. "ledger_history no longer contains the text it was matching on"  (261)
       Six migrations patch a function by reading pg_get_functiondef and
       running replace() on it. The defining file was CRLF and the patching
       file was LF, so the anchor was present, identical on screen, and could
       never match. 97 of 426 files were CRLF with no rule saying which they
       should be. .gitattributes now pins *.sql to LF and
       test/migration_line_endings_test.dart fails on a CR.

  WHAT THE REBUILT DATABASE IS FOR. The five scratch files in supabase/tests/
  had never executed, because running them needs a database with no books in it
  and branching is a Pro-plan feature. They run against this one. On their
  first execution they found eight further things, six of them defects in the
  tests themselves -- a 15-character MLID in a varchar(13), a gender_digit
  assertion stale since Others was added, an address fixture missing five
  NOT NULL columns, a day_ledger row the recompute trigger had already made,
  and a penalty assertion that depended on a default it had backwards.

  A test that has never run does not go stale loudly. It goes stale quietly,
  and then reports the schema as broken.

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
# THE SERVER IS STARTED DIRECTLY, NOT THROUGH pg_ctl.
#
# pg_ctl start cannot be called from this script on Windows. Measured rather
# than reasoned about, after two wrong fixes -- initdb finishes in 8.4s, and
# every one of these never returned at all:
#
#   & pg_ctl ... | Out-Null                 the surviving postmaster inherits
#                                           the pipeline handle; Out-Null waits
#                                           for a writer that never closes
#   & pg_ctl ... *> $null                   still hangs: pg_ctl start blocks
#                                           whenever its output is redirected,
#                                           null device included
#   Start-Process pg_ctl -NoNewWindow -Wait waits on the process tree, and the
#                                           postmaster is in it
#
# The symptom is what made this expensive: the script sits on "Creating a
# disposable cluster..." while a perfectly healthy server accepts connections
# beside it, so every instinct blames the database. Earlier runs of this script
# appeared to work only because a previous -Keep had left a cluster already
# running on the port.
#
# postgres.exe IS the server, so there is no wrapper to out-wait. It is started
# without -Wait (waiting on a server is a category error) and then POLLED until
# it answers, which is the thing actually being waited for.
Start-Process -FilePath "$PgBin\postgres.exe" `
  -ArgumentList "-D `"$data`" -p $Port" `
  -NoNewWindow `
  -RedirectStandardOutput "$data\stdout.log" `
  -RedirectStandardError "$data\log.txt" | Out-Null

$ready = $false
$deadline = (Get-Date).AddSeconds(60)
while (-not $ready -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 500
  & "$PgBin\psql.exe" -h localhost -p $Port -U postgres -d postgres -w -At -c 'select 1' *> $null
  $ready = ($LASTEXITCODE -eq 0)
}
if (-not $ready) {
  Write-Error "The cluster did not accept a connection within 60s. See $data\log.txt"
  exit 1
}

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

# Extensions the Supabase platform provides and a stock PostgreSQL does not.
# CREATE EXTENSION for something absent from disk cannot be made to succeed
# from SQL, so the statement is neutralised here and the objects it would have
# brought are stubbed in rebuild_bootstrap.sql.
#
# NAMED, not pattern-matched, and printed every run: a rebuild that quietly
# skipped statements would prove nothing. pgcrypto and pg_trgm are contrib and
# are NOT on this list -- they install for real.
$platformExtensions = @('pg_cron')

$stage = Join-Path $env:TEMP 'mana_rebuild_stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($e in $platformExtensions) {
  Write-Host "  CREATE EXTENSION $e is stubbed (Supabase provides it; see rebuild_bootstrap.sql)."
}

$applied = 0
foreach ($f in $files) {
  $text = [IO.File]::ReadAllText($f.FullName)
  $patched = $text
  foreach ($e in $platformExtensions) {
    $patched = [regex]::Replace($patched,
      "CREATE\s+EXTENSION\s+(IF\s+NOT\s+EXISTS\s+)?""?$([regex]::Escape($e))""?[^;]*;",
      "SELECT 'platform extension $e stubbed by verify_rebuild.ps1';",
      'IgnoreCase')
  }
  $target = $f.FullName
  if ($patched -ne $text) {
    $target = Join-Path $stage $f.Name
    [IO.File]::WriteAllText($target, $patched, (New-Object Text.UTF8Encoding $false))
  }
  $out = Psql $db @('-q', '-v', 'ON_ERROR_STOP=1', '-f', $target) 2>&1
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
Write-Host 'The schema rebuilt from nothing. Run the five scratch SQL test'
Write-Host 'files against it -- this cluster is the only place they can run,'
Write-Host 'because they need a database with no books in it:'
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

# Explicit, because the teardown above is the last thing to set $LASTEXITCODE
# and pg_ctl stop reports non-zero on a cluster that has already gone. A
# successful rebuild reporting failure is the one outcome this script must not
# produce.
exit 0

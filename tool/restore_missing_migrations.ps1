<#
.SYNOPSIS
  Writes a local .sql file for every migration that was applied to the
  database but whose file was never written.

.DESCRIPTION
  THE DRIFT THIS REPAIRS. `supabase_migrations.schema_migrations` is the
  record of what actually ran. When a migration is applied through the
  management API (which is how every migration in this project is applied --
  see CLAUDE.md), the ledger row is created but the local file is only written
  if somebody remembers. On 2026-09-15 a census found 421 ledger rows and 418
  local files, with 42 applied migrations having no file at all.

  Seventeen of those forty-two were the SAME migration under a hand-written
  timestamp -- `20260803010000_batch_a_bf_loan_gate.sql` against the stamped
  `20260804212717`. Those were matched by CONTENT fingerprint, not by name,
  and renamed with `git mv` so their history follows them.

  The rest could not be renamed, because the applied SQL and the local file
  genuinely differ. `batch_a_cheti_bf` is the clearest: the file says
  `ALTER TABLE agent_permissions ADD COLUMN can_record_cheti`, and what ran
  says `ADD COLUMN IF NOT EXISTS`. Renaming the file onto that version would
  make the repo claim to reproduce something it does not.

.NOTES
  WHY A SCRIPT AND NOT AN ASSISTANT DOING IT BY HAND.

  These files are mostly `INSERT INTO ui_translations` with Telugu strings --
  about 32 KB of them. Retyping that through any intermediary is precisely
  where silent corruption enters, and a corrupted Telugu label is invisible to
  every guard this repo has: it is a perfectly valid string, of a plausible
  length, in the right column. It would reach a user and look deliberate.

  `git mv` carries no such risk, which is why the seventeen renames were done
  by hand and these are not. This copies bytes.

.NOTES
  Needs MANA_DB_URL, the same variable tool/run_sql_tests.ps1 uses. It is NOT
  in this repo and must not be: run.ps1.txt carries the anon key because that
  ships inside every APK anyway, and a database password does not.

.EXAMPLE
  $env:MANA_DB_URL = '...'; pwsh tool/restore_missing_migrations.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  # Where the files go. Only ever this, but overridable for a dry run.
  [string]$MigrationsDir = "$PSScriptRoot/../supabase/migrations"
)

$ErrorActionPreference = 'Stop'

if (-not $env:MANA_DB_URL) {
  Write-Error @'
MANA_DB_URL is not set.

It is deliberately not in this repo. Take the connection string from the
Supabase dashboard (Project Settings -> Database -> Connection string, URI),
and set it for this shell only:

  $env:MANA_DB_URL = 'postgresql://...'

Do not put it in run.ps1.txt, .claude/launch.json, or any other tracked file.
'@
  exit 2
}

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
  Write-Error 'psql is not on PATH. Install the PostgreSQL client tools, or run this from a machine that has them.'
  exit 2
}

$MigrationsDir = (Resolve-Path $MigrationsDir).Path
Write-Host "Migrations directory: $MigrationsDir"

# Which versions already have a file. The filename's leading 14 digits are the
# version; anything else the CLI ignores silently, which is the original sin
# recorded in supabase/MIGRATIONS.md.
$local = @{}
Get-ChildItem -Path $MigrationsDir -Filter '*.sql' | ForEach-Object {
  if ($_.Name -match '^(\d{14})_') { $local[$Matches[1]] = $_.Name }
}
Write-Host "Local files: $($local.Count)"

# Versions and names only -- small, and enough to decide what to fetch.
$rows = & psql $env:MANA_DB_URL -At -F '|' -c @'
select version, name from supabase_migrations.schema_migrations order by version;
'@
if ($LASTEXITCODE -ne 0) { Write-Error 'Could not read the ledger.'; exit 1 }

$missing = @()
foreach ($row in $rows) {
  if (-not $row) { continue }
  $version, $name = $row -split '\|', 2
  if (-not $local.ContainsKey($version)) {
    $missing += [pscustomobject]@{ Version = $version; Name = $name }
  }
}

Write-Host "Ledger rows: $($rows.Count)"
Write-Host "Applied with no local file: $($missing.Count)"
if ($missing.Count -eq 0) { Write-Host 'Nothing to restore.'; exit 0 }

$written = 0
foreach ($m in $missing) {
  $file = Join-Path $MigrationsDir ("{0}_{1}.sql" -f $m.Version, $m.Name)

  if (-not $PSCmdlet.ShouldProcess($file, 'restore from schema_migrations')) {
    Write-Host "  would write $(Split-Path $file -Leaf)"
    continue
  }

  # -At: unaligned, tuples only, no headers or footers. The statements array
  # is joined with a blank line between entries, which is how a multi-statement
  # migration reads back as a file rather than as one enormous line.
  #
  # Straight to the file. The contents never pass through a variable, a
  # console, or anything that might re-encode them -- these are UTF-8 Telugu
  # strings and every extra hop is a chance to mangle one.
  $sql = "select array_to_string(statements, E'\n\n') from supabase_migrations.schema_migrations where version = '$($m.Version)';"
  & psql $env:MANA_DB_URL -At -c $sql | Set-Content -Path $file -Encoding utf8 -NoNewline

  if ($LASTEXITCODE -ne 0) { Write-Error "Failed on $($m.Version)"; exit 1 }
  Add-Content -Path $file -Value "`n" -Encoding utf8
  Write-Host "  wrote $(Split-Path $file -Leaf)"
  $written++
}

Write-Host ''
Write-Host "Restored $written file(s)."
Write-Host @'
Now, before committing:

  1. `git status` -- every new file should be exactly what ran, nothing else.
  2. `flutter test test/translation_keys_exist_test.dart` -- the
     _appliedButFileMissing list in that file should now be shrinkable. Remove
     the names it no longer needs; shrinking it is progress, adding to it is
     not.
  3. Read one of the restored files. The ledger stores what was SENT, so the
     explanatory comment blocks that were trimmed at apply time are gone. That
     is what ran, and the file is a record of what ran -- do not re-add them
     from memory.
'@

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
  #
  # Defaulted in the BODY, not here. $PSScriptRoot is empty while a param
  # default is being evaluated under Windows PowerShell 5.1, so
  # "$PSScriptRoot/../supabase/migrations" collapsed to "/../supabase/migrations"
  # and resolved against the drive root -- D:\supabase\migrations, which does
  # not exist. The .env read further down uses $PSScriptRoot successfully
  # because that runs in the body, where it is populated.
  [string]$MigrationsDir
)

$ErrorActionPreference = 'Stop'

# .env is the documented home for anything that must not be committed --
# CLAUDE.md: "Put those in .env (already ignored)" -- and it is line 171 of
# .gitignore. Read here so the connection string can live in one place rather
# than being re-exported into every new shell.
#
# Only MANA_DB_URL is taken. This is not a general .env loader, because a
# script that quietly imports every name in a file is a script that can be
# handed a PATH.
$envFile = Join-Path $PSScriptRoot '../.env'
if (-not $env:MANA_DB_URL -and (Test-Path $envFile)) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*MANA_DB_URL\s*=\s*(.+?)\s*$') {
      $env:MANA_DB_URL = $Matches[1].Trim().Trim('"').Trim("'")
      Write-Host 'Read MANA_DB_URL from .env'
      break
    }
  }
}

if (-not $env:MANA_DB_URL) {
  Write-Error @'
MANA_DB_URL is not set, and .env does not carry it either.

Take the connection string from the Supabase dashboard (Project Settings ->
Database -> Connection string, URI) and put it in .env at the repo root:

  MANA_DB_URL=postgresql://...

.env is git-ignored (.gitignore line 171) and is where CLAUDE.md says anything
uncommittable belongs. Do NOT put it in run.ps1.txt or .claude/launch.json --
both are tracked.

If the password contains : / ? # [ ] @ or %, percent-encode it in the URI --
$ becomes %24, @ becomes %40. This script decodes them again before use.
'@
  exit 2
}

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
  Write-Error 'psql is not on PATH. Install the PostgreSQL client tools, or run this from a machine that has them.'
  exit 2
}

if (-not $MigrationsDir) {
  $MigrationsDir = Join-Path $PSScriptRoot '../supabase/migrations'
}
if (-not (Test-Path $MigrationsDir)) {
  Write-Error "Migrations directory not found: $MigrationsDir"
  exit 2
}
# THE PASSWORD NEVER GOES ON A COMMAND LINE OR INTO A URI.
#
# The first version handed psql the whole connection URI. A password containing
# a `$` broke libpq's URI parsing, which then printed the mis-parsed HOST --
# with the password inside it -- into stderr, and from there into a terminal
# and a chat log. A credential that only leaks when something goes wrong is a
# credential that leaks exactly when somebody is watching the output.
#
# So the URI is split here and the password is handed over through PGPASSWORD,
# which libpq reads from the environment. That also keeps it out of the process
# list, where a command line is readable by any other process on the machine.
#
# Percent-decoding matters: a password written correctly as %24 in the URI must
# reach libpq as `$`.
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
try {
  $uri = [System.Uri]$env:MANA_DB_URL
} catch {
  Write-Error 'MANA_DB_URL is not a valid postgresql:// URI. Expected: postgresql://USER:PASSWORD@HOST:PORT/DATABASE'
  exit 2
}
$userInfo = $uri.UserInfo -split ':', 2
$pgUser = [System.Uri]::UnescapeDataString($userInfo[0])
$pgPass = if ($userInfo.Count -gt 1) { [System.Uri]::UnescapeDataString($userInfo[1]) } else { '' }
$pgHost = $uri.Host
$pgPort = if ($uri.Port -gt 0) { $uri.Port } else { 5432 }
$pgDb   = $uri.AbsolutePath.TrimStart('/')
if (-not $pgDb) { $pgDb = 'postgres' }

if (-not $pgHost -or -not $pgUser) {
  Write-Error 'MANA_DB_URL is missing a host or a user.'
  exit 2
}

# Only this leaves the script. Never $pgPass.
Write-Host "Connecting to $pgHost as $pgUser (database $pgDb)"
$env:PGPASSWORD = $pgPass

# psql arguments, minus the credential. Reused by every call below.
$psqlArgs = @('-h', $pgHost, '-p', $pgPort, '-U', $pgUser, '-d', $pgDb, '-w')

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
$rows = & psql @psqlArgs -At -F '|' -c @'
select version, name from supabase_migrations.schema_migrations order by version;
'@
if ($LASTEXITCODE -ne 0) {
  $env:PGPASSWORD = ''
  Write-Error 'Could not read the ledger. Check the host, user and password in .env.'
  exit 1
}

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
  # -o: PSQL WRITES THE FILE. PowerShell never holds the bytes.
  #
  # The first version piped psql into `Set-Content -NoNewline`. PowerShell
  # captures a native command's stdout as an ARRAY OF LINES, and -NoNewline
  # then joins that array with nothing at all -- so every newline in the
  # migration vanished and each file arrived as one enormous line. Valid SQL,
  # because SQL is whitespace-insensitive, and unreadable by a person.
  #
  # Set-Content -Encoding utf8 on Windows PowerShell 5.1 also prepends a BOM,
  # which has no business at the start of a .sql file.
  #
  # Letting psql write the file solves both, and is what "copies bytes" was
  # supposed to mean in the first place.
  $sql = "select array_to_string(statements, E'\n\n') from supabase_migrations.schema_migrations where version = '$($m.Version)';"
  & psql @psqlArgs -At -o $file -c $sql

  if ($LASTEXITCODE -ne 0) { Write-Error "Failed on $($m.Version)"; exit 1 }
  Write-Host "  wrote $(Split-Path $file -Leaf)"
  $written++
}

$env:PGPASSWORD = ''

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

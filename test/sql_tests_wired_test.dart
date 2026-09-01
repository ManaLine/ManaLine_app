import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The SQL tests run, can report a failure, and cannot be aimed at a live book
/// by accident.
///
/// THE PROBLEM THIS EXISTS FOR: `supabase/tests/` held five files for months and
/// nothing ever executed them. The assertions added most recently — no customer
/// with a live loan outside an active operating area, no village recording a
/// state the PIN directory does not carry, no SECURITY INVOKER trigger reaching
/// into the app schema — had never run once. A guard nobody runs is worse than
/// no guard, because it reads as cover.
///
/// TWO KINDS OF FILE, and the difference is not cosmetic:
///
///   * `@target: scratch` files fabricate persons, businesses and loans. They
///     must never be pointed at a real database.
///   * `@target: production` files only read. They are the ones worth running
///     against a live book, and the only ones that can be — a stranded customer
///     or a mistyped state cannot be reproduced with fixtures, so against an
///     empty branch they pass trivially and prove nothing.
///
/// The runner enforces the split at runtime: scratch files are refused unless
/// the target holds no businesses or loans, and production files run with
/// `default_transaction_read_only=on` so a write raises 25006.
///
/// WHY RUNTIME AND NOT A GREP. Deciding which files were safe, I counted INSERT
/// statements and concluded `migration_weekly_ledger_tests.sql` wrote nothing.
/// Its writes are inside `app.import_weekly_account` — invisible to any reading
/// of the file's own statements, and it was replaying twelve fabricated weeks
/// over whichever business happened to be oldest. Static inspection cannot
/// answer this question, so the checks below verify the DECLARATIONS and the
/// runner verifies the BEHAVIOUR.
void main() {
  final testDir = Directory('supabase/tests');
  final runner = File('tool/run_sql_tests.ps1');

  test('the runner exists where CLAUDE.md says it does', () {
    expect(runner.existsSync(), isTrue,
        reason: 'tool/run_sql_tests.ps1 is the documented way to run these');
  });

  test('there are SQL tests to run', () {
    expect(testDir.existsSync(), isTrue);
    final files = testDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'));
    expect(files, isNotEmpty);
  });

  group('every SQL test file', () {
    final files = testDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final source = file.readAsStringSync();
      final marker =
          RegExp(r'^\s*--\s*@target:\s*(\S+)', multiLine: true).firstMatch(source);
      final target = marker?.group(1)?.toLowerCase();
      // Comments explain the patterns these files must NOT use, and quoting one
      // is not committing it. Checks that look for a construct match code only.
      final code = source.replaceAll(RegExp(r'--[^\n]*'), '');

      test('$name declares what it may be run against', () {
        // The runner defaults an undeclared file to scratch, which is the safe
        // direction — but silently inheriting a safety property is how the
        // weekly-ledger file came to be pointed at a real book. Say it.
        expect(
          target,
          anyOf('scratch', 'production'),
          reason: '$name has no `-- @target: scratch` or `-- @target: '
              'production` line near the top. scratch = builds fixtures, never '
              'run against a live database. production = reads only, safe '
              'anywhere and only meaningful on real data.',
        );
      });

      test('$name can announce a failure', () {
        // The runner detects a failed assertion by looking for a WARNING line
        // mentioning FAIL. A file that reports only NOTICEs passes silently
        // however broken the schema is.
        expect(
          RegExp(r"RAISE\s+WARNING\s+'[^']*FAIL").hasMatch(source),
          isTrue,
          reason: "$name never raises a WARNING containing 'FAIL', so the "
              'runner cannot tell a failed assertion from a passing one. '
              'Follow the si_log pattern in schema_integrity_tests.sql.',
        );
      });

      if (target != 'production') {
        test('$name leaves nothing behind', () {
          // These build fixtures. Against a live database a missing ROLLBACK is
          // not a failed test, it is a data incident.
          expect(
            RegExp(r'^\s*ROLLBACK\s*;', multiLine: true).hasMatch(source),
            isTrue,
            reason: '$name has no ROLLBACK. Every scratch file builds fixtures '
                'and must undo them.',
          );
        });

        test('$name builds its own fixtures rather than adopting a real row',
            () {
          // The specific bug: `SELECT ... FROM businesses ORDER BY created_at
          // LIMIT 1` reads as "any business will do" and means "the oldest real
          // book on this database". Three blocks did it, and the transaction
          // was the only thing between them and a rewritten ledger.
          expect(
            RegExp(r'FROM\s+businesses\s+ORDER\s+BY', caseSensitive: false)
                .hasMatch(code),
            isFalse,
            reason: '$name picks an existing business by ordering the table. '
                'Create a fixture business instead — see wk_fixture in '
                'migration_weekly_ledger_tests.sql.',
          );
        });
      }

      if (target == 'production') {
        test('$name contains no DDL', () {
          // default_transaction_read_only forbids CREATE outright — temp tables
          // and pg_temp functions included, which is NOT what I assumed and had
          // to be found by running it. So a production file cannot open with
          // the temp-results harness the scratch files use; it raises its own
          // NOTICE and WARNING inline. Catching that here gives a reason
          // instead of a bare 25006 at the far end of a psql run.
          expect(
            RegExp(r'\b(CREATE|DROP|ALTER)\s+(TEMP|TEMPORARY|TABLE|FUNCTION|VIEW|INDEX)',
                    caseSensitive: false)
                .hasMatch(code),
            isFalse,
            reason: '$name is @target: production, so it runs read-only and '
                'any CREATE/DROP/ALTER raises 25006 — temp tables and pg_temp '
                'functions included. Raise NOTICE/WARNING inline instead.',
          );
        });

        test('$name does not opt out of the read-only session', () {
          // The runner sets default_transaction_read_only=on. A file can undo
          // that in one line, and then nothing is protecting a live book.
          expect(
            RegExp(r'READ\s+WRITE|default_transaction_read_only\s*(=|TO)\s*off',
                    caseSensitive: false)
                .hasMatch(code),
            isFalse,
            reason: '$name turns the read-only session off. That session is the '
                'only thing making a production-targeted file safe.',
          );
        });
      }
    }
  });

  test('the SQL assertions actually pass', () {
    final url = Platform.environment['MANA_DB_URL'];
    if (url == null || url.trim().isEmpty) {
      // Not a silent skip: printing is what stops this reading as coverage.
      // ignore: avoid_print
      print('SKIPPED — MANA_DB_URL is not set, so the SQL assertions were not '
          'executed. Set it and re-run to check them:\n'
          r'  $env:MANA_DB_URL = "postgresql://postgres:<password>@<host>:5432/postgres"'
          '\n  flutter test test/sql_tests_wired_test.dart\n'
          'Against the live project only the @target: production files run; '
          'the fixture-building ones need a scratch database.');
      return;
    }

    final result = Process.runSync(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', runner.path],
      environment: {'MANA_DB_URL': url},
    );

    expect(
      result.exitCode,
      0,
      reason: 'SQL assertions failed. Runner output:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });
}

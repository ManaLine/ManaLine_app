import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The SQL tests run, and can report a failure when they have one.
///
/// THE PROBLEM THIS EXISTS FOR: `supabase/tests/` has held five files for
/// months and nothing ever executed them. The assertions added most recently —
/// no customer with a live loan outside an active operating area, no village
/// recording a state the PIN directory does not carry, no SECURITY INVOKER
/// trigger reaching into the app schema — had never run once. A guard nobody
/// runs is worse than no guard, because it reads as cover.
///
/// Two halves, and only one of them can work offline:
///
///   * the CONVENTION check always runs. Every file must be able to announce a
///     failure in the way the runner detects, and must clean up after itself.
///     A new test file that silently passes, or one that forgets its ROLLBACK
///     and leaves fixtures in a live database, fails here;
///   * the EXECUTION check runs when `MANA_DB_URL` is set, shelling out to
///     tool/run_sql_tests.ps1 and asserting it exits zero. Without the
///     variable it skips loudly rather than passing quietly, because a green
///     tick that means "did not look" is the thing being fixed.
///
/// The database password is deliberately not in this repo. run.ps1.txt carries
/// the anon key because that ships inside every APK anyway; a password does
/// not, so the execution half is opt-in by whoever holds one — and a branch
/// database for preference, since these files write fixtures before rolling
/// them back.
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

      test('$name leaves nothing behind', () {
        // These build fixtures. Against a live database a missing ROLLBACK is
        // not a failed test, it is a data incident.
        expect(
          RegExp(r'^\s*ROLLBACK\s*;', multiLine: true).hasMatch(source),
          isTrue,
          reason: '$name has no ROLLBACK. Every file in here builds fixtures '
              'and must undo them.',
        );
      });
    }
  });

  test('the SQL assertions actually pass', () {
    final url = Platform.environment['MANA_DB_URL'];
    if (url == null || url.trim().isEmpty) {
      // Not a silent skip: printing is what stops this reading as coverage.
      // ignore: avoid_print
      print('SKIPPED — MANA_DB_URL is not set, so the SQL assertions were not '
          'executed. Set it to a branch database and re-run to check them:\n'
          r'  $env:MANA_DB_URL = "postgresql://postgres:<password>@<host>:5432/postgres"'
          '\n  flutter test test/sql_tests_wired_test.dart');
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

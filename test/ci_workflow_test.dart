import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The guards only guard if something runs them.
///
/// This repo's whole safety story is its tests -- the consumer census, the
/// enum-literal scan, the invented-function-name scan, the layout sweeps at
/// four text scales in two languages, the raw-key sweep over 1,336 keys. Every
/// one of them has, until now, depended on a person remembering to type
/// `flutter test` before pushing.
///
/// That is the largest single gap between this codebase and a maintained one,
/// and it is also the cheapest to close: nothing new has to be written, only
/// run. Automating tests that already exist is worth more than any test that
/// could be added beside them.
///
/// WHY A TEST FOR A YAML FILE. Because the failure mode is deletion, not
/// breakage. A workflow that is removed, renamed, or has its `flutter test`
/// step commented out during a debugging session leaves no trace in the app --
/// analyze stays clean, the suite still passes locally, and the only symptom
/// is that nothing ever fails again. This makes that state loud.
void main() {
  final file = File('.github/workflows/ci.yml');

  /// The workflow with its comment lines removed.
  ///
  /// EVERY assertion below runs against this, not the raw file. The first
  /// version of this test did not, and all three of its content checks failed
  /// against the workflow's own explanation of itself: the comment saying
  /// "not `channel: stable`" tripped the no-floating-channel check, the
  /// comment mentioning MANA_DB_URL tripped the no-credentials check, and the
  /// sentence "remembering to type `flutter test`" was found before the step
  /// that actually runs it.
  ///
  /// This project has now made that mistake twice -- the other was a
  /// placeholder scan flagging its own doc comment -- and it is worth naming:
  /// a guard that reads prose as if it were code reports faults that cannot
  /// happen, and the reflex when that happens is to loosen the guard.
  ///
  /// Full-line comments only. There are no trailing `#` comments in this
  /// workflow, and stripping those properly means parsing YAML strings, which
  /// is more machinery than the check is worth. If one is ever added, this
  /// test will say something confusing rather than something false.
  String code() => file
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  test('there is a CI workflow at all', () {
    expect(file.existsSync(), isTrue,
        reason: 'no .github/workflows/ci.yml -- nothing runs the guards');
  });

  group('what it runs', () {
    late String yaml;
    setUp(() => yaml = code());

    test('it runs the analyzer and the whole suite', () {
      expect(yaml, contains('flutter analyze'));
      expect(yaml, contains('flutter test'),
          reason: 'the step that runs the guards is gone');
    });

    test('the suite is not narrowed to a subset', () {
      // `flutter test test/some_file.dart` during a debugging session, left
      // behind, is a workflow that stays green while running almost nothing.
      final line = yaml
          .split('\n')
          .firstWhere((l) => l.trimLeft().startsWith('- run: flutter test'),
              orElse: () => '');
      expect(line, isNotEmpty,
          reason: 'no `- run: flutter test` step -- the suite is not run');
      expect(line.trim(), anyOf(endsWith('flutter test'), contains('--')),
          reason: 'flutter test has been given a path and now covers only '
              'part of the suite: "${line.trim()}"');
    });

    test('it fires on pushes and on pull requests', () {
      expect(yaml, contains('push:'));
      expect(yaml, contains('pull_request:'),
          reason: 'a PR that is never checked is checked by whoever merges it');
    });
  });

  group('what it runs on', () {
    late String yaml;
    setUp(() => yaml = code());

    test('the Flutter version is pinned, not floating', () {
      // `channel: stable` means a green build can turn red with no commit
      // behind it, and the failure arrives attributed to whoever pushed next.
      expect(yaml, contains('flutter-version:'),
          reason: 'the Flutter version is not pinned');
      expect(yaml, isNot(contains('channel: stable')),
          reason: 'a floating channel is how a build breaks with nobody having '
              'changed anything');
    });

    test('the pinned version matches what this repo is developed on', () {
      // Developed on 3.44.6. A CI on a different version is testing a
      // different app, and the disagreement surfaces as a mystery failure.
      expect(yaml, contains('3.44.6'),
          reason: 'CI pins a Flutter version this project is not built with');
    });
  });

  test('no credentials are baked into the test job', () {
    // The suite passes offline BY DESIGN -- verified 2026-09-15: nothing under
    // test/ reads SUPABASE_URL, and sql_tests_wired_test prints a skip rather
    // than failing when MANA_DB_URL is absent. If a secret ever appears in the
    // test job, something has started reaching the network from a test, and
    // that is the thing to fix rather than the workflow.
    final yaml = code();
    final testJob = yaml.substring(
      yaml.indexOf('  test:'),
      yaml.contains('  build:') ? yaml.indexOf('  build:') : yaml.length,
    );
    expect(testJob, isNot(contains('MANA_DB_URL')));
    expect(testJob, isNot(contains('secrets.')),
        reason: 'the test job has grown a secret, which means a test has '
            'started needing the network');
  });
}

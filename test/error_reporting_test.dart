import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A field agent hitting a bug in a village is, today, silent data loss.
///
/// There is no crash reporting at all. An app that breaks on a handset two
/// hours from anywhere produces exactly one artefact: a person who stops
/// using it. Nothing reaches anybody who could fix it, and the first signal
/// is a business quietly going back to paper.
///
/// This is Task 3 of docs/superpowers/plans/2026-09-15-production-readiness.md
/// and it is the second cheapest large gain after CI, for the same reason:
/// no new behaviour, only the ability to see what already happens.
void main() {
  final reporter = File('lib/shared/mana_error_reporting.dart');

  test('there is a reporter at all', () {
    expect(reporter.existsSync(), isTrue,
        reason: 'no lib/shared/mana_error_reporting.dart');
  });

  group('the DSN', () {
    late String src;
    setUp(() => src = reporter.readAsStringSync());

    test('comes from --dart-define, never a literal in the source', () {
      // Same route as the Supabase values, and for a sharper reason: a DSN
      // pasted into a tracked file is a write endpoint anybody with the repo
      // can post to.
      expect(src, contains('String.fromEnvironment'));
      expect(src, isNot(contains('https://')),
          reason: 'a literal DSN has been pasted into the source');
    });

    test('its absence is a normal state, not a crash', () {
      // A local debug build has no DSN, CI has no DSN, and the app must
      // behave identically without one. An error reporter that itself throws
      // on a missing key is worse than no reporter: it turns a working build
      // into a dead one at launch.
      expect(src, contains('isEmpty'),
          reason: 'nothing handles the no-DSN case');
    });

    test('run.ps1.txt still holds only the two public values', () {
      // CLAUDE.md is explicit that nothing else may be added to it, because
      // it is TRACKED. The URL and anon key are there only because both ship
      // inside every APK anyway. A DSN there would be the first step toward
      // a service-role key there.
      expect(File('run.ps1.txt').readAsStringSync(), isNot(contains('SENTRY')));
    });
  });

  group('what it is allowed to send', () {
    late String src;
    setUp(() => src = reporter.readAsStringSync());

    test('personally identifying data is off', () {
      // These are money screens. A customer's name, phone, village and
      // outstanding balance are on most of them, and a crash report that
      // scoops up the request body carries all four off the handset to a
      // third party. The people in this database did not agree to that and
      // largely could not be asked.
      expect(src, contains('sendDefaultPii = false'));
    });

    test('no performance tracing, which samples real traffic', () {
      // Tracing on a 2G village connection spends the user's data allowance
      // on telemetry. Crashes only.
      expect(src, contains('tracesSampleRate = 0.0'));
    });
  });

  group('the failures the app survives', () {
    // THE HALF A CRASH REPORTER NEVER SEES, and the reason this task is worth
    // more than wrapping runApp. NetworkErrorHandler.run catches a failure,
    // shows the user a sentence and returns null. Nothing crashed, so nothing
    // is reported -- and its own debugPrint is stripped from release builds,
    // so in the build a real Owner runs, a failure they are looking at leaves
    // no trace anywhere at all.
    //
    // A PostgREST 300 from an ambiguous embed, a timeout on a money write, an
    // RPC that was never created: all survived, all silent.
    late String src;
    setUp(() => src =
        File('lib/shared/network_error_handler.dart').readAsStringSync());

    test('handled failures are reported, not only shown', () {
      expect(src, contains('manaReportError'),
          reason: 'NetworkErrorHandler swallows every failure it shows; those '
              'are precisely the ones nobody will ever hear about');
    });

    test('reporting never delays the message the user is waiting for', () {
      // The person is standing there waiting to be told what happened. A
      // report that blocks their SnackBar has made the app worse to use in
      // order to tell somebody about it.
      expect(src, contains('unawaited(manaReportError('),
          reason: 'the report is awaited, so the user waits on telemetry');
    });

    test('the caller can name what was being attempted', () {
      // "PostgrestException" and nothing else costs as much to triage as no
      // report at all. The exception says what went wrong; only the caller
      // knows what it was doing.
      expect(src, contains('String? reportAs'));
      expect(src, contains('hint: reportAs'));
    });
  });

  group('both entrypoints report', () {
    // main.dart's own comment: this project "has already paid twice for two
    // copies of the same setup drifting apart". Android and web share
    // bootstrapManaApp for exactly that reason. Error reporting must not
    // become the third copy -- and a reporter wired into only one of them is
    // worse than none, because it reads as covered.
    test('android', () {
      expect(File('lib/main.dart').readAsStringSync(),
          contains('manaRunApp'),
          reason: 'the Android entrypoint calls runApp directly, so nothing '
              'wraps its error zone');
    });

    test('web', () {
      expect(File('lib/main_web.dart').readAsStringSync(),
          contains('manaRunApp'),
          reason: 'the web entrypoint calls runApp directly');
    });

    test('and they share one wrapper rather than owning a copy each', () {
      final src = reporter.readAsStringSync();
      expect(src, contains('manaRunApp'),
          reason: 'the shared wrapper is not where both can reach it');
    });
  });
}

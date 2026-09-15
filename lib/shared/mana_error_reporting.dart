import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Where errors go when nobody is watching the handset.
///
/// Before this, an app that broke in a village two hours from anywhere
/// produced exactly one artefact: a person who stopped using it. Nothing
/// reached anybody who could fix it, and the first signal would have been a
/// business quietly going back to paper.
///
/// THE DSN ARRIVES BY --dart-define, like the Supabase values, and NOT via
/// run.ps1.txt. That file is tracked, and CLAUDE.md is explicit that only the
/// URL and anon key may live in it because both ship inside every APK anyway.
/// A DSN is a write endpoint: less dangerous than a service-role key, and
/// still not something to hand to anybody who can read the repository.
///
/// AN EMPTY DSN IS A NORMAL STATE, not an error. A local debug build has
/// none, CI has none, and the app must behave identically without one. An
/// error reporter that throws on a missing key turns a working build into a
/// dead one at launch, which is a worse failure than the one it was added to
/// catch.
const String _dsn = String.fromEnvironment('SENTRY_DSN');

/// Whether anything is actually being reported. Useful in a debug screen; the
/// app's behaviour must not otherwise depend on it.
bool get manaErrorReportingEnabled => _dsn.isNotEmpty;

/// Start the app, with reporting around it when there is somewhere to report.
///
/// ONE WRAPPER FOR BOTH ENTRYPOINTS. main.dart and main_web.dart already share
/// `bootstrapManaApp` because, in that file's own words, this project "has
/// already paid twice for two copies of the same setup drifting apart". Error
/// reporting wired into one entrypoint and not the other would be that
/// mistake again, and worse than not having it: a half-covered app reads as
/// covered, so nobody looks for the gap.
///
/// Sentry's `appRunner` is what makes this more than a try/catch. It installs
/// the Flutter error handler and runs the app inside a guarded zone, so an
/// exception thrown inside a widget build, a gesture callback or an unawaited
/// future is caught -- which is most of them.
Future<void> manaRunApp(Widget app) async {
  if (_dsn.isEmpty) {
    runApp(app);
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = _dsn;

      // OFF, deliberately, and not a default worth accepting. These are money
      // screens: a customer's name, phone, village and outstanding balance are
      // on most of them. sendDefaultPii would attach request bodies and user
      // identifiers to every report, carrying all four off the handset to a
      // third party. The people in this database did not agree to that and
      // largely could not be asked.
      options.sendDefaultPii = false;

      // Crashes only. Tracing samples real traffic, and on a 2G village
      // connection that spends the user's own data allowance on telemetry.
      options.tracesSampleRate = 0.0;

      // Screenshots and view hierarchies are left off for the same reason as
      // sendDefaultPii -- a screenshot of a collection screen is a photograph
      // of somebody's debt.
      options.attachScreenshot = false;
      // attachViewHierarchy is left at its own default rather than set here:
      // the setter is marked experimental, and pinning the app to an API that
      // "could be removed or changed at any time" to restate a default it
      // already has is a dependency taken on for nothing. It is off.

      // Which build a report came from. Without it, a crash fixed three
      // builds ago and a crash happening now look identical in the list.
      options.environment = kReleaseMode ? 'release' : 'debug';
    },
    appRunner: () => runApp(app),
  );
}

/// Report something the app HANDLED but should not have had to.
///
/// The interesting half. NetworkErrorHandler.run catches a failure, shows the
/// user a message and returns null -- correct for the user, and invisible to
/// everybody else. A PostgREST 300, a timeout on a money write, an RPC that
/// does not exist: every one of those is survived, and none of them would
/// otherwise reach a crash reporter, because the app did not crash.
///
/// [hint] should name the action, not the error -- "record collection",
/// "submit settlement". The exception says what went wrong; only the caller
/// knows what was being attempted.
Future<void> manaReportError(
  Object error,
  StackTrace stack, {
  String? hint,
}) async {
  if (_dsn.isEmpty) return;
  await Sentry.captureException(
    error,
    stackTrace: stack,
    withScope: (scope) {
      if (hint != null) scope.setContexts('mana', {'where': hint});
    },
  );
}

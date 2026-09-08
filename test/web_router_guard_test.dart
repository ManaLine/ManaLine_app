import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/app/router.dart';
import 'package:mana_line/app/web_router.dart';

/// THE ENTIRE MITIGATION for having two routers in one app.
///
/// CLAUDE.md's core invariant is one route per screen ID, in one router.
/// `manaWebRouter` (lib/app/web_router.dart) is a deliberate exception to
/// that, built for Plan 3a's restricted web surface, and it was accepted
/// on one condition: the two routers cannot silently drift apart. This
/// test is that condition, not a decoration on it.
///
/// It fails three separate ways, and each one was verified to actually
/// fail before this file was considered done (see task-3-report.md for
/// the transcript of a route added to one side only, and one removed):
///
///   1. manaWebRouter registers a route manaRouter does not have
///      (excluding /web-home, which is web-only by design — there is no
///      dashboard-less "home" screen on Android to match it against).
///   2. manaWebRouter's actual route set no longer matches the published
///      kManaWebAllowedRoutes constant — the allowlist and the router
///      silently disagreeing about what is reachable.
///   3. kManaWebAllowedRoutes names a route manaWebRouter does not
///      actually register — the allowlist promising something that
///      does not exist.
///
/// Extracting paths from the live GoRouter objects (via `.configuration
/// .routes`) rather than hand-copying the two literal lists into this
/// file, because a hand-copied list here is exactly the second router
/// this project keeps getting bitten by — a copy that can go stale
/// without anyone noticing.
void main() {
  Set<String> pathsOf(GoRouter router) => router.configuration.routes
      .whereType<GoRoute>()
      .map((r) => r.path)
      .toSet();

  final androidPaths = pathsOf(manaRouter);
  final webPaths = pathsOf(manaWebRouter);

  test('every web route (except /web-home) also exists on Android', () {
    final webOnly = webPaths.difference(androidPaths)..remove('/web-home');
    expect(
      webOnly,
      isEmpty,
      reason: 'manaWebRouter registers a route manaRouter does not have: $webOnly. '
          'A route reachable on the web build must also be a real screen ID '
          'in the app — the web router reuses screens, it does not invent them.',
    );
  });

  test('manaWebRouter\'s route set matches kManaWebAllowedRoutes exactly', () {
    final missingFromRouter = kManaWebAllowedRoutes.difference(webPaths);
    final extraInRouter = webPaths.difference(kManaWebAllowedRoutes);
    expect(
      missingFromRouter,
      isEmpty,
      reason: 'kManaWebAllowedRoutes names a route manaWebRouter never '
          'registers: $missingFromRouter. The published allowlist and the '
          'actual router have drifted apart.',
    );
    expect(
      extraInRouter,
      isEmpty,
      reason: 'manaWebRouter registers a route absent from '
          'kManaWebAllowedRoutes: $extraInRouter. Either the route was added '
          'without updating the allowlist, or it should not be reachable on '
          'the web build at all.',
    );
  });
}

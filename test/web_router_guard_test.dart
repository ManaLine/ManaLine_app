import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/app/router.dart';
import 'package:mana_line/app/web_router.dart';

/// A BuildContext that answers nothing -- deliberately. Every shared-route
/// builder below was confirmed (by reading each one) to touch only
/// `GoRouterState`, never `context`, so a context that throws the moment
/// anything actually calls it is the right instrument: silence proves the
/// claim, and a throw here means a route was added that broke it.
class _UntouchedBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'A shared route\'s builder read BuildContext ($invocation) -- '
      'web_router_guard_test.dart\'s widget-type check assumed none of them '
      'do. That route needs a real widget-tree pump instead of this cheap '
      'probe, or the assumption in this file\'s doc comment needs updating.');
}

/// THE ENTIRE MITIGATION for having two routers in one app.
///
/// CLAUDE.md's core invariant is one route per screen ID, in one router.
/// `manaWebRouter` (lib/app/web_router.dart) is a deliberate exception to
/// that, built for Plan 3a's restricted web surface, and it was accepted
/// on one condition: the two routers cannot silently drift apart. This
/// test is that condition, not a decoration on it.
///
/// It fails four separate ways, and each one was verified to actually
/// fail before this file was considered done (see task-3-report.md for the
/// first three; task-3-fix-report.md for the fourth):
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
///   4. a path both routers register resolves to a DIFFERENT screen
///      widget on each — the drift the first three checks cannot see,
///      because they only ever compare path strings. See the widget-type
///      test below for its own limitation: it stands in a BuildContext
///      that throws on any use, which holds only because every shared
///      route's builder was read and confirmed to never touch context.
///
/// Extracting paths from the live GoRouter objects (via `.configuration
/// .routes`) rather than hand-copying the two literal lists into this
/// file, because a hand-copied list here is exactly the second router
/// this project keeps getting bitten by — a copy that can go stale
/// without anyone noticing.
void main() {
  /// RECURSIVE, and it has to be. This walked `configuration.routes` and
  /// took the top-level GoRoutes only. On 2026-09-18 the web router moved its
  /// twenty-one signed-in routes inside a ShellRoute -- to give every page
  /// the site's navigation -- and all twenty-one vanished from this guard's
  /// view at once. It failed loudly, which is the good outcome; had the shell
  /// been introduced with a route ALREADY missing from the allowlist, a
  /// non-recursive walk would have reported agreement between two routers it
  /// could no longer see.
  Iterable<GoRoute> allGoRoutes(Iterable<RouteBase> routes) sync* {
    for (final r in routes) {
      if (r is GoRoute) yield r;
      yield* allGoRoutes(r.routes);
    }
  }

  Set<String> pathsOf(GoRouter router) =>
      allGoRoutes(router.configuration.routes).map((r) => r.path).toSet();

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

  test('every shared path resolves to the same screen widget type on both routers', () {
    // The three checks above only ever compared PATH STRINGS. `/ow-013`
    // present on both sides passes them even if one router's builder for
    // it returns a different widget than the other's -- exactly the drift
    // that matters, since "the web router reuses screens, it does not
    // reimplement them" is the actual promise this file exists to keep.
    //
    // Every GoRoute is wrapped by `manaSelectable` (see router.dart), which
    // returns `SelectionArea(child: <the real screen widget>)` -- so the
    // comparison unwraps that one layer rather than comparing two
    // SelectionAreas, which would pass unconditionally.
    //
    // Constructing a widget from a route's `builder` needs a BuildContext
    // and a GoRouterState. A real BuildContext means pumping a full widget
    // tree per route -- for ~19 routes, several of them ConsumerWidgets
    // needing Riverpod/session/translation scaffolding the harness builds
    // for exactly one screen at a time, that is a much heavier test than
    // this guard has ever been. Reading every shared builder's source
    // (done as part of building this check) showed none of them touch
    // `context` -- only `GoRouterState.extra`/`.uri` and `ManaSession`,
    // both of which are equally satisfiable without a widget tree -- so an
    // untouched-BuildContext stand-in is enough, and it throws loudly (see
    // `_UntouchedBuildContext`) if a future route breaks that assumption
    // instead of silently mis-comparing.
    Type screenTypeOf(GoRouter router, GoRoute route) {
      final state = GoRouterState(
        router.configuration,
        uri: Uri.parse(route.path),
        matchedLocation: route.path,
        fullPath: route.path,
        pathParameters: const {},
        pageKey: ValueKey(route.path),
      );
      final built = route.builder!(_UntouchedBuildContext(), state);
      final unwrapped = built is SelectionArea ? built.child : built;
      return unwrapped.runtimeType;
    }

    GoRoute routeAt(GoRouter router, String path) =>
        allGoRoutes(router.configuration.routes)
            .firstWhere((r) => r.path == path && r.builder != null);

    final shared = webPaths.intersection(androidPaths); // /web-home excluded: web-only
    final mismatches = <String, String>{};
    for (final path in shared) {
      final androidType = screenTypeOf(manaRouter, routeAt(manaRouter, path));
      final webType = screenTypeOf(manaWebRouter, routeAt(manaWebRouter, path));
      if (androidType != webType) {
        mismatches[path] = '$androidType (android) vs $webType (web)';
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason: 'a shared path resolves to a DIFFERENT screen widget on web '
          'than on Android: $mismatches. manaWebRouter must reuse the same '
          'screen classes manaRouter builds, never a reimplementation.',
    );
  });
}

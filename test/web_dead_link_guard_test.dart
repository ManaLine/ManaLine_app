import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/app/web_router.dart';

/// A screen that runs on the web must not send somebody to a route the web
/// build does not carry.
///
/// THE BUG THIS EXISTS FOR, found on the live site by the Owner. OW-018 is in
/// [kManaWebAllowedRoutes], so it renders in a browser. Its Bulk Onboarding
/// button pushed `/ow-bulk-onboarding-web` — the handset signpost, which is
/// deliberately Android-only because telling somebody to visit the website
/// they are already on would be absurd.
///
/// So a web Owner pressing it landed on "This Screen Is in the App", being
/// offered the Android app, from inside the app's own website, one click away
/// from the wizard they wanted. Nothing failed: `flutter analyze` was clean,
/// every test passed, and the route-unavailable screen did exactly its job.
///
/// Neither existing router guard could see it. `web_router_guard_test` compares
/// route SETS between the two routers and says nothing about who navigates
/// where; `bulk_onboarding_moved_to_web_test` checks the opposite direction.
/// The missing check is this one: the LINKS out of a web-reachable screen.

/// Mapped to /web-home by web_router's own redirect: each of these means
/// "take me to my workspace's front page", and on the web that IS /web-home.
const _redirectedToWebHome = {'/ow-001', '/ag-001', '/cw-001', '/iw-001'};

/// Targets that really do not exist on the web, with why. Reaching one shows
/// the route-unavailable screen, which names the screen and offers a way back
/// — that is the designed behaviour for them, not a dead end.
///
/// Listed by name so the list cannot grow by accident. Adding an entry means
/// deciding that a web visitor pressing that button SHOULD be told the screen
/// lives in the app.
const _appOnlyOnPurpose = <String, String>{
  '/cw-003': 'one loan detail view; Plan 3a kept loans on the handset',
  '/cw-005': 'the customer payment screen; paying happens at the door',
  '/iw-004': 'one investment detail view, same reasoning as /cw-003',
  '/notifications': 'the inbox is a field tool; the web build has no bell',
  '/admin-login': 'the support console is not part of the customer website',
};

void main() {
  /// Source with comments stripped — several of these screens explain in prose
  /// which route they used to push, and a naive scan finds the path in the
  /// sentence saying it is no longer used.
  String code(File f) => f
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('no web-reachable screen pushes a route the web build lacks', () {
    // Which files ARE reachable on the web: the screen file behind each
    // allowlisted route. Matched by the screen-ID filename convention, which
    // is the routing contract — `/ow-018` lives in `ow_018_*.dart`.
    final screens = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final webIds = {
      for (final r in kManaWebAllowedRoutes) r.replaceFirst('/', '').replaceAll('-', '_')
    };

    final offenders = <String>[];
    for (final f in screens) {
      final name = f.uri.pathSegments.last;
      final isWebReachable = webIds.any((id) => name.startsWith(id));
      if (!isWebReachable) continue;

      final src = code(f);
      for (final m in RegExp(r"""(?:push|go)\(\s*'(/[a-z0-9\-]+)'""")
          .allMatches(src)) {
        final target = m.group(1)!;
        if (kManaWebAllowedRoutes.contains(target)) continue;
        // A push guarded by kIsWeb is the fix, not the fault — the screen has
        // already been taught that it runs on two builds.
        if (src.contains('kIsWeb')) continue;
        // Redirected centrally in web_router: these four mean "my workspace's
        // front page", which on the web IS /web-home.
        if (_redirectedToWebHome.contains(target)) continue;
        // GENUINELY ABSENT, and the route-unavailable screen is the right
        // answer for them rather than a bug. Listed by name with the reason,
        // so the list cannot grow by accident:
        if (_appOnlyOnPurpose.containsKey(target)) continue;
        offenders.add('$name -> $target');
      }
    }

    expect(offenders, isEmpty,
        reason: 'these screens render on the web and push a route the web '
            'router does not register, so the person lands on the '
            '"This Screen Is in the App" fallback: $offenders. Either add the '
            'route to the web build, or branch on kIsWeb and send web users '
            'somewhere that exists.');
  });

  test('and OW-018 in particular sends each build somewhere real', () {
    // The specific instance, pinned by name so the fix cannot be quietly
    // reverted into "one route for both" again.
    final src = code(
        File('lib/features/owner_workspace/screens/ow_018_business_migration.dart'));
    expect(src, contains('kIsWeb'));
    expect(src, contains("'/ow-bulk-onboarding-menu'"),
        reason: 'the web build has the menu');
    expect(src, contains("'/ow-bulk-onboarding-web'"),
        reason: 'the handset still gets the signpost');
  });
}

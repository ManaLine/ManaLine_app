import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/router.dart';
import '../features/login_registration/state/auth_flow_state.dart';

/// Makes the Android back button go back.
///
/// It did not. 91 of the app's navigations use `context.go()`, which REPLACES
/// the router's stack rather than pushing onto it -- so after moving from the
/// dashboard into Collection Mode there was nothing behind it, and the system
/// back button fell through to Android and closed the app. Someone three
/// screens into their work would press back once and lose the lot.
///
/// Converting all 91 to push() would be the deeper fix, but `go()` is correct
/// at many of them: switching workspace, landing after login, returning home.
/// The reliable rule is not "which call was used" but "is there anywhere to go
/// back to", and that can be answered here, once, for the whole app:
///
///   1. Something on the navigator stack -> pop it. Covers imperative pushes
///      (collection entry, business detail) and dialogs.
///   2. Otherwise, not on a workspace home -> go to the home for this role.
///   3. Already home -> leave, which is what back means there.
///
/// Step 2 is what `go()` took away and this gives back.
class ManaBackHandler extends StatelessWidget {
  final Widget child;
  const ManaBackHandler({super.key, required this.child});

  /// Where "home" is for the workspace this route belongs to.
  ///
  /// Keyed off the screen-ID prefix, which is the routing contract -- every
  /// route is /ow-*, /ag-*, /cw-*, /iw-* or /lr-*, so the workspace is
  /// readable from the path without a lookup table that could fall behind.
  static String? homeFor(String location) {
    if (location.startsWith('/ow-')) return '/ow-001';
    if (location.startsWith('/ag-')) return '/ag-001';
    if (location.startsWith('/cw-')) return '/cw-001';
    if (location.startsWith('/iw-')) return '/iw-001';
    // Login and registration are a flow, not a workspace. Back inside it must
    // not jump to a dashboard the person has not signed into yet.
    return null;
  }

  /// True when this is a place where Back should exit the app rather than
  /// navigate. Both the workspace homes and the first login screen qualify:
  /// there is nothing behind either of them.
  static bool isExitPoint(String location) =>
      location == '/lr-001' || location == homeFor(location);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Always intercept, then decide. Handing the decision to Navigator
      // first would let it exit the app before rule 2 ever runs.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        final nav = manaRootNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          return;
        }

        final location =
            manaRouter.routerDelegate.currentConfiguration.uri.path;
        final home = homeFor(location);

        if (home != null && location != home) {
          // businessId is what every workspace home needs to render anything,
          // and it is the one thing `go()` calls pass around by hand. Taken
          // from the session rather than the route, because the route being
          // left may not carry it.
          manaRouter.go(home, extra: ManaSession.instance.lastBusinessId);
          return;
        }

        // Nothing behind this screen. Let the press mean what it means.
        SystemNavigator.pop();
      },
      child: child,
    );
  }
}

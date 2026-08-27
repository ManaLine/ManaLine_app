import 'package:flutter/material.dart';

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
///
/// WHY THIS IS A DISPATCHER AND NOT A PopScope. It was a PopScope, placed in
/// MaterialApp.router's builder, and it never ran once. PopScope registers
/// itself with the enclosing ModalRoute; the app builder sits ABOVE the
/// Navigator, so there is no route to register with, and the widget silently
/// did nothing while the back press went to the router, found an empty stack,
/// and closed the app.
///
/// That is the same mistake as the SelectionArea one, whose warning is three
/// lines above where this used to be wired in main.dart: things that need to
/// be inside the Navigator cannot be installed above it. A back press arrives
/// at the Router's BackButtonDispatcher, so the decision belongs there.
class ManaBackHandler {
  const ManaBackHandler._();

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

  /// The decision itself, separated from where it is installed so it can be
  /// tested without a live router. Returns true when it handled the press.
  static bool handleBack({
    required bool canPop,
    required VoidCallback pop,
    required String location,
    required void Function(String home) goHome,
  }) {
    if (canPop) {
      pop();
      return true;
    }
    final home = homeFor(location);
    if (home != null && location != home) {
      goHome(home);
      return true;
    }
    return false;
  }
}

/// Installed as the Router's backButtonDispatcher, which is where an Android
/// back press actually arrives.
class ManaBackButtonDispatcher extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() async {
    final nav = manaRootNavigatorKey.currentState;
    return ManaBackHandler.handleBack(
      canPop: nav?.canPop() ?? false,
      pop: () => nav!.pop(),
      location: manaRouter.routerDelegate.currentConfiguration.uri.path,
      goHome: (home) =>
          manaRouter.go(home, extra: ManaSession.instance.lastBusinessId),
    );
    // false falls through to Flutter, which exits the app -- what back means
    // on a workspace home.
  }
}

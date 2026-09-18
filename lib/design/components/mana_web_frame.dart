import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';

/// Gives every web page a measure, so a screen drawn for a 360dp phone is
/// legible in a desktop browser without being laid out again.
///
/// TWO THINGS ABOUT THIS WIDGET WERE WRONG, and both were found on the same
/// afternoon by deploying it and looking at the page.
///
/// ONE: THE ROUTE CHECK NEVER WORKED. `main.dart` hands [currentLocation] the
/// expression `router.routerDelegate.currentConfiguration.uri.path`, and this
/// widget lives in `MaterialApp.builder` -- ABOVE the Navigator, where that
/// configuration has not been parsed yet. It returns the empty string, and
/// the builder is not re-run on navigation, so it stays empty. Every route
/// therefore matched nothing in the opt-out list, including `/ow-013`, which
/// had been believed responsive on the web since Plan 2a and has been
/// rendering as a 480px phone column the whole time.
///
/// `mana_web_frame_test.dart` passed throughout, because it injects
/// [currentLocation] as a literal string -- it proves this widget's logic and
/// says nothing about the wiring. `web_frame_real_router_test.dart` now
/// drives it from a real GoRouter, wired exactly as `main.dart` wires it, and
/// fails if the string goes empty again.
///
/// The fix is [routeListenable]: `GoRouter.routeInformationProvider` IS a
/// ValueListenable<RouteInformation> that is populated and that notifies, so
/// a ValueListenableBuilder around it both gets the right answer and rebuilds
/// when it changes.
///
/// TWO: THE DEFAULT WAS BACKWARDS. Clamping everything to 480px and letting
/// screens out one at a time was right when the web build was a courtesy;
/// three routes escaped in the project's life, and the Owner's verdict on
/// seeing it live was "it looks like a mobile device screen". The default is
/// inverted now: a web page gets [kManaWebReadingMeasure], which is wide
/// enough to read as a page and narrow enough that a button drawn full-width
/// for a phone does not become a 1,400px band. [kManaWideRoutes] keeps its
/// meaning but changes direction -- it now names the screens that have a
/// BESPOKE wide layout and want the full [kManaDeskContentMax], rather than
/// the only ones allowed out of a cell.
///
/// [isWeb] defaults to the real `kIsWeb`. This is the property the widget is
/// FOR: width alone is an assumption about today's device fleet, not a
/// mechanism, and an unfolded foldable can exceed it. Gating on [isWeb] is
/// what makes "cannot change the Android build" true by construction.
class ManaWebFrame extends StatelessWidget {
  final Widget child;
  final String Function() currentLocation;
  final bool Function() isWeb;

  /// Notifies when the route changes, and unlike `currentConfiguration` it
  /// is populated above the Navigator. `main.dart` passes
  /// `router.routeInformationProvider`.
  ///
  /// Nullable so the widget still works with [currentLocation] alone, which
  /// is how the unit tests drive it.
  final ValueListenable<RouteInformation>? routeListenable;

  const ManaWebFrame({
    super.key,
    required this.child,
    required this.currentLocation,
    this.routeListenable,
    this.isWeb = _realIsWeb,
  });

  /// Default for [isWeb]: the actual platform. A static tear-off rather than
  /// `() => kIsWeb` inline because a default parameter value must be a
  /// compile-time constant.
  static bool _realIsWeb() => kIsWeb;

  @override
  Widget build(BuildContext context) {
    final listenable = routeListenable;
    if (listenable == null) return _framed(context, currentLocation());
    return ValueListenableBuilder<RouteInformation>(
      valueListenable: listenable,
      builder: (context, info, _) {
        // The provider's uri is the whole location; the list holds paths.
        final path = info.uri.path.isEmpty ? currentLocation() : info.uri.path;
        return _framed(context, path);
      },
    );
  }

  Widget _framed(BuildContext context, String location) {
    final width = MediaQuery.sizeOf(context).width;
    // A phone browser is already the width every screen was drawn for.
    if (!isWeb() || width < ManaBreakpoints.compact) return child;

    // SIGNED-IN PAGES ARE NOT THIS WIDGET'S JOB ANY MORE. web_router wraps
    // all twenty-one of them in a ShellRoute that puts the site navigation
    // against the window's edge and measures the content beside it. Clamping
    // here as well would measure the RAIL too, leaving the whole assembly
    // floating in the middle of a wide monitor -- which is the exact
    // complaint that started this work.
    //
    // A PREFIX, NOT A LIST. The signed-out screens are `/lr-*` by the screen
    // ID contract, so there is no second copy of the router's route set here
    // to drift out of step with it.
    if (!location.startsWith('/lr-')) return child;

    return ColoredBox(
      color: ManaColors.surfaceMuted,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kManaWebReadingMeasure),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';

/// Renders the app as a centred, phone-width column when the window is wider
/// than a phone.
///
/// WHY A CLAMP AND NOT A RESPONSIVE PASS: the app is ~85 screens, all built
/// and tested against a 360x640 surface. Dropped into a 1440px window a
/// full-width Column stretches its buttons to 1400px and its cards into
/// unreadable bands. Laying all of them out again would re-open the overflow
/// bug class that has shipped four times here. Clamping makes every screen
/// legible on day one, from ONE edit, with no per-screen step to forget.
///
/// The route check is how a screen escapes: once a workflow has actually been
/// laid out for a wide window, its path goes in [kManaWideRoutes] and this
/// widget stops constraining it. Opt-in, so an unconverted screen cannot
/// accidentally be let out.
///
/// [currentLocation] is injected rather than read from the global router
/// because this widget sits ABOVE the Navigator, where `GoRouterState.of`
/// does not resolve — and because a callback is what makes it testable
/// without standing up a router.
///
/// [isWeb] defaults to the real `kIsWeb` and exists for the same reason
/// [currentLocation] is a callback rather than a global read: so a test can
/// supply a value without needing a web test target. This is also the
/// property this widget is FOR — width alone is an assumption about today's
/// device fleet (every targeted Android handset sits under
/// [ManaBreakpoints.compact]), not a mechanism, and an Android tablet or an
/// unfolded foldable in portrait can exceed it. Gating on [isWeb] too is what
/// makes "the clamp cannot change the Android build" true by construction.
class ManaWebFrame extends StatelessWidget {
  final Widget child;
  final String Function() currentLocation;
  final bool Function() isWeb;

  const ManaWebFrame({
    super.key,
    required this.child,
    required this.currentLocation,
    this.isWeb = _realIsWeb,
  });

  /// Default for [isWeb]: the actual platform. A static tear-off rather than
  /// `() => kIsWeb` inline because a default parameter value must be a
  /// compile-time constant.
  static bool _realIsWeb() => kIsWeb;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (!isWeb() ||
        width < ManaBreakpoints.compact ||
        kManaWideRoutes.contains(currentLocation())) {
      return child;
    }

    return ColoredBox(
      color: ManaColors.surfaceMuted,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ManaBreakpoints.columnMax),
          child: child,
        ),
      ),
    );
  }
}

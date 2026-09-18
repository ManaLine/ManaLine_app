import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mana_adaptive_shell.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/tokens/breakpoints.dart';
import '../../../shared/translation_service.dart';
import '../state/web_destinations.dart';

/// The site's navigation, wrapped around every signed-in web page.
///
/// WHAT IT REPLACES: nothing, which was the problem. The rail existed on
/// `/web-home` and nowhere else, so 20 of the 21 signed-in web routes were a
/// column of content with no way out of it but the browser's Back button.
/// That is the single largest difference between what this build was and a
/// website.
///
/// APPLIED AT THE ROUTER, not inside each screen, for two reasons. It is one
/// edit rather than twenty, so no screen can be forgotten — and more
/// importantly the router is the only place that reliably KNOWS the current
/// route. `ManaWebFrame` tried to read it from `MaterialApp.builder` and got
/// the empty string for months (see that widget's note); a GoRoute's builder
/// cannot have that problem, because the path is what selected it.
///
/// SIGNED-OUT ROUTES DO NOT GET THIS. Login, registration, OTP and PIN have
/// nothing to navigate to — every destination in the rail needs a session —
/// and a rail full of links that bounce you back to the login you are already
/// looking at is worse than no rail.
///
/// NESTED SCAFFOLDS ARE INTENDED HERE. Most screens are a Scaffold with their
/// own ManaAppBar, and that bar is the PAGE's title; this shell's Scaffold
/// carries the rail beside it. Rail on the left, page with its own heading to
/// the right, is the ordinary shape of a web application and is what the
/// nesting produces.
class ManaWebShell extends ConsumerWidget {
  final Widget child;

  /// The route this shell is wrapping, so the rail can show where you are.
  /// Passed in by the router, which is the thing that knows.
  final String location;

  const ManaWebShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);

    // Below the web treatment's own threshold there is no room beside the
    // content for a rail, and the page is already the width it was drawn
    // for. Kept identical to ManaWebFrame's gate on purpose: a page either
    // gets the web treatment or it does not, rather than getting the measure
    // at one width and the navigation at another.
    if (MediaQuery.sizeOf(context).width < ManaBreakpoints.compact) {
      return child;
    }

    final destinations = manaWebDestinations(manaWebRole(ref), ref);
    final selected = manaWebSelectedIndex(destinations, location);

    final items = [
      ManaNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: ref.t('home'),
        onTap: () => context.go('/web-home'),
      ),
      for (final d in destinations)
        ManaNavItem(
          icon: d.icon,
          selectedIcon: d.icon,
          label: d.title,
          onTap: () {
            final route = d.route;
            if (route != null) {
              context.go(route);
            } else {
              d.onTap?.call();
            }
          },
        ),
    ];

    return ManaAdaptiveShell(
      items: items,
      // Home leads, so a destination's index in the rail is one past its
      // index in the list. -1 from manaWebSelectedIndex means "not a
      // destination", which lands on 0 — Home — and that is the honest
      // answer for a page the rail cannot name.
      currentIndex: location == '/web-home' ? 0 : selected + 1,
      // The rail from 600 rather than 1024. ManaAdaptiveShell's own default
      // protects the tablet case for the ANDROID build, where the alternative
      // is a bottom bar that already exists. On the web the alternative is no
      // navigation at all, and a 768px browser window is a desk.
      railFrom: ManaBreakpoints.compact,
      // A screen with a bespoke wide layout gets the desk measure; the rest
      // get the reading measure, for the same reason ManaWebFrame gives it
      // to them -- they are single columns of full-width rows drawn against
      // 360dp, and 1,200px-wide buttons are not an improvement on 480.
      contentMax: kManaWideRoutes.contains(location)
          ? kManaDeskContentMax
          : kManaWebReadingMeasure,
      child: child,
    );
  }
}

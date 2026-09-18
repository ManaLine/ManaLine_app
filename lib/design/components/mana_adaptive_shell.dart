import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_header.dart';
import 'mana_text.dart';

/// Wraps a screen's body with navigation that changes SHAPE, not CONTENT,
/// with viewport width.
///
/// Below [ManaWidthClass.expanded] this renders exactly what every screen
/// already renders: a [Scaffold] with [ManaBottomNav] docked at the bottom.
/// At [ManaWidthClass.expanded] the bottom bar is replaced by a
/// [NavigationRail] beside the content instead.
///
/// WHY ONLY AT `expanded`, NOT AT `medium` (the 820px tablet case): a rail is
/// a permanent horizontal strip. At 1024+ there is width to spare beside the
/// content it sits next to; at 820 a rail would eat into the same space the
/// wide layout exists to give back to the ledger table and two-column
/// content — the exact tablet case [ManaBreakpoints.medium] is documented to
/// protect. So the tablet keeps the bottom nav it already has, and only a
/// desk-width window gets the rail.
///
/// WHY THE RAIL IS BUILT FROM THE SAME `items` LIST RATHER THAN A SEPARATE
/// rail-items PARAMETER: this project's worst regressions have been exactly
/// this shape — one navigation model expressed twice (a shared window used
/// by two call sites, a photo column read by sixteen) where only some
/// consumers were updated and the rest silently drifted. A rail and a bottom
/// bar are two renderings of one list of destinations; adding a second list
/// would reintroduce the two-navigation-contracts problem this widget exists
/// to avoid, with no test able to catch a rail that goes stale.
class ManaAdaptiveShell extends StatelessWidget {
  final List<ManaNavItem> items;
  final int currentIndex;
  final Widget child;
  final PreferredSizeWidget? appBar;

  const ManaAdaptiveShell({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.child,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isExpanded = ManaBreakpoints.of(width) == ManaWidthClass.expanded;

    if (!isExpanded) {
      return Scaffold(
        appBar: appBar,
        body: child,
        bottomNavigationBar: ManaBottomNav(items: items, currentIndex: currentIndex),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          // A CAP, because NavigationRail has none. `minWidth` is a floor;
          // with labelType.all the rail then grows to fit its WIDEST label,
          // and "Also Available On Mobile" pushed it to 408px at 1440 -- a
          // quarter of the window spent on navigation, and enough to squeeze
          // the card grid from three columns down to two. A rail is a strip,
          // not a sidebar. Long labels wrap inside it instead.
          SizedBox(
            width: 168,
            child: NavigationRail(
              selectedIndex: currentIndex,
              labelType: NavigationRailLabelType.all,
              backgroundColor: ManaColors.surface,
              indicatorColor: ManaColors.brandFaint,
              useIndicator: true,
              minWidth: 72,
              groupAlignment: -1,
              // THE MARK AT THE HEAD OF THE RAIL. Logo top-left above the
              // navigation is what nearly every web application does, and its
              // absence is a good part of why this page read as an app window
              // rather than a site. It is chrome -- the same category as the
              // rail itself -- so it does not cross the "shape, not content"
              // line this widget's doc draws above.
              //
              // Only here, in the expanded branch: a phone already shows the
              // brand in its launcher and its app bar, and a bottom nav has
              // nowhere to put it.
              leading: const _RailBrand(),
              selectedIconTheme: IconThemeData(color: ManaColors.brandDeep),
              unselectedIconTheme: IconThemeData(color: ManaColors.textSecondary),
              selectedLabelTextStyle:
                  TextStyle(color: ManaColors.brandDeep, fontWeight: FontWeight.w700),
              unselectedLabelTextStyle: TextStyle(color: ManaColors.textSecondary),
              // Re-navigating to the current destination pushes a duplicate
              // route and breaks Back — same rule ManaBottomNav's `_NavButton`
              // follows, kept here so both renderings behave identically.
              onDestinationSelected: (i) {
                if (i != currentIndex) items[i].onTap();
              },
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: ManaText(item.label),
                  ),
              ],
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: ManaColors.divider),
          // A MEASURE, not the whole window. Letting a screen out of the
          // 480px phone column is not the same as giving it 2560px: a card
          // grid run edge to edge loses the eye between rows. Aligned to the
          // top-left rather than centred, so the content sits against the
          // rail the way a page sits against its own navigation.
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kManaDeskContentMax),
                // SizedBox.expand, because Align hands its child LOOSE
                // constraints in both axes -- so without this the body
                // shrink-wraps to the height of its content. That is
                // invisible until something wants the full page: the logo
                // backdrop anchored bottom-right ended up floating halfway
                // up, against the bottom of the cards rather than the bottom
                // of the page.
                child: SizedBox.expand(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The MANA LINE mark, at the head of the desk-width navigation rail.
///
/// The wordmark is deliberately NOT drawn beside it. The rail is 72dp at its
/// narrowest and the logo already carries the words "MANA" and "LINE" inside
/// the circle -- setting them again next to it would say the same thing twice
/// in a strip that has no room for it.
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(
          top: ManaSpacing.lg,
          bottom: ManaSpacing.md,
        ),
        child: SizedBox(
          height: 44,
          width: 44,
          child: Image(
            image: AssetImage('assets/images/logo.png'),
            fit: BoxFit.contain,
            // The mark is a 1024px circle; without this it is resampled on
            // every frame at 44px.
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
}

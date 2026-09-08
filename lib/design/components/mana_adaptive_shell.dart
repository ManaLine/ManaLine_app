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
          NavigationRail(
            selectedIndex: currentIndex,
            labelType: NavigationRailLabelType.all,
            backgroundColor: ManaColors.surface,
            indicatorColor: ManaColors.brandFaint,
            useIndicator: true,
            minWidth: 72,
            groupAlignment: -1,
            leading: const SizedBox(height: ManaSpacing.lg),
            selectedIconTheme: IconThemeData(color: ManaColors.brandDeep),
            unselectedIconTheme: IconThemeData(color: ManaColors.textSecondary),
            selectedLabelTextStyle: TextStyle(color: ManaColors.brandDeep, fontWeight: FontWeight.w700),
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
          VerticalDivider(width: 1, thickness: 1, color: ManaColors.divider),
          Expanded(child: child),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/mana_header.dart';
import '../translation_service.dart';

/// The Owner's four destinations, wherever they are standing.
///
/// It lived inside OW-001 as a private widget with currentIndex hardcoded to
/// zero, which was fine while the dashboard was the only screen with a nav
/// bar. Collection Mode needs the same four -- an Agent who has finished a
/// round should be able to leave it without pressing back -- and a second
/// copy of a navigation contract is how two screens end up disagreeing about
/// where "Customers" goes.
class ManaOwnerFooterNav extends ConsumerWidget {
  final String businessId;

  /// Which of the four this screen IS. The bar refuses to re-navigate to the
  /// current tab: doing so pushed a duplicate route and broke Back.
  final int currentIndex;

  const ManaOwnerFooterNav({
    super.key,
    required this.businessId,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(String route) => context.go(route, extra: businessId);

    return ManaBottomNav(
      currentIndex: currentIndex,
      items: [
        ManaNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: ref.t('home'),
          onTap: () => go('/ow-001'),
        ),
        ManaNavItem(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: ref.t('customers'),
          onTap: () => go('/ow-004'),
        ),
        ManaNavItem(
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          label: ref.t('collections'),
          onTap: () => go('/ow-006'),
        ),
        ManaNavItem(
          icon: Icons.history,
          selectedIcon: Icons.history_toggle_off,
          label: ref.t('history'),
          onTap: () => go('/ow-017'),
        ),
      ],
    );
  }
}

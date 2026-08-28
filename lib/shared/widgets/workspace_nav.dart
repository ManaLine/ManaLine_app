import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/mana_header.dart';
import '../translation_service.dart';

/// Which workspace's four destinations these are.
enum ManaWorkspace { owner, agent }

/// The four destinations, in one order, for whoever is standing there.
///
/// There were two of these. The Owner's lived here as ManaOwnerFooterNav and
/// used GoRouter; the Agent's was a private `_AgentFooterNav` inside AG-001
/// built from a raw NavigationBar that pushed each destination with
/// `Navigator.push`. Two copies of a navigation contract is how two screens
/// end up disagreeing about where "Customers" goes -- and they did: the Owner
/// read Home, Customers, Collections, History and the Agent read the same four
/// in the same order, while the Owner's tabs replaced the stack and the
/// Agent's stacked on top of it.
///
/// That second difference was a bug, not a style choice. AG-002's back button
/// calls `context.go('/ag-001')`, which rewrites the ROUTER's stack -- but a
/// page pushed with Navigator.push sits ABOVE the router's pages, so the
/// screen underneath changed and the pushed page stayed exactly where it was.
/// Back appeared dead. Every tab goes through the router now, so back means
/// the same thing in both workspaces.
///
/// The order is Home, Collections, Customers, History in both. Collections
/// comes second because it is the thing the day is spent in.
class ManaWorkspaceNav extends ConsumerWidget {
  final ManaWorkspace workspace;
  final String businessId;

  /// Which of the four this screen IS. The bar refuses to re-navigate to the
  /// current tab: doing so pushed a duplicate route and broke Back.
  final int currentIndex;

  const ManaWorkspaceNav({
    super.key,
    required this.workspace,
    required this.businessId,
    required this.currentIndex,
  });

  /// Home, Collections, Customers, History — by screen ID, per workspace.
  ///
  /// A screen ID is the routing contract, so the two rows below ARE the
  /// difference between the workspaces. Nothing else here branches on role.
  List<String> get _routes => switch (workspace) {
        ManaWorkspace.owner => const ['/ow-001', '/ow-006', '/ow-004', '/ow-017'],
        ManaWorkspace.agent => const ['/ag-001', '/ag-002', '/ag-004', '/ag-010'],
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(int i) => context.go(_routes[i], extra: businessId);

    return ManaBottomNav(
      currentIndex: currentIndex,
      items: [
        ManaNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: ref.t('home'),
          onTap: () => go(0),
        ),
        ManaNavItem(
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          label: ref.t('collections'),
          onTap: () => go(1),
        ),
        ManaNavItem(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: ref.t('customers'),
          onTap: () => go(2),
        ),
        ManaNavItem(
          icon: Icons.history,
          selectedIcon: Icons.history_toggle_off,
          label: ref.t('history'),
          onTap: () => go(3),
        ),
      ],
    );
  }
}

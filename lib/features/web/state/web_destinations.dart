import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/mana_share_app.dart';
import '../../../shared/translation_service.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// Where a signed-in person can go on the web, by role.
///
/// LIFTED OUT OF web_home_screen.dart on 2026-09-18, when the navigation rail
/// stopped being that one screen's furniture and became the site's. The cards
/// on the home page and the rail on every page are two renderings of ONE
/// list — which is the same rule [ManaAdaptiveShell] already states for the
/// rail and the bottom bar, for the same reason. A second, separately
/// maintained nav list is the exact shape this project's worst regressions
/// have taken: a shared contract with two copies, one of which gets updated.
///
/// WHY THE WEB SET IS SHORTER THAN THE APP'S. Plan 3a removed the four
/// workspace dashboards from the web build — collections, loans, day closure
/// and reports all happen on the handset — so this is not a subset waiting to
/// be completed. It is the whole of what the desk half does.
class ManaWebDestination {
  final IconData icon;
  final String title;

  /// Longer explanation, set only where a label is not enough. Today that is
  /// the "get the app" card alone, which has to say what it is FOR.
  final String? body;

  /// Where it goes, or null for a destination that does something instead of
  /// going somewhere — see [onTap].
  final String? route;

  /// What to do when [route] is null.
  final VoidCallback? onTap;

  /// Drawn as the leading, emphasised card. At most one.
  final bool isPrimary;

  const ManaWebDestination({
    required this.icon,
    required this.title,
    this.body,
    this.route,
    this.onTap,
    this.isPrimary = false,
  });
}

/// Which role this person is browsing as.
///
/// `authFlowProvider.selectedRole` is authoritative when it exists — it is the
/// role LR-013 actually put them into this session. It is lost on a browser
/// refresh (in-memory Riverpod state, not persisted), which is exactly the
/// case router.dart's `_resolveBusinessId` already handles for businessId:
/// fall back to what ManaSession remembers. The fallback uses the same
/// most-specific-first precedence as the existing profile-route resolver in
/// auth_flow_state.dart (agent, then customer, then investor, else owner)
/// rather than inventing a second ordering for the same question.
String manaWebRole(WidgetRef ref) {
  final selected = ref.watch(authFlowProvider.select((s) => s.selectedRole));
  if (selected != null) return selected;
  final session = ManaSession.instance;
  if (session.lastAgentId != null) return 'Agent';
  if (session.lastCustomerId != null) return 'Customer';
  if (session.lastInvestorId != null) return 'Investor';
  return 'Owner';
}

/// The destinations for [role], in the order they are shown.
List<ManaWebDestination> manaWebDestinations(String role, WidgetRef ref) {
  ManaWebDestination appCard({required bool primary}) => ManaWebDestination(
        icon: Icons.phone_android_outlined,
        title: ref.t(primary
            ? 'web_home_agent_app_title'
            : 'web_home_secondary_app_title'),
        body: ref.t(
            primary ? 'web_home_agent_app_body' : 'web_home_secondary_app_body'),
        isPrimary: primary,
        onTap: shareManaLineApp,
      );

  ManaWebDestination profile(String route) => ManaWebDestination(
        icon: Icons.person_outline,
        title: ref.t('profile'),
        route: route,
      );

  final settings = ManaWebDestination(
    icon: Icons.settings_outlined,
    title: ref.t('settings'),
    route: '/settings',
  );

  switch (role) {
    case 'Agent':
      // The one role with genuinely nothing to link to on the web — an
      // Agent's whole job is field work. The app card leads, styled primary,
      // because it IS the answer here, not a fallback.
      return [appCard(primary: true), profile('/ag-009'), settings];
    case 'Customer':
      return [
        ManaWebDestination(
            icon: Icons.account_balance_wallet_outlined,
            title: ref.t('my_loans'),
            route: '/cw-004'),
        profile('/cw-006'),
        settings,
        appCard(primary: false),
      ];
    case 'Investor':
      return [
        ManaWebDestination(
            icon: Icons.pie_chart_outline,
            title: ref.t('my_investments'),
            route: '/iw-003'),
        profile('/iw-005'),
        settings,
        appCard(primary: false),
      ];
    case 'Owner':
    default:
      return [
        ManaWebDestination(
            icon: Icons.fact_check_outlined,
            title: ref.t('account_review'),
            route: '/ow-013'),
        ManaWebDestination(
            icon: Icons.move_to_inbox_outlined,
            title: ref.t('pre_existing_business'),
            route: '/ow-018'),
        // Its own destination since 2026-09-18. The handset no longer runs
        // the wizard — it shows a signpost pointing here — so this is the
        // only place it exists, and the signpost tells an Owner to "choose
        // Bulk Onboarding from the menu". It leads to the MENU rather than
        // the wizard: page 1 of the wizard asks what the book contains,
        // which answers a different question from "what do I do here".
        ManaWebDestination(
            icon: Icons.table_chart_outlined,
            title: ref.t('bulk_onboarding'),
            route: '/ow-bulk-onboarding-menu'),
        ManaWebDestination(
            icon: Icons.workspace_premium_outlined,
            title: ref.t('subscription'),
            route: '/subscription'),
        profile('/ow-016'),
        settings,
        appCard(primary: false),
      ];
  }
}

/// Which destination the rail should show as selected for [location].
///
/// Returns -1 when the current page is not itself a destination — a settings
/// sub-page, the bulk onboarding wizard reached FROM the menu, the account
/// review of one particular account. Highlighting the nearest ancestor there
/// would say "you are on Settings" while looking at a screen Settings only
/// led to, and a rail that lies about where you are is worse than one that
/// admits it does not know.
int manaWebSelectedIndex(List<ManaWebDestination> items, String location) {
  for (var i = 0; i < items.length; i++) {
    if (items[i].route != null && items[i].route == location) return i;
  }
  return -1;
}

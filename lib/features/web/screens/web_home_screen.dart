import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mana_adaptive_shell.dart';
import '../../../design/components/mana_form_grid.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/mana_share_app.dart';

/// The web home — first thing a signed-in person sees on the site, and
/// nowhere else. Plan 3a removed the four workspace dashboards from the
/// web build (collections, loans, day closure, reports all happen on the
/// handset), which leaves this as the one screen that has to answer "I'm
/// signed in, now what" without becoming a smaller copy of what was cut.
///
/// So: destinations and words only, gated by role, never a figure — see
/// [_Destination] and the "no digits" test this screen is pinned by.
///
/// ALSO: the first production consumer of [ManaAdaptiveShell]. Every other
/// screen still renders its own bottom nav or drawer; this one exists
/// entirely on the web, so it is the natural place for the rail-at-desk-
/// width shell to prove itself before anything else adopts it.
class ManaWebHomeScreen extends ConsumerWidget {
  const ManaWebHomeScreen({super.key});

  /// Which role this landing page is for.
  ///
  /// `authFlowProvider.selectedRole` is authoritative when it exists — it is
  /// the role LR-013 actually put the person into this session. It is lost
  /// on a browser refresh (in-memory Riverpod state, not persisted), which
  /// is exactly the case router.dart's `_resolveBusinessId` already handles
  /// for businessId: fall back to whatever ManaSession remembers. The
  /// fallback here uses the same most-specific-first precedence as the
  /// existing profile-route resolver in auth_flow_state.dart (agent, then
  /// customer, then investor, else owner) rather than inventing a second
  /// ordering for the same question. Deliberately not a call to that
  /// resolver itself — it answers "which profile screen", this answers
  /// "which role" — so it is not counted as a consumer in
  /// consumer_census_test.dart.
  String _resolveRole(WidgetRef ref) {
    final selected = ref.watch(authFlowProvider.select((s) => s.selectedRole));
    if (selected != null) return selected;
    final session = ManaSession.instance;
    if (session.lastAgentId != null) return 'Agent';
    if (session.lastCustomerId != null) return 'Customer';
    if (session.lastInvestorId != null) return 'Investor';
    return 'Owner';
  }

  List<_Destination> _destinationsFor(String role, BuildContext context, WidgetRef ref) {
    void go(String route) => context.push(route);

    _Destination appCard({required bool primary}) => _Destination(
          icon: Icons.phone_android_outlined,
          title: ref.t(primary ? 'web_home_agent_app_title' : 'web_home_secondary_app_title'),
          body: ref.t(primary ? 'web_home_agent_app_body' : 'web_home_secondary_app_body'),
          isPrimary: primary,
          onTap: shareManaLineApp,
        );

    _Destination profile(String route) => _Destination(
          icon: Icons.person_outline,
          title: ref.t('profile'),
          onTap: () => go(route),
        );
    final settings = _Destination(
      icon: Icons.settings_outlined,
      title: ref.t('settings'),
      onTap: () => go('/settings'),
    );

    switch (role) {
      case 'Agent':
        // The one case with genuinely nothing to link to on the web — an
        // Agent's whole job is field work. The app card leads, styled
        // primary, because it IS the answer here, not a fallback.
        return [
          appCard(primary: true),
          profile('/ag-009'),
          settings,
        ];
      case 'Customer':
        return [
          _Destination(icon: Icons.account_balance_wallet_outlined, title: ref.t('my_loans'), onTap: () => go('/cw-004')),
          profile('/cw-006'),
          settings,
          appCard(primary: false),
        ];
      case 'Investor':
        return [
          _Destination(icon: Icons.pie_chart_outline, title: ref.t('my_investments'), onTap: () => go('/iw-003')),
          profile('/iw-005'),
          settings,
          appCard(primary: false),
        ];
      case 'Owner':
      default:
        return [
          _Destination(icon: Icons.fact_check_outlined, title: ref.t('account_review'), onTap: () => go('/ow-013')),
          _Destination(icon: Icons.move_to_inbox_outlined, title: ref.t('pre_existing_business'), onTap: () => go('/ow-018')),
          // ITS OWN CARD ON THE MENU, from 2026-09-18. The handset no longer
          // runs the wizard -- it shows a signpost here instead -- so this is
          // the only place it exists, and an Owner arriving from that signpost
          // is looking for these words. Reaching it only through OW-018 would
          // mean the instruction "choose Bulk Onboarding from the menu" was
          // not true of the menu they land on.
          _Destination(icon: Icons.table_chart_outlined, title: ref.t('bulk_onboarding'), onTap: () => go('/ow-bulk-onboarding')),
          _Destination(icon: Icons.workspace_premium_outlined, title: ref.t('subscription'), onTap: () => go('/subscription')),
          profile('/ow-016'),
          settings,
          appCard(primary: false),
        ];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);
    final role = _resolveRole(ref);
    final destinations = _destinationsFor(role, context, ref);

    // One shared list feeds both the body grid and the shell's nav —
    // ManaAdaptiveShell's own doc comment is explicit about why a second,
    // separately-maintained nav list is exactly the shape that drifts.
    // "Home" leads and is already selected; its onTap is never invoked
    // because ManaBottomNav/NavigationRail both guard re-navigation to the
    // current index.
    final navItems = [
      ManaNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: ref.t('home'),
        onTap: () {},
      ),
      for (final d in destinations)
        ManaNavItem(icon: d.icon, selectedIcon: d.icon, label: d.title, onTap: d.onTap),
    ];

    return ManaAdaptiveShell(
      items: navItems,
      currentIndex: 0,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('welcome_back'), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: ManaSpacing.xl),
              ManaFormGrid(
                columnsAtMedium: 2,
                columnsAtExpanded: 3,
                children: [for (final d in destinations) _DestinationCard(d)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable destination on this screen. Title-only for a plain link;
/// [body] is set only for the "get the app" card, which is the one
/// destination that needs a sentence of explanation rather than a label.
class _Destination {
  final IconData icon;
  final String title;
  final String? body;
  final bool isPrimary;
  final VoidCallback onTap;

  const _Destination({
    required this.icon,
    required this.title,
    this.body,
    this.isPrimary = false,
    required this.onTap,
  });
}

class _DestinationCard extends StatelessWidget {
  final _Destination destination;
  const _DestinationCard(this.destination);

  @override
  Widget build(BuildContext context) {
    final d = destination;
    final borderColor = d.isPrimary ? ManaColors.brand : ManaColors.divider;
    return Material(
      color: d.isPrimary ? ManaColors.brandFaint : ManaColors.surface,
      borderRadius: BorderRadius.circular(ManaRadius.md),
      child: InkWell(
        onTap: d.onTap,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: kManaMinTapTarget),
          padding: const EdgeInsets.all(ManaSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ManaRadius.md),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.icon, color: d.isPrimary ? ManaColors.brandDeep : ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.sm),
              // .raw, not title-cased: d.title is already a translated string
              // straight from ui_translations (same reasoning as ManaAppBar's
              // own title, which is .raw for the same reason) — re-casing it
              // in code would mangle "Pre-Existing Business" into
              // "Pre-existing Business" the moment ManaText's algorithm hits
              // the hyphen.
              ManaText.raw(
                d.title,
                style: d.isPrimary ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.titleMedium,
              ),
              if (d.body != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(d.body!, style: ManaType.note),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

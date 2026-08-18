import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../shared/notification_bell.dart';
import '../../../shared/person_identity.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/investor_dashboard_state.dart';
import '../../../shared/translation_service.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// IW-001 — Investor Home Dashboard. Primary entry point for an
/// Investor, reached from LR-013 Role Selector (Investor role chosen).
/// Read-only aggregation screen; every write happens on the destination
/// screens its Quick Actions link to. Polling refresh every 15-30s per
/// the cross-cutting live-update decision, matching every other
/// workspace dashboard (OW-001/AG-001/CW-001 siblings).
class InvestorHomeDashboardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const InvestorHomeDashboardScreen({super.key, required this.businessId});

  @override
  ConsumerState<InvestorHomeDashboardScreen> createState() => _InvestorHomeDashboardScreenState();
}

class _InvestorHomeDashboardScreenState extends ConsumerState<InvestorHomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(investorDashboardProvider.notifier).load(widget.businessId);
    });
  }

  Future<void> _refresh() => ref.read(investorDashboardProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final async = ref.watch(investorDashboardProvider);

    // Same change as CW-001: the three controls come out of the overflow menu
    // and the drawer gives this workspace persistent navigation.
    return ManaAppShell(
      userName: ref.watch(personDisplayNameProvider).valueOrNull ?? '',
      businessName: businessNameFor(ref, widget.businessId),
      // Investors had no notifications entry either, which mattered more
      // here: an investor's join request is the one flow that starts with
      // them and waits on an Owner.
      actions: const [ManaNotificationBell()],
      sections: [
        ManaDrawerSection(
          icon: Icons.savings_outlined,
          labelKey: 'my_investments',
          actions: [
            ManaDrawerAction(
              labelKey: 'my_investments',
              onTap: () => context.push('/iw-003', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'request_withdrawal',
              onTap: () => context.push('/iw-004', extra: widget.businessId),
            ),
          ],
        ),
        ManaDrawerSection(
          icon: Icons.person_outline,
          labelKey: 'my_account',
          actions: [
            ManaDrawerAction(
              labelKey: 'my_profile',
              onTap: () => context.push('/iw-005', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'find_a_business',
              onTap: () => context.push('/iw-002'),
            ),
          ],
        ),
        // Settings / Switch / Logout used to be icons in the header's second
        // row. That row is gone — they are drawer rows now, shared with the
        // other three workspaces so the order and labels cannot drift.
        ...manaGlobalDrawerSections(
          onProfile: () => context.push('/iw-005'),
          onSwitchWorkspace: () => context.go('/lr-012'),
          onSwitchRole: () => context.go('/lr-013', extra: widget.businessId),
          onSettings: () =>
              context.push('/iw-settings', extra: widget.businessId),
          onLogout: () {
            ref.read(authFlowProvider.notifier).reset();
            context.go('/lr-009');
          },
        ),
      ],
      body: SafeArea(
        child: async.when(
          // Only shown on a genuine cold load — revisits keep the previous
          // data on screen and revalidate behind it (see load()).
          loading: () => const ManaSkeletonList(itemCount: 5, itemHeight: 120),
          error: (e, _) => _errorState(e),
          data: (data) => data.hasActiveMembership
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: [
                      _Header(
                        businessName: data.businessName,
                        investorName: data.investorName,
                        verified: data.investorVerified,
                        notifications: data.notifications,
                      ),
                      const SizedBox(height: ManaSpacing.lg),
                      _MySummary(data: data),
                      const SizedBox(height: ManaSpacing.lg),
                      _QuickActions(businessId: widget.businessId),
                    ],
                  ),
                )
              // S3 — No Memberships: same default-state inference
              // pattern as CW-001 S3 — direct straight to Find A
              // Business rather than showing an empty dashboard shell.
              : _NoMembershipsState(businessId: widget.businessId),
        ),
      ),
    );
  }

  Widget _errorState(Object e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('could_not_load_dashboard')),
            const SizedBox(height: ManaSpacing.sm),
            // Was completely swallowed before — the real exception (e)
            // was passed in but never actually shown, meaning every
            // failure looked identical regardless of real cause. Shown
            // here so it's reportable/screenshottable instead of guessed at.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
              child: ManaText.raw(
                e.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: ManaColors.statusBad),
              ),
            ),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: _refresh, child: ManaText.raw(ref.t('retry'))),
          ],
        ),
      ),
    );
  }
}

// --- HEADER --------------------------------------------------------------

class _Header extends ConsumerWidget {
  final String businessName;
  final String investorName;
  final bool verified;
  final List<InvestorNotification> notifications;
  const _Header({
    required this.businessName,
    required this.investorName,
    required this.verified,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        ManaVerificationRing(isVerified: verified, size: 48),
        const SizedBox(width: ManaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ManaText.raw(investorName, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: ref.t('notifications'),
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _NotificationsSheet(notifications: notifications),
          ),
        ),
        IconButton(
          tooltip: ref.t('switch_business'),
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => context.go('/lr-012'),
        ),
      ],
    );
  }
}

class _NotificationsSheet extends ConsumerWidget {
  final List<InvestorNotification> notifications;
  const _NotificationsSheet({required this.notifications});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('notifications'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: ManaText.raw(ref.t('no_notifications_yet'), style: TextStyle(color: ManaColors.textSecondary)),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final n = notifications[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            n.read ? Icons.notifications_none : Icons.notifications_active,
                            color: n.read ? ManaColors.textSecondary : ManaColors.brand,
                          ),
                          title: ManaText.raw(n.message, style: const TextStyle(fontSize: 13)),
                          subtitle: ManaText.raw(n.type, style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                          trailing: ManaText.raw(DateFormat('d MMM, hh:mm a').format(n.timestamp),
                              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- MY SUMMARY ------------------------------------------------------------

class _MySummary extends ConsumerWidget {
  final InvestorDashboardData data;
  const _MySummary({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = <(String, String, ManaStatus)>[
      (ref.t('total_investment_balance'), _currency.format(data.totalInvestmentBalance), ManaStatus.neutral),
      (ref.t('active_investments'), '${data.activeInvestmentCount}', ManaStatus.good),
      (ref.t('interest_accrued'), _currency.format(data.totalInterestAccrued), ManaStatus.neutral),
      (ref.t('interest_paid_to_date'), _currency.format(data.interestPaidToDate), ManaStatus.good),
      (ref.t('pending_withdrawal_requests'), '${data.pendingWithdrawalRequests}', ManaStatus.warn),
      (ref.t('pending_interest_payment_requests'), '${data.pendingInterestPaymentRequests}', ManaStatus.warn),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('my_summary'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.md),
            Wrap(
              spacing: ManaSpacing.lg,
              runSpacing: ManaSpacing.md,
              children: stats
                  .map((s) => SizedBox(
                        width: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ManaText.raw(s.$2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 2),
                            ManaStatusPill(label: s.$1, status: s.$3),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// --- QUICK ACTIONS -----------------------------------------------------

class _QuickActions extends ConsumerWidget {
  final String businessId;
  const _QuickActions({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personId = ref.watch(authFlowProvider).personId;
    final actions = <(String, IconData, String, String)>[
      (ref.t('find_a_business'), Icons.search, '/iw-002', businessId),
      (ref.t('my_investments'), Icons.pie_chart_outline, '/iw-003', businessId),
      // BUG FIXED this pass: this used to push straight to '/iw-004' with
      // `businessId` as `extra`, but IW-004 requires a specific
      // `investmentId` (router.dart builds
      // RequestWithdrawalScreen(investmentId: s.extra as String?)) —
      // every tap failed with "Could not load this investment." since
      // there's no such investment. Withdrawal always needs a specific
      // investment picked first (which investment IW-003's own working
      // "request withdrawal" button already does correctly) — routing
      // here to My Investments instead of a dead IW-004 hit.
      (ref.t('request_withdrawal'), Icons.request_page_outlined, '/iw-003', businessId),
      // My Profile/Memberships is scoped by personId, not businessId — it
      // shows every membership across every business for this person.
      (ref.t('my_profile_memberships'), Icons.badge_outlined, '/iw-005', personId ?? businessId),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('quick_actions'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ...actions.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.$2, color: ManaColors.brand),
                  title: ManaText.raw(a.$1),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push(a.$3, extra: a.$4),
                )),
          ],
        ),
      ),
    );
  }
}

// --- S3 No Memberships --------------------------------------------------

class _NoMembershipsState extends ConsumerWidget {
  final String businessId;
  const _NoMembershipsState({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('no_business_memberships_yet'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              ref.t('find_investor_membership_note'),
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/iw-002', extra: businessId),
              icon: const Icon(Icons.search),
              label: ManaText.raw(ref.t('find_a_business')),
            ),
          ],
        ),
      ),
    );
  }
}

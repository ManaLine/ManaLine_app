import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('investor_dashboard')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'switch_business':
                  context.go('/lr-012');
                case 'switch_role':
                  context.go('/lr-013');
                case 'settings':
                  context.push('/iw-settings', extra: widget.businessId);
                case 'logout':
                  ref.read(authFlowProvider.notifier).reset();
                  context.go('/lr-003');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'switch_business', child: ManaText('switch workspace')),
              PopupMenuItem(value: 'switch_role', child: ManaText('switch role')),
              PopupMenuItem(value: 'settings', child: ManaText('settings')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: ManaText('logout')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
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
            const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load dashboard'),
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
                style: const TextStyle(fontSize: 11, color: ManaColors.statusBad),
              ),
            ),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: _refresh, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

// --- HEADER --------------------------------------------------------------

class _Header extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        ManaVerificationRing(isVerified: verified, size: 48),
        const SizedBox(width: ManaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ManaText.raw(investorName, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _NotificationsSheet(notifications: notifications),
          ),
        ),
        IconButton(
          tooltip: 'Switch Business',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => context.go('/lr-012'),
        ),
      ],
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  final List<InvestorNotification> notifications;
  const _NotificationsSheet({required this.notifications});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            Expanded(
              child: notifications.isEmpty
                  ? const Center(
                      child: ManaText.raw('No notifications yet.', style: TextStyle(color: ManaColors.textSecondary)),
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
                            color: n.read ? ManaColors.textSecondary : ManaColors.brass,
                          ),
                          title: ManaText.raw(n.message, style: const TextStyle(fontSize: 13)),
                          subtitle: ManaText.raw(n.type, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                          trailing: ManaText.raw(DateFormat('d MMM, hh:mm a').format(n.timestamp),
                              style: const TextStyle(fontSize: 10, color: ManaColors.textSecondary)),
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

class _MySummary extends StatelessWidget {
  final InvestorDashboardData data;
  const _MySummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Total Investment Balance', _currency.format(data.totalInvestmentBalance), ManaStatus.neutral),
      ('Active Investments', '${data.activeInvestmentCount}', ManaStatus.good),
      ('Interest Accrued', _currency.format(data.totalInterestAccrued), ManaStatus.neutral),
      ('Interest Paid to Date', _currency.format(data.interestPaidToDate), ManaStatus.good),
      ('Pending Withdrawal Requests', '${data.pendingWithdrawalRequests}', ManaStatus.warn),
      ('Pending Interest Payment Requests', '${data.pendingInterestPaymentRequests}', ManaStatus.warn),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('my summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      ('Find A Business', Icons.search, '/iw-002', businessId),
      ('My Investments', Icons.pie_chart_outline, '/iw-003', businessId),
      // BUG FIXED this pass: this used to push straight to '/iw-004' with
      // `businessId` as `extra`, but IW-004 requires a specific
      // `investmentId` (router.dart builds
      // RequestWithdrawalScreen(investmentId: s.extra as String?)) —
      // every tap failed with "Could not load this investment." since
      // there's no such investment. Withdrawal always needs a specific
      // investment picked first (which investment IW-003's own working
      // "request withdrawal" button already does correctly) — routing
      // here to My Investments instead of a dead IW-004 hit.
      ('Request Withdrawal', Icons.request_page_outlined, '/iw-003', businessId),
      // My Profile/Memberships is scoped by personId, not businessId — it
      // shows every membership across every business for this person.
      ('My Profile / Memberships', Icons.badge_outlined, '/iw-005', personId ?? businessId),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('quick actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ...actions.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.$2, color: ManaColors.brass),
                  title: ManaText(a.$1),
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

class _NoMembershipsState extends StatelessWidget {
  final String businessId;
  const _NoMembershipsState({required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('no business memberships yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            const ManaText.raw(
              'Find a Business to request Investor membership. Once the '
              'Owner approves, it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/iw-002', extra: businessId),
              icon: const Icon(Icons.search),
              label: const ManaText('find a business'),
            ),
          ],
        ),
      ),
    );
  }
}

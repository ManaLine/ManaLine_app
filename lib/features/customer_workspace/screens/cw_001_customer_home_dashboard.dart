import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/auto_refresh.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/customer_dashboard_state.dart';
import '../../../shared/translation_service.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

/// CW-001 — Customer Home Dashboard. Primary entry point for a Customer,
/// reached from LR-013 Role Selector (Customer role chosen). Read-only
/// aggregation screen; every write happens on the destination screens
/// its Quick Actions link to. No Business Session / Area Selection / BF
/// Gate concept applies here (that's Agent-only mechanics) — this is a
/// straightforward "load dashboard data, display" screen once a
/// Business is selected. Polling refresh every 15-30s per the
/// cross-cutting live-update decision, matching every other workspace
/// dashboard (OW-001/AG-001/IW-001 siblings).
class CustomerHomeDashboardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const CustomerHomeDashboardScreen({super.key, required this.businessId});

  @override
  ConsumerState<CustomerHomeDashboardScreen> createState() =>
      _CustomerHomeDashboardScreenState();
}

class _CustomerHomeDashboardScreenState
    extends ConsumerState<CustomerHomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerDashboardProvider.notifier).load(widget.businessId);
    });
  }

  Future<void> _refresh() =>
      ref.read(customerDashboardProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final async = ref.watch(customerDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('customer_dashboard')),
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
                  context.push('/cw-settings', extra: widget.businessId);
                case 'logout':
                  ref.read(authFlowProvider.notifier).reset();
                  context.go('/lr-003');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'switch_business',
                  child: ManaText('switch workspace')),
              PopupMenuItem(
                  value: 'switch_role', child: ManaText('switch role')),
              PopupMenuItem(value: 'settings', child: ManaText('settings')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: ManaText('logout')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          // Only shown on a genuine cold load — revisits keep the previous
          // data on screen and revalidate behind it (see load()).
          loading: () => const ManaSkeletonList(itemCount: 5, itemHeight: 120),
          error: (e, _) => _errorState(e),
          data: (data) => data.hasActiveMembership
              ? AutoRefresh(
                  onRefresh: _refresh,
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      children: [
                        _Header(
                          businessName: data.businessName,
                          customerName: data.customerName,
                          verified: data.verified,
                          photo: data.profilePhotoUrl,
                        ),
                        const SizedBox(height: ManaSpacing.lg),
                        _MySummary(data: data),
                        const SizedBox(height: ManaSpacing.lg),
                        _QuickActions(businessId: widget.businessId),
                      ],
                    ),
                  ),
                )
              // S3 — No Memberships: a brand-new Customer with zero
              // Active Business Memberships lands here and is directed
              // straight into CW-002, not shown an empty dashboard
              // shell (spec's own S3 wording).
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
            const Icon(Icons.cloud_off,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load dashboard'),
            const SizedBox(height: ManaSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
              child: ManaText.raw(
                e.toString(),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: ManaColors.statusBad),
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
//
// Full HEADER per spec also includes Business Logo, Language selector,
// Notification Center, Universal Search, Profile, Switch Business, Switch
// Role — those are shared app-chrome elements owned elsewhere (same split
// already established at IW-001: this screen renders the icon buttons as
// no-op stubs, the actual shared header widget/drawer is a separate
// integration task for master chat, flagged below).
class _Header extends StatelessWidget {
  final String businessName;
  final String customerName;
  final bool verified;
  final String? photo;
  const _Header(
      {required this.businessName,
      required this.customerName,
      required this.verified,
      this.photo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ManaVerificationRing(
          isVerified: verified,
          photo: photo != null ? NetworkImage(photo!) : null,
          size: 48,
        ),
        const SizedBox(width: ManaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(businessName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              ManaText.raw(customerName,
                  style: const TextStyle(
                      color: ManaColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () {},
        ),
        IconButton(
          tooltip: 'Switch Business',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () {},
        ),
      ],
    );
  }
}

// --- MY SUMMARY ------------------------------------------------------------

class _MySummary extends StatelessWidget {
  final CustomerDashboardData data;
  const _MySummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Active Loans', '${data.activeLoansCount}', ManaStatus.good),
      (
        'Total Outstanding',
        _currency.format(data.totalOutstanding),
        ManaStatus.neutral
      ),
      (
        'Next Payment Due',
        data.nextPaymentDueDate != null
            ? '${_currency.format(data.nextPaymentDueAmount ?? 0)} · ${_dateFmt.format(data.nextPaymentDueDate!)}'
            : '—',
        ManaStatus.warn,
      ),
      (
        'Pending Loan Requests',
        '${data.pendingLoanRequestsCount}',
        ManaStatus.warn
      ),
      (
        'Pending Online Payments',
        '${data.pendingOnlinePaymentsCount}',
        ManaStatus.warn
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('my summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.md),
            Wrap(
              spacing: ManaSpacing.lg,
              runSpacing: ManaSpacing.md,
              children: stats
                  .map((s) => SizedBox(
                        width: 160,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ManaText.raw(s.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
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
//
// Find A Business → CW-002 (this chat, live route). Request New Loan →
// CW-003, My Loans → CW-004, Make A Payment → CW-005, My Profile /
// Memberships → CW-006 — none of these screens exist yet; stubbed as
// named destinations, same pattern AG-001 used for AG-003..AG-009 before
// those existed. Master chat wires the real routes once those chats land.
class _QuickActions extends ConsumerWidget {
  final String businessId;
  const _QuickActions({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personId = ref.watch(authFlowProvider).personId;
    final actions = <(String, IconData, String, String)>[
      ('Find A Business', Icons.search, '/cw-002', businessId),
      ('Request New Loan', Icons.request_page_outlined, '/cw-003', businessId),
      (
        'My Loans',
        Icons.account_balance_wallet_outlined,
        '/cw-004',
        businessId
      ),
      ('Make A Payment', Icons.payments_outlined, '/cw-004', businessId),
      // My Profile/Memberships is scoped by personId, not businessId — it
      // shows every membership across every business for this person
      // (same convention as IW-005).
      (
        'My Profile / Memberships',
        Icons.badge_outlined,
        '/cw-006',
        personId ?? businessId
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('quick actions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ...actions.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(a.$2, color: ManaColors.brand),
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
            const Icon(Icons.storefront_outlined,
                size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('no business memberships yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            const ManaText.raw(
              'Find a Business to request Customer membership. Once the '
              'Owner or Agent approves, it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/cw-002', extra: businessId),
              icon: const Icon(Icons.search),
              label: const ManaText('find a business'),
            ),
          ],
        ),
      ),
    );
  }
}

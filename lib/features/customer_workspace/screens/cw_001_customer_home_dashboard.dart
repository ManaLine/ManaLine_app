import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/auto_refresh.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../shared/notification_bell.dart';
import '../../../shared/person_identity.dart';
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

    // Switch / Settings / Logout were buried in an overflow menu behind a
    // three-dot glyph. The shell surfaces all three as labelled controls and
    // adds the drawer, which is the point of P1 — this workspace previously
    // had no persistent navigation at all.
    return ManaAppShell(
      userName: ref.watch(personDisplayNameProvider).valueOrNull ?? '',
      businessName: businessNameFor(ref, widget.businessId),
      // Customers had no notifications entry at all before this — the only
      // notifications screen in the app was AG-008, agent-only. An invitation
      // to join a business reached them nowhere.
      actions: const [ManaNotificationBell()],
      sections: [
        ManaDrawerSection(
          icon: Icons.account_balance_wallet_outlined,
          labelKey: 'my_loans',
          actions: [
            ManaDrawerAction(
              labelKey: 'my_loans',
              onTap: () => context.push('/cw-004', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'request_new_loan',
              onTap: () => context.push('/cw-003', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'make_a_payment',
              onTap: () => context.push('/cw-005', extra: widget.businessId),
            ),
          ],
        ),
        ManaDrawerSection(
          icon: Icons.person_outline,
          labelKey: 'my_account',
          actions: [
            ManaDrawerAction(
              labelKey: 'my_profile',
              onTap: () => context.push('/cw-006', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'find_a_business',
              onTap: () => context.push('/cw-002'),
            ),
          ],
        ),
        // Settings / Switch / Logout used to be icons in the header's second
        // row. That row is gone — they are drawer rows now, shared with the
        // other three workspaces so the order and labels cannot drift.
        ...manaGlobalDrawerSections(
          onProfile: () => context.push('/cw-006'),
          onSwitchWorkspace: () => context.go('/lr-012'),
          onSwitchRole: () => context.go('/lr-013', extra: widget.businessId),
          onSettings: () =>
              context.push('/cw-settings', extra: widget.businessId),
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
            Icon(Icons.cloud_off,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('could_not_load_dashboard')),
            const SizedBox(height: ManaSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
              child: ManaText.raw(
                e.toString(),
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: ManaColors.statusBad),
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
//
// Full HEADER per spec also includes Business Logo, Language selector,
// Notification Center, Universal Search, Profile, Switch Business, Switch
// Role — those are shared app-chrome elements owned elsewhere (same split
// already established at IW-001: this screen renders the icon buttons as
// no-op stubs, the actual shared header widget/drawer is a separate
// integration task for master chat, flagged below).
class _Header extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                  style: TextStyle(
                      color: ManaColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: ref.t('notifications'),
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () {},
        ),
        IconButton(
          tooltip: ref.t('switch_business'),
          icon: const Icon(Icons.swap_horiz),
          onPressed: () {},
        ),
      ],
    );
  }
}

// --- MY SUMMARY ------------------------------------------------------------

class _MySummary extends ConsumerWidget {
  final CustomerDashboardData data;
  const _MySummary({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = <(String, String, ManaStatus)>[
      (ref.t('active_loans'), '${data.activeLoansCount}', ManaStatus.good),
      (
        ref.t('total_outstanding'),
        _currency.format(data.totalOutstanding),
        ManaStatus.neutral
      ),
      (
        ref.t('next_payment_due'),
        data.nextPaymentDueDate != null
            ? '${_currency.format(data.nextPaymentDueAmount ?? 0)} · ${_dateFmt.format(data.nextPaymentDueDate!)}'
            : '—',
        ManaStatus.warn,
      ),
      (
        ref.t('pending_loan_requests'),
        '${data.pendingLoanRequestsCount}',
        ManaStatus.warn
      ),
      (
        ref.t('pending_online_payments'),
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
            ManaText.raw(ref.t('my_summary'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
      (ref.t('find_a_business'), Icons.search, '/cw-002', businessId),
      (ref.t('request_new_loan'), Icons.request_page_outlined, '/cw-003', businessId),
      (
        ref.t('my_loans'),
        Icons.account_balance_wallet_outlined,
        '/cw-004',
        businessId
      ),
      (ref.t('make_a_payment'), Icons.payments_outlined, '/cw-004', businessId),
      // My Profile/Memberships is scoped by personId, not businessId — it
      // shows every membership across every business for this person
      // (same convention as IW-005).
      (
        ref.t('my_profile_memberships'),
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
            ManaText.raw(ref.t('quick_actions'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
            Icon(Icons.storefront_outlined,
                size: 48, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('no_business_memberships_yet'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              ref.t('find_business_membership_note'),
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/cw-002', extra: businessId),
              icon: const Icon(Icons.search),
              label: ManaText.raw(ref.t('find_a_business')),
            ),
          ],
        ),
      ),
    );
  }
}

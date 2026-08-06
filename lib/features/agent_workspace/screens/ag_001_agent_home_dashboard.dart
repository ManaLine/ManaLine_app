import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/auto_refresh.dart';
import '../../../shared/translation_service.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../shared/person_identity.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/agent_dashboard_state.dart';
import 'ag_002_collection_mode.dart';
import 'ag_003_todays_route.dart';
import 'ag_004_customer_management.dart';
import 'ag_005_draft_transactions.dart';
import 'ag_006_owner_settlement.dart';
import 'ag_007_loan_distribution.dart';
import 'ag_008_notifications.dart';
import 'ag_009_profile.dart';
import 'ag_010_transaction_history.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _time = DateFormat('h:mm a');
final _date = DateFormat('d MMM yyyy');

/// AG-001 — Agent Home Dashboard. Entry sequence per spec: Opening BF
/// Confirm/Update gate (S0, blocking) → Area Selection (S1, no running
/// session) → populated dashboard (S2, session running).
///
/// CHANGED this batch: header menu now has "Create New Business" (same
/// OW-000 flow LR-012's own S0 uses), and the Scaffold now carries a
/// bottom nav bar — same Home/Customers/Collections pattern as OW-001's
/// own footer, plus a 4th "History" tab (new AG-010 screen) since the
/// Agent side has no existing equivalent of Owner's OW-017. Per the
/// Owner-side precedent already established (OW-001 has this footer;
/// OW-002/006/etc drill-down screens deliberately do not), this footer
/// belongs on AG-001 only — not duplicated onto every AG-00x drill-down
/// screen.
class AgentHomeDashboardScreen extends ConsumerStatefulWidget {
  final String agentId;
  final String businessId;
  // Set from the '?anchor=compensation' query param when entered from
  // AG-009's "My Compensation" link-out row (per AG-009's own note that it
  // links to, rather than duplicates, this screen's Compensation panel).
  final String? initialAnchor;
  const AgentHomeDashboardScreen({
    super.key,
    required this.agentId,
    required this.businessId,
    this.initialAnchor,
  });

  @override
  ConsumerState<AgentHomeDashboardScreen> createState() =>
      _AgentHomeDashboardScreenState();
}

class _AgentHomeDashboardScreenState
    extends ConsumerState<AgentHomeDashboardScreen> {
  final _compensationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref
          .read(agentDashboardProvider.notifier)
          .enter(agentId: widget.agentId, businessId: widget.businessId);
      if (widget.initialAnchor == 'compensation' && mounted) {
        // Give the dashboard a frame to lay out before scrolling to it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _compensationKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300));
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final state = ref.watch(agentDashboardProvider);

    // Notifications and Profile stay as header actions — they belong to this
    // screen. Switch / Settings / Logout move to the shell's global row, and
    // the rest of the old overflow menu becomes drawer rows, which is how they
    // stop being hidden behind a three-dot glyph.
    return ManaAppShell(
      userName: ref.watch(personDisplayNameProvider).valueOrNull ?? '',
      businessName: businessNameFor(ref, widget.businessId),
      actions: [
        ManaHeaderAction(
          icon: Icons.notifications_outlined,
          label: 'Notifications',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Ag008NotificationsScreen(
                  agentId: widget.agentId, businessId: widget.businessId),
            ),
          ),
        ),
        ManaHeaderAction(
          icon: Icons.person_outline,
          label: 'Profile',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Ag009ProfileScreen(
                personId: ref.read(authFlowProvider).personId ?? '',
                agentId: widget.agentId,
                businessId: widget.businessId,
              ),
            ),
          ),
        ),
      ],
      sections: [
        ManaDrawerSection(
          icon: Icons.people_outline,
          labelKey: 'customers',
          actions: [
            ManaDrawerAction(
              labelKey: 'customer management',
              onTap: () => context.push('/ag-004', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: "today's route",
              onTap: () => context.push('/ag-003', extra: widget.businessId),
            ),
          ],
        ),
        ManaDrawerSection(
          icon: Icons.work_outline,
          labelKey: 'my work',
          actions: [
            ManaDrawerAction(
              labelKey: 'draft transactions',
              onTap: () => context.push('/ag-005', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'transaction history',
              onTap: () => context.push('/ag-010', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'change area',
              // Null while the session is not running: the add/remove-area
              // RPCs only apply to a running session, so offering it earlier
              // would open a sheet that cannot act.
              onTap: state.stage != AgentSessionStage.running
                  ? null
                  : () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _ChangeAreaSheet(
                            state: state,
                            agentId: widget.agentId,
                            businessId: widget.businessId),
                      ),
            ),
            ManaDrawerAction(
              labelKey: 'create new business',
              // Same OW-000 flow LR-012's S0 uses for a person's first
              // business — this Agent already has an account and at least one
              // membership, so it is an *additional* business.
              onTap: () => context.push('/ow-000', extra: true),
            ),
          ],
        ),
      ],
      onSettings: () => context.push('/ag-settings', extra: widget.businessId),
      onSwitch: () => context.go('/lr-013', extra: widget.businessId),
      onLogout: () {
        ref.read(authFlowProvider.notifier).reset();
        context.go('/lr-003');
      },
      bottomNavigationBar: _AgentFooterNav(
          businessId: widget.businessId, agentId: widget.agentId),
      body: SafeArea(
        child: switch (state.stage) {
          // Structure-shaped placeholder instead of a spinner while the
          // Opening-BF gate resolves.
          AgentSessionStage.loadingGate =>
            const ManaSkeletonList(itemCount: 4, itemHeight: 112),
          AgentSessionStage.bfBlockedNoAssignment => const _BfNotGrantedBlock(),
          AgentSessionStage.bfConfirmPending => _BfGate(
              state: state,
              agentId: widget.agentId,
              businessId: widget.businessId),
          AgentSessionStage.bfUpdateRequested =>
            const _BfUpdateRequestedBlock(),
          AgentSessionStage.areaSelection => _AreaSelection(
              state: state,
              agentId: widget.agentId,
              businessId: widget.businessId),
          AgentSessionStage.running => _RunningDashboard(
              state: state,
              agentId: widget.agentId,
              businessId: widget.businessId,
              compensationKey: _compensationKey,
            ),
        },
      ),
    );
  }
}

// --- Footer Navigation (new this batch) -----------------------------------

/// Same Home/Customers/Collections pattern as OW-001's own `_FooterNav`,
/// plus a 4th "History" tab (AG-010, new this batch) since the Agent
/// side has no pre-existing equivalent of Owner's OW-017 Daily Record
/// Book. Home (index 0) is a no-op — this screen already IS Home.
class _AgentFooterNav extends ConsumerWidget {
  final String businessId;
  final String agentId;
  const _AgentFooterNav({required this.businessId, required this.agentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: [
        NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: ref.t('home')),
        NavigationDestination(
            icon: const Icon(Icons.people_outline), label: ref.t('customers')),
        NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            label: ref.t('collections')),
        NavigationDestination(
            icon: const Icon(Icons.history), label: ref.t('history')),
      ],
      onDestinationSelected: (i) {
        switch (i) {
          case 1:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AgentCustomerManagementScreen(
                    businessId: businessId, agentMembershipId: agentId),
              ),
            );
          case 2:
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      AgentCollectionModeScreen(businessId: businessId)),
            );
          case 3:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Ag010TransactionHistoryScreen(
                    businessId: businessId, agentMembershipId: agentId),
              ),
            );
        }
      },
    );
  }
}

// --- Opening BF Confirm/Update Gate (mobile scenario-testing 2026-07-19) ---

class _BfGate extends ConsumerStatefulWidget {
  final AgentDashboardState state;
  final String agentId;
  final String businessId;
  const _BfGate(
      {required this.state, required this.agentId, required this.businessId});

  @override
  ConsumerState<_BfGate> createState() => _BfGateState();
}

class _BfGateState extends ConsumerState<_BfGate> {
  bool _submitting = false;

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    await NetworkErrorHandler.run(context, () {
      return ref
          .read(agentDashboardProvider.notifier)
          .confirmBf(agentId: widget.agentId, businessId: widget.businessId);
    });
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _update() async {
    setState(() => _submitting = true);
    await NetworkErrorHandler.run(context, () {
      return ref
          .read(agentDashboardProvider.notifier)
          .disputeBf(agentId: widget.agentId);
    });
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bf = widget.state.bfAssignment!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 40, color: ManaColors.brand),
                const SizedBox(height: ManaSpacing.md),
                const ManaText('opening bf for this session'),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(_currency.format(bf.openingBf),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(
                  'Confirm this figure to proceed, or Update if it looks wrong — '
                  'you will be blocked from the workspace until the Owner corrects it.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                ),
                const SizedBox(height: ManaSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _update,
                        child: const ManaText('update'),
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.md),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _confirm,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const ManaText('confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BfNotGrantedBlock extends StatelessWidget {
  const _BfNotGrantedBlock();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('access not yet granted'),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              'Owner has not assigned an Opening BF for this session yet. '
              'Please contact your Owner.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BfUpdateRequestedBlock extends StatelessWidget {
  const _BfUpdateRequestedBlock();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_outlined,
                size: 40, color: ManaColors.statusWarn),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('waiting on owner'),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              'Your Opening BF dispute has been sent to the Owner. You will be '
              're-prompted with the corrected figure once they resolve it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Area Selection (S1) -------------------------------------------------

class _AreaSelection extends ConsumerStatefulWidget {
  final AgentDashboardState state;
  final String agentId;
  final String businessId;
  const _AreaSelection(
      {required this.state, required this.agentId, required this.businessId});

  @override
  ConsumerState<_AreaSelection> createState() => _AreaSelectionState();
}

class _AreaSelectionState extends ConsumerState<_AreaSelection> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    final ok = await NetworkErrorHandler.run(context, () {
      return ref.read(agentDashboardProvider.notifier).startBusinessSession(
            agentId: widget.agentId,
            businessId: widget.businessId,
          );
    });
    if (mounted) setState(() => _starting = false);
    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select at least one enabled area to start.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = widget.state.enabledAreas;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText('select operating area(s)'),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          'Only areas enabled by your Owner are shown. Select one or more to start today\'s Business Session.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (areas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
            child: Center(
              child: ManaText.raw(
                  'No areas enabled for you yet. Contact your Owner.',
                  style: TextStyle(color: ManaColors.textSecondary)),
            ),
          )
        else
          ...areas.map((area) => Card(
                margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
                child: CheckboxListTile(
                  title: ManaText.raw(area.areaName),
                  value: area.selectedInSession,
                  onChanged: (v) => ref
                      .read(agentDashboardProvider.notifier)
                      .toggleAreaSelection(area.operatingAreaId, v ?? false),
                ),
              )),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed:
              (widget.state.canStartSession && !_starting) ? _start : null,
          child: _starting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('start business session'),
        ),
      ],
    );
  }
}

class _ChangeAreaSheet extends ConsumerStatefulWidget {
  final AgentDashboardState state;
  final String agentId;
  final String businessId;
  const _ChangeAreaSheet(
      {required this.state, required this.agentId, required this.businessId});

  @override
  ConsumerState<_ChangeAreaSheet> createState() => _ChangeAreaSheetState();
}

class _ChangeAreaSheetState extends ConsumerState<_ChangeAreaSheet> {
  String? _pendingAreaId;

  Future<void> _toggle(AgentAreaAssignment area, bool selected) async {
    setState(() => _pendingAreaId = area.operatingAreaId);
    final notifier = ref.read(agentDashboardProvider.notifier);
    final ok = selected
        ? await notifier.addArea(
            agentId: widget.agentId,
            businessId: widget.businessId,
            operatingAreaId: area.operatingAreaId)
        : await notifier.removeArea(
            agentId: widget.agentId,
            businessId: widget.businessId,
            operatingAreaId: area.operatingAreaId);
    if (!mounted) return;
    setState(() => _pendingAreaId = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not change area — save or clear pending unsaved transactions first.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(agentDashboardProvider).enabledAreas;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('change area',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Adding an area starts working it immediately; removing one stops new collections there for today (its Account Period keeps running to its own end date).',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            ...areas.map((area) => CheckboxListTile(
                  title: ManaText.raw(area.areaName),
                  value: area.selectedInSession,
                  onChanged: _pendingAreaId == area.operatingAreaId
                      ? null
                      : (v) => _toggle(area, v ?? false),
                  secondary: _pendingAreaId == area.operatingAreaId
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                )),
          ],
        ),
      ),
    );
  }
}

// --- Running Dashboard (S2) -----------------------------------------------

class _RunningDashboard extends ConsumerWidget {
  final AgentDashboardState state;
  final String agentId;
  final String businessId;
  final Key? compensationKey;
  const _RunningDashboard({
    required this.state,
    required this.agentId,
    required this.businessId,
    this.compensationKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = state.dashboard;
    if (d == null) return const Center(child: CircularProgressIndicator());

    return AutoRefresh(
      onRefresh: () => ref
          .read(agentDashboardProvider.notifier)
          .refreshDashboard(agentId: agentId, businessId: businessId),
      child: RefreshIndicator(
        onRefresh: () => ref
            .read(agentDashboardProvider.notifier)
            .refreshDashboard(agentId: agentId, businessId: businessId),
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            _SectionCard(
              title: 'business status',
              rows: [
                ('Business Date', _date.format(d.businessDate)),
                ('Assigned Route', d.assignedRoute),
                ('Pending Drafts', '${d.pendingDraftsCount}'),
                ('Pending Settlement', d.pendingSettlement ? 'Yes' : 'No'),
                ("Today's Target", _currency.format(d.todaysTarget)),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            _SectionCard(
              title: 'today summary',
              rows: [
                ('Customers Assigned', '${d.customersAssigned}'),
                ('Customers Visited', '${d.customersVisited}'),
                ('Customers Remaining', '${d.customersRemaining}'),
                ('Cash', _currency.format(d.collectionsCash)),
                ('UPI', _currency.format(d.collectionsUpi)),
                ('Bank', _currency.format(d.collectionsBank)),
                ('Cheque', _currency.format(d.collectionsCheque)),
                ('Mixed', _currency.format(d.collectionsMixed)),
                (
                  "Today's Collections Total",
                  _currency.format(d.todaysCollectionsTotal)
                ),
                ('Loans Issued', '${d.loansIssued}'),
                ('Pending Collections', '${d.pendingCollections}'),
                ('Skipped Customers', '${d.skippedCustomers}'),
                ('Short', _currency.format(d.shortAmount)),
                ('Excess', _currency.format(d.excessAmount)),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            _QuickActions(
                visible: d.visibleQuickActions,
                businessId: businessId,
                agentId: agentId),
            const SizedBox(height: ManaSpacing.md),
            if (state.hasPendingUnsavedTransactions ||
                d.pendingCustomerRequests +
                        d.pendingExtensionRequests +
                        d.pendingRouteChanges +
                        d.pendingMessages >
                    0)
              _SectionCard(
                title: 'attention required',
                rows: [
                  ('Pending Drafts', '${d.pendingDraftsCount}'),
                  ('Pending Settlement', d.pendingSettlement ? 'Yes' : 'No'),
                  ('Pending Customer Requests', '${d.pendingCustomerRequests}'),
                  (
                    'Pending Extension Requests',
                    '${d.pendingExtensionRequests}'
                  ),
                  ('Pending Route Changes', '${d.pendingRouteChanges}'),
                  ('Pending Messages', '${d.pendingMessages}'),
                ],
                accent: ManaColors.statusWarn,
              ),
            const SizedBox(height: ManaSpacing.md),
            _LiveActivity(entries: d.liveActivity),
            const SizedBox(height: ManaSpacing.md),
            _CompensationSection(key: compensationKey, d: d),
            const SizedBox(height: ManaSpacing.md),
            _SectionCard(
              title: 'workspace information',
              rows: [
                ('Business Name', d.businessName),
                ('Owner', d.ownerName),
                ('Membership Status', d.membershipStatus),
                ('Permission Profile', d.permissionProfile),
                ('Last Sync', _time.format(d.lastSync)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  final Color? accent;
  const _SectionCard({required this.title, required this.rows, this.accent});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accent ?? ManaColors.textPrimary)),
            const SizedBox(height: ManaSpacing.sm),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ManaText.raw(r.$1,
                          style: TextStyle(
                              fontSize: 13, color: ManaColors.textSecondary)),
                      ManaText.raw(r.$2,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// "MY COMPENSATION (Read-Only, Set By Owner)" — Fixed Salary, Salary
/// Cycle, Daily Allowance, Profit Share % (if enabled), Advances Deducted,
/// Shorts Deducted, Pending Salary, Salary History. This is the single
/// authoritative display AG-009 Profile links out to rather than
/// duplicating — no second live copy should ever be built elsewhere.
class _CompensationSection extends StatelessWidget {
  final AgentDashboardData d;
  const _CompensationSection({super.key, required this.d});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('my compensation',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw('Read-only, set by Owner.',
                style:
                    TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.sm),
            ...[
              ('Fixed Salary', _currency.format(d.fixedSalary)),
              (
                'Salary Cycle',
                d.salaryCycleStatus.isEmpty ? '—' : d.salaryCycleStatus
              ),
              ('Daily Allowance', _currency.format(d.dailyAllowance)),
              if (d.profitSharePercent != null)
                ('Profit Share', '${d.profitSharePercent}%'),
              ('Advances Deducted', _currency.format(d.advancesDeducted)),
              ('Shorts Deducted', _currency.format(d.shortsDeducted)),
              ('Pending Salary', _currency.format(d.pendingSalary)),
            ].map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ManaText.raw(r.$1,
                          style: TextStyle(
                              fontSize: 13, color: ManaColors.textSecondary)),
                      ManaText.raw(r.$2,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            if (d.salaryHistory.isNotEmpty) ...[
              const SizedBox(height: ManaSpacing.sm),
              const ManaText.raw('Salary History',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: ManaSpacing.xs),
              ...d.salaryHistory.take(6).map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ManaText.raw(h.cycleLabel,
                            style: TextStyle(
                                fontSize: 13, color: ManaColors.textSecondary)),
                        ManaText.raw(_currency.format(h.amount),
                            style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final Set<String> visible;
  final String businessId;
  final String agentId;
  const _QuickActions(
      {required this.visible, required this.businessId, required this.agentId});

  // Hidden modules remain fully absent — not shown greyed-out — per
  // OW-001's Quick Actions pattern that this screen mirrors.
  static const _all = [
    ('Collection Mode', Icons.payments_outlined),
    ('Area Work Session', Icons.route_outlined),
    ('Customer List', Icons.people_outline),
    ('Loan Distribution', Icons.request_page_outlined),
    ('Draft Transactions', Icons.drafts_outlined),
    ('Settlement', Icons.receipt_long_outlined),
    ('Notifications', Icons.notifications_outlined),
    ('Universal Search', Icons.search),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _all.where((a) => visible.contains(a.$1)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('quick actions',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: ManaSpacing.sm,
              crossAxisSpacing: ManaSpacing.sm,
              childAspectRatio: 0.95,
              children: items
                  .map((a) => _QuickActionTile(
                        label: a.$1,
                        icon: a.$2,
                        onTap: () {
                          switch (a.$1) {
                            case 'Collection Mode':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => AgentCollectionModeScreen(
                                        businessId: businessId)),
                              );
                              break;
                            case 'Area Work Session':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TodaysRouteScreen(
                                    businessId: businessId,
                                    agentMembershipId: agentId,
                                  ),
                                ),
                              );
                              break;
                            case 'Customer List':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AgentCustomerManagementScreen(
                                    businessId: businessId,
                                    agentMembershipId: agentId,
                                  ),
                                ),
                              );
                              break;
                            case 'Loan Distribution':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => Ag007LoanDistributionScreen(
                                    agentId: agentId,
                                    businessId: businessId,
                                  ),
                                ),
                              );
                              break;
                            case 'Draft Transactions':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DraftTransactionsScreen(
                                    businessId: businessId,
                                    membershipId: agentId,
                                  ),
                                ),
                              );
                              break;
                            case 'Settlement':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) {
                                    final now = DateTime.now();
                                    return OwnerSettlementScreen(
                                      businessId: businessId,
                                      agentId: agentId,
                                      periodStart: DateTime(
                                          now.year, now.month, now.day),
                                      periodEnd: DateTime(now.year, now.month,
                                          now.day, 23, 59, 59),
                                    );
                                  },
                                ),
                              );
                              break;
                            case 'Notifications':
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => Ag008NotificationsScreen(
                                      agentId: agentId, businessId: businessId),
                                ),
                              );
                              break;
                            case 'Universal Search':
                              // AG-004 already has a real search box
                              // ("Search by name, MLID, or phone") over
                              // this Agent's assigned customers — that's
                              // the only search surface actually built
                              // for the Agent role (unlike Owner's
                              // owner_search_person RPC, which is
                              // explicitly Owner-only server-side), so
                              // this reuses it rather than inventing a
                              // second search screen with nothing to
                              // query.
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AgentCustomerManagementScreen(
                                    businessId: businessId,
                                    agentMembershipId: agentId,
                                  ),
                                ),
                              );
                              break;
                          }
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickActionTile(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: ManaColors.inkFaint,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(ManaSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: ManaColors.ink),
            const SizedBox(height: ManaSpacing.xs),
            ManaText(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _LiveActivity extends StatelessWidget {
  final List<AgentLiveActivityEntry> entries;
  const _LiveActivity({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('live activity',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              ManaText.raw('Nothing yet today.',
                  style:
                      TextStyle(fontSize: 13, color: ManaColors.textSecondary))
            else
              ...entries.take(10).map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        ManaText.raw(_time.format(e.at),
                            style: TextStyle(
                                fontSize: 13, color: ManaColors.textSecondary)),
                        const SizedBox(width: ManaSpacing.sm),
                        Expanded(
                            child: ManaText.raw(e.description,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

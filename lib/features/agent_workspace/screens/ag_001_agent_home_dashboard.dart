import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/auto_refresh.dart';
import '../../../shared/translation_service.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_app_shell.dart';
import '../../../shared/notification_bell.dart';
import '../../../shared/person_identity.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/agent_dashboard_state.dart';
import 'ag_002_collection_mode.dart';
import 'ag_004_customer_management.dart';
import 'ag_005_draft_transactions.dart';
import 'ag_006_owner_settlement.dart';
import 'ag_007_loan_distribution.dart';
import 'ag_008_notifications.dart';
import 'ag_009_profile.dart';
import 'ag_010_transaction_history.dart';

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
        // Was AG-008, the app's only notifications screen and agent-only.
        // Now the shared inbox, which also carries the invitations that used
        // to be scattered across six other screens.
        const ManaNotificationBell(),
        ManaHeaderAction(
          icon: Icons.person_outline,
          label: ref.t('profile'),
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
              labelKey: 'customer_management',
              onTap: () => context.push('/ag-004', extra: widget.businessId),
            ),
            // Today's Route now IS Collection Mode. It was the same customer
            // list from the same provider, opening the same entry screen, and
            // its one distinction — ordering by route_locations.visit_order —
            // has never had any data: the routes table is empty. Collection
            // Mode's village filter says "work this area" better than a
            // separate screen did, and an Agent choosing between two doors to
            // the same round is a choice that costs them time and gains them
            // nothing.
            ManaDrawerAction(
              labelKey: 'collection_mode',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AgentCollectionModeScreen(businessId: widget.businessId),
                ),
              ),
            ),
          ],
        ),
        ManaDrawerSection(
          icon: Icons.work_outline,
          labelKey: 'my_work',
          actions: [
            ManaDrawerAction(
              labelKey: 'draft_transactions',
              onTap: () => context.push('/ag-005', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'transaction_history',
              onTap: () => context.push('/ag-010', extra: widget.businessId),
            ),
            ManaDrawerAction(
              labelKey: 'change_area',
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
              labelKey: 'create_new_business',
              // Same OW-000 flow LR-012's S0 uses for a person's first
              // business — this Agent already has an account and at least one
              // membership, so it is an *additional* business.
              onTap: () => context.push('/ow-000', extra: true),
            ),
          ],
        ),
        // Settings / Switch / Logout used to be icons in the header's second
        // row. That row is gone — they are drawer rows now, shared with the
        // other three workspaces so the order and labels cannot drift.
        ...manaGlobalDrawerSections(
          onProfile: () => context.push('/ag-009'),
          onSwitchWorkspace: () => context.go('/lr-012'),
          onSwitchRole: () => context.go('/lr-013', extra: widget.businessId),
          onSettings: () =>
              context.push('/ag-settings', extra: widget.businessId),
          onLogout: () {
            ref.read(authFlowProvider.notifier).reset();
            context.go('/lr-009');
          },
        ),
      ],
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
                ManaText.raw(ref.t('opening_bf_for_session')),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(manaRupees(bf.openingBf),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(
                  ref.t('confirm_bf_or_update_warning'),
                  textAlign: TextAlign.center,
                  style:
                      ManaType.note,
                ),
                const SizedBox(height: ManaSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _update,
                        child: ManaText.raw(ref.t('update')),
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
                            : ManaText.raw(ref.t('confirm')),
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

class _BfNotGrantedBlock extends ConsumerWidget {
  const _BfNotGrantedBlock();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('access_not_yet_granted')),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              ref.t('owner_not_assigned_bf'),
              textAlign: TextAlign.center,
              style: ManaType.note,
            ),
          ],
        ),
      ),
    );
  }
}

class _BfUpdateRequestedBlock extends ConsumerWidget {
  const _BfUpdateRequestedBlock();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_outlined,
                size: 40, color: ManaColors.statusWarn),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('waiting_on_owner')),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              ref.t('bf_dispute_sent'),
              textAlign: TextAlign.center,
              style: ManaType.note,
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
        SnackBar(content: ManaText.raw(ref.t('select_at_least_one_area'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = widget.state.enabledAreas;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('select_operating_areas')),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
          ref.t('only_areas_enabled'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        if (areas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
            child: Center(
              child: ManaText.raw(
                  ref.t('no_areas_enabled'),
                  style: ManaType.secondary),
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
              : ManaText.raw(ref.t('start_business_session')),
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
        SnackBar(content: ManaText.raw(ref.t('could_not_change_area'))),
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
            ManaText.raw(ref.t('change_area'),
                style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('adding_area_note'),
              style: ManaType.note,
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
              title: ref.t('business_status'),
              rows: [
                (ref.t('business_date'), _date.format(d.businessDate)),
                (ref.t('assigned_route'), d.assignedRoute),
                (ref.t('pending_drafts'), '${d.pendingDraftsCount}'),
                (ref.t('pending_settlement'), d.pendingSettlement ? ref.t('yes') : ref.t('no')),
                (ref.t('todays_target'), manaRupees(d.todaysTarget)),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            _SectionCard(
              title: ref.t('today_summary'),
              rows: [
                (ref.t('customers_assigned'), '${d.customersAssigned}'),
                (ref.t('customers_visited'), '${d.customersVisited}'),
                (ref.t('customers_remaining'), '${d.customersRemaining}'),
                (ref.t('cash'), manaRupees(d.collectionsCash)),
                (ref.t('upi'), manaRupees(d.collectionsUpi)),
                (ref.t('bank'), manaRupees(d.collectionsBank)),
                (ref.t('cheque'), manaRupees(d.collectionsCheque)),
                (ref.t('mixed'), manaRupees(d.collectionsMixed)),
                (
                  ref.t('todays_collections_total'),
                  manaRupees(d.todaysCollectionsTotal)
                ),
                (ref.t('loans_issued'), '${d.loansIssued}'),
                (ref.t('pending_collections'), '${d.pendingCollections}'),
                (ref.t('skipped_customers'), '${d.skippedCustomers}'),
                (ref.t('short'), manaRupees(d.shortAmount)),
                (ref.t('excess'), manaRupees(d.excessAmount)),
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
                title: ref.t('attention_required'),
                rows: [
                  (ref.t('pending_drafts'), '${d.pendingDraftsCount}'),
                  (ref.t('pending_settlement'), d.pendingSettlement ? ref.t('yes') : ref.t('no')),
                  (ref.t('pending_customer_requests'), '${d.pendingCustomerRequests}'),
                  (
                    ref.t('pending_extension_requests'),
                    '${d.pendingExtensionRequests}'
                  ),
                  (ref.t('pending_route_changes'), '${d.pendingRouteChanges}'),
                  (ref.t('pending_messages'), '${d.pendingMessages}'),
                ],
                accent: ManaColors.statusWarn,
              ),
            const SizedBox(height: ManaSpacing.md),
            _LiveActivity(entries: d.liveActivity),
            const SizedBox(height: ManaSpacing.md),
            _CompensationSection(key: compensationKey, d: d),
            const SizedBox(height: ManaSpacing.md),
            _SectionCard(
              title: ref.t('workspace_information'),
              rows: [
                (ref.t('business_name'), d.businessName),
                (ref.t('owner'), d.ownerName),
                (ref.t('membership_status'), d.membershipStatus),
                (ref.t('permission_profile'), d.permissionProfile),
                (ref.t('last_sync'), _time.format(d.lastSync)),
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
            ManaText.raw(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accent ?? ManaColors.textPrimary)),
            const SizedBox(height: ManaSpacing.sm),
            // Neither side was flexible — a long real value (business name,
            // assigned route, owner name) overflowed the Row outright, not
            // just at a scaled-up text size, and a first fix that only made
            // the value flexible still overflowed on long LABELS
            // ("Pending Customer Requests") at larger text scales. Both
            // sides now Flexible: the label may wrap to a second line, the
            // value stays single-line with an ellipsis safety net.
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: ManaText.raw(r.$1,
                            style: TextStyle(
                                fontSize: 13, color: ManaColors.textSecondary)),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      Flexible(
                        child: ManaText.raw(r.$2,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
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
class _CompensationSection extends ConsumerWidget {
  final AgentDashboardData d;
  const _CompensationSection({super.key, required this.d});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('my_compensation'),
                style: ManaType.strong),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(ref.t('read_only_set_by_owner'),
                style:
                    ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            ...[
              (ref.t('fixed_salary'), manaRupees(d.fixedSalary)),
              (
                ref.t('salary_cycle'),
                d.salaryCycleStatus.isEmpty ? '—' : d.salaryCycleStatus
              ),
              (ref.t('daily_allowance'), manaRupees(d.dailyAllowance)),
              if (d.profitSharePercent != null)
                (ref.t('profit_share'), '${d.profitSharePercent}%'),
              (ref.t('advances_deducted'), manaRupees(d.advancesDeducted)),
              (ref.t('shorts_deducted'), manaRupees(d.shortsDeducted)),
              (ref.t('pending_salary'), manaRupees(d.pendingSalary)),
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
              ManaText.raw(ref.t('salary_history'),
                  style: ManaType.smallStrong),
              const SizedBox(height: ManaSpacing.xs),
              ...d.salaryHistory.take(6).map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ManaText.raw(h.cycleLabel,
                            style: TextStyle(
                                fontSize: 13, color: ManaColors.textSecondary)),
                        ManaText.raw(manaRupees(h.amount),
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

class _QuickActions extends ConsumerWidget {
  final Set<String> visible;
  final String businessId;
  final String agentId;
  const _QuickActions(
      {required this.visible, required this.businessId, required this.agentId});

  // Hidden modules remain fully absent — not shown greyed-out — per
  // OW-001's Quick Actions pattern that this screen mirrors. `$1` is the
  // STABLE dispatch key — matched against `visible` (built from
  // agent_dashboard_state.dart's `tilePermissionColumns`, which is keyed on
  // these exact English strings) and against the switch below. It must
  // never be swapped for translated text, or this reintroduces the exact
  // vocabulary-mismatch bug that file's own comment documents fixing.
  // `$3` is the translation key for what's actually shown on screen.
  static const _all = [
    ('Collection Mode', Icons.payments_outlined, 'collection_mode'),
    ('Customer List', Icons.people_outline, 'customer_list'),
    ('Loan Distribution', Icons.request_page_outlined, 'loan_distribution'),
    ('Draft Transactions', Icons.drafts_outlined, 'draft_transactions'),
    ('Settlement', Icons.receipt_long_outlined, 'settlement'),
    ('Notifications', Icons.notifications_outlined, 'notifications'),
    ('Universal Search', Icons.search, 'universal_search'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _all.where((a) => visible.contains(a.$1)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('quick_actions'),
                style: ManaType.strong),
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
                        label: ref.t(a.$3),
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
                              // Merged into Collection Mode — see the drawer
                              // action above for why.
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => AgentCollectionModeScreen(
                                        businessId: businessId)),
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
            ManaText.raw(label,
                textAlign: TextAlign.center,
                style: ManaType.small),
          ],
        ),
      ),
    );
  }
}

class _LiveActivity extends ConsumerWidget {
  final List<AgentLiveActivityEntry> entries;
  const _LiveActivity({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('live_activity'),
                style: ManaType.strong),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              ManaText.raw(ref.t('nothing_yet_today'),
                  style:
                      ManaType.note)
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
                                style: ManaType.small)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

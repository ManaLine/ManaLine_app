import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_member_roster.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_stat_strip.dart';
import '../../../design/components/mana_amount.dart' show manaRupees;
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';
import '../state/business_management_state.dart' show businessManagementApiServiceProvider, OperatingAreaSummary;
import '../state/investor_state.dart' show ProfitShareDeclaration;
import '../../../shared/document_viewer.dart';

/// OW-002 — Workforce Management (Agents). List view is the default landing
/// state; Register/Add Existing are sub-flows reached from the header;
/// selecting a row drills into the tabbed Agent Profile (C6).
class WorkforceManagementScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// Open straight onto this agent's profile once the roster has loaded.
  ///
  /// Set by the "Disputed Opening BF" card on the Owner dashboard. Without it
  /// that card dropped the Owner on this list — no mention of the dispute and
  /// no way to correct the float — which reads as the card doing nothing.
  final String? focusAgentId;

  const WorkforceManagementScreen({
    super.key,
    required this.businessId,
    this.focusAgentId,
  });

  @override
  ConsumerState<WorkforceManagementScreen> createState() =>
      _WorkforceManagementScreenState();
}

class _WorkforceManagementScreenState
    extends ConsumerState<WorkforceManagementScreen> {
  // Search field belongs to ManaMemberRoster now.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(workforceProvider.notifier).load(widget.businessId);
      if (!mounted) return;

      // After the load, not before: the agent has to be in the list before
      // their profile can be opened. Silently staying on the roster is the
      // right failure — better than a blank profile — if they are not.
      final target = widget.focusAgentId;
      if (target == null) return;
      final agents = ref.read(workforceProvider).agents;
      final match = agents.where((a) => a.agentId == target);
      if (match.isEmpty) return;
      if (!mounted) return;
      _openAgentProfile(context, match.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workforceProvider);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('workforce_management')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(workforceProvider.notifier).load(widget.businessId),
          child: state.loading && state.agents.isEmpty
              ? const ManaSkeletonList()
              : ManaMemberRoster(
                  heading: ref.t('agents'),
                  header: _DashboardStrip(state: state),
                  members: [
                    for (final a in state.filtered)
                      MemberEntry(
                        id: a.agentId,
                        name: a.fullName,
                        subtitle:
                            [a.mlid, a.phoneNumber].where((s) => s.isNotEmpty).join(' · '),
                        status: a.status,
                      ),
                  ],
                  filterLabels: [
                    ref.t('all'),
                    ref.t('active'),
                    ref.t('pending_invitation_status'),
                    ref.t('pending_acceptance_status'),
                    ref.t('temporarily_disabled'),
                    ref.t('suspended'),
                  ],
                  statusValues: const [
                    'Active',
                    'Pending Invitation',
                    'Pending Acceptance',
                    'Temporarily Disabled',
                    'Suspended',
                  ],
                  statusValue: state.statusFilter,
                  onStatusChanged: (v) =>
                      ref.read(workforceProvider.notifier).setStatusFilter(v),
                  onSearchChanged: (v) =>
                      ref.read(workforceProvider.notifier).setSearchQuery(v),
                  searchHint: ref.t('search_by_name_or_mlid'),
                  // A failed load must not look like "no agents" — state.error
                  // was captured but never shown before this screen surfaced
                  // it, making an RLS/query failure indistinguishable from a
                  // business that genuinely has none. The distinction is kept
                  // by swapping the empty message.
                  emptyLabel: state.error != null
                      ? ref.t('could_not_load_agents').replaceAll('{error}', '${state.error}')
                      : ref.t('no_agents_match_view'),
                  addLabel: ref.t('add_agent'),
                  addActions: [
                    MemberAction(
                      label: ref.t('register_agent'),
                      icon: Icons.person_add_alt_1_outlined,
                      onTap: () => _openRegisterNewAgent(context),
                    ),
                    MemberAction(
                      label: ref.t('add_existing_agent'),
                      icon: Icons.badge_outlined,
                      onTap: () => _openAddExistingAgent(context),
                    ),
                    // An agent who worked for this business before it joined
                    // MANA LINE, so has no MANA LINE ID yet.
                    MemberAction(
                      label: ref.t('pre_existing_agent'),
                      icon: Icons.history_edu_outlined,
                      onTap: () => context
                          .push('/ow-014?type=agent', extra: widget.businessId)
                          .then((_) =>
                              ref.read(workforceProvider.notifier).load(widget.businessId)),
                    ),
                  ],
                  rowBuilder: (entry, _) {
                    final a = state.filtered.firstWhere((x) => x.agentId == entry.id);
                    return _AgentRow(agent: a, onTap: () => _openAgentProfile(context, a));
                  },
                ),
        ),
      ),
    );
  }

  void _openRegisterNewAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RegisterNewAgentSheet(businessId: widget.businessId),
    ).then((_) => ref.read(workforceProvider.notifier).load(widget.businessId));
  }

  void _openAddExistingAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddExistingAgentSheet(businessId: widget.businessId),
    ).then((_) => ref.read(workforceProvider.notifier).load(widget.businessId));
  }

  void _openAgentProfile(BuildContext context, AgentSummary agent) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AgentProfileScreen(businessId: widget.businessId, agent: agent),
      ),
    );
  }
}

// --- C2 Dashboard summary strip ------------------------------------------

class _DashboardStrip extends ConsumerWidget {
  final WorkforceState state;
  const _DashboardStrip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = <(String, int, ManaStatus)>[
      (ref.t('active'), state.totalActive, ManaStatus.good),
      (ref.t('pending_invitation_status'), state.pendingInvitations, ManaStatus.warn),
      (ref.t('pending_acceptance_status'), state.pendingAcceptance, ManaStatus.warn),
      (ref.t('disabled'), state.disabled, ManaStatus.neutral),
      (ref.t('suspended'), state.suspended, ManaStatus.bad),
      (ref.t('removed'), state.removed, ManaStatus.neutral),
    ];
    return ManaStatStrip(
      valueFontSize: 20,
      stats: [
        for (final (label, value, status) in stats)
          ManaStat(value: '$value', label: label, status: status),
      ],
    );
  }
}

// --- C3 Agent List row ------------------------------------------------

class _AgentRow extends StatelessWidget {
  final AgentSummary agent;
  final VoidCallback onTap;
  const _AgentRow({required this.agent, required this.onTap});

  ManaStatus get _statusKind => switch (agent.status) {
        'Active' => ManaStatus.good,
        'Pending Invitation' || 'Pending Acceptance' => ManaStatus.warn,
        'Suspended' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 40),
        title: ManaText.raw(agent.fullName,
            style: ManaType.emphasis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ManaText.raw(
            '${agent.mlid} · ${agent.phoneNumber}',
            style:
                ManaType.note,
          ),
        ),
        // ManaTrailingStatus, not a bare pill: this row threw "Trailing widget
        // consumes the entire tile width" at 1.3x once the filter dropdown
        // freed the vertical space for it to be laid out.
        trailing: ManaTrailingStatus(label: agent.status, status: _statusKind),
        onTap: onTap,
      ),
    );
  }
}

// --- C4 Register New Agent (sub-flow) ------------------------------------

class _RegisterNewAgentSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _RegisterNewAgentSheet({required this.businessId});

  @override
  ConsumerState<_RegisterNewAgentSheet> createState() =>
      _RegisterNewAgentSheetState();
}

class _RegisterNewAgentSheetState
    extends ConsumerState<_RegisterNewAgentSheet> {
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  String? _gender;
  bool _submitting = false;

  // Global Rules Guide ADDENDUM v4: Aadhaar is mandatory at registration
  // for all roles except OW-014's pre-existing-member migration path —
  // Agent registration here is a normal registration path, so it applies.
  bool get _canSubmit =>
      _fullName.text.trim().length >= 2 &&
      _fatherHusband.text.trim().length >= 2 &&
      _gender != null &&
      _mobile.text.trim().length == 10 &&
      _aadhaar.text.trim().length == 12;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(workforceProvider.notifier).registerNewAgent(
            businessId: widget.businessId,
            fullName: _fullName.text.trim(),
            fatherHusbandName: _fatherHusband.text.trim(),
            genderDigit: _gender!,
            mobileNumber: _mobile.text.trim(),
            aadhaarNumber: _aadhaar.text.trim(),
          );
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('agent_registered_note'))),
      );
    }
  }

  // Disposed with the State that owns them. Each controller holds a
  // listener list and a ChangeNotifier; a State that never disposes them
  // leaks one set per visit.
  @override
  void dispose() {
    _fullName.dispose();
    _fatherHusband.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ListView(
            controller: scrollController,
            children: [
              ManaText.raw(ref.t('register_new_agent'),
                  style: ManaType.sheetTitle),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('register_new_agent_note'),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.lg),
              TextField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: '${ref.t("full_name")} *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _fatherHusband,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: '${ref.t("father_husband_name")} *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: InputDecoration(labelText: '${ref.t("gender")} *'),
                items: [
                  DropdownMenuItem(value: '1', child: ManaText.raw(ref.t('male'))),
                  DropdownMenuItem(value: '0', child: ManaText.raw(ref.t('female'))),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: InputDecoration(labelText: '${ref.t("mobile_number")} *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _aadhaar,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration:
                    InputDecoration(labelText: '${ref.t("aadhaar_number")} *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.lg),
              ElevatedButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('register_and_send_invitation')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- C5 Add Existing Agent (sub-flow) ------------------------------------

class _AddExistingAgentSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _AddExistingAgentSheet({required this.businessId});

  @override
  ConsumerState<_AddExistingAgentSheet> createState() =>
      _AddExistingAgentSheetState();
}

class _AddExistingAgentSheetState
    extends ConsumerState<_AddExistingAgentSheet> {
  final _mlid = TextEditingController();
  AgentSummary? _found;
  bool _searching = false;
  bool _adding = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(workforceProvider.notifier)
          .searchByMlid(_mlid.text.trim());
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = result;
    });
  }

  Future<void> _add() async {
    if (_found == null) return;
    setState(() => _adding = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(workforceProvider.notifier).addExistingAgent(
            businessId: widget.businessId,
            personId: _found!.personId!,
          );
    });
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok == true && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('invitation_sent_note'))),
      );
    }
  }

  // Disposed with the State that owns them. Each controller holds a
  // listener list and a ChangeNotifier; a State that never disposes them
  // leaks one set per visit.
  @override
  void dispose() {
    _mlid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('add_existing_agent'),
                style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('add_existing_agent_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mlid,
                    decoration: InputDecoration(labelText: ref.t('enter_mlid')),
                    onChanged: (_) => setState(() => _found = null),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: (_mlid.text.trim().isNotEmpty && !_searching)
                      ? _search
                      : null,
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.lg),
            if (_found != null)
              Card(
                child: ListTile(
                  leading:
                      const ManaVerificationRing(isVerified: true, size: 40),
                  title: ManaText.raw(_found!.fullName),
                  subtitle: ManaText.raw(_found!.mlid),
                  trailing: ElevatedButton(
                    onPressed: _adding ? null : _add,
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ManaText.raw(ref.t('add')),
                  ),
                ),
              )
            else if (_mlid.text.trim().isNotEmpty && !_searching)
              ManaText.raw(
                  ref.t('no_match_found_note'),
                  style:
                      ManaType.note),
          ],
        ),
      ),
    );
  }
}

// --- C6 Agent Profile (tabbed drill-in) ------------------------------------

class AgentProfileScreen extends ConsumerWidget {
  final String businessId;
  final AgentSummary agent;
  const AgentProfileScreen(
      {super.key, required this.businessId, required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(agentProfileProvider(agent.agentId));

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(agent.fullName),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: ref.t('overview')),
              Tab(text: ref.t('permissions')),
              Tab(text: ref.t('compensation')),
              Tab(text: ref.t('areas')),
              Tab(text: ref.t('documents')),
              Tab(text: ref.t('audit')),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (status) => _changeStatus(context, ref, status),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'Active', child: ManaText.raw(ref.t('reactivate'))),
                PopupMenuItem(
                    value: 'Temporarily Disabled', child: ManaText.raw(ref.t('disable'))),
                PopupMenuItem(value: 'Suspended', child: ManaText.raw(ref.t('suspend'))),
                PopupMenuItem(value: 'Removed', child: ManaText.raw(ref.t('remove'))),
              ],
            ),
          ],
        ),
        body: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(ref.t('could_not_load_profile').replaceAll('{error}', '$e'),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (profile) => TabBarView(
            children: [
              _OverviewTab(agent: agent, businessId: businessId),
              _PermissionsTab(agentId: agent.agentId, profile: profile),
              _CompensationTab(
                  agentId: agent.agentId, businessId: businessId, profile: profile),
              _AreasTab(businessId: businessId, agent: agent, profile: profile),
              _DocumentsTab(agentId: agent.agentId),
              const _AuditTab(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('confirm_status_change_title').replaceAll('{status}', status)),
        content: ManaText.raw(
            ref.t('change_status_note').replaceAll('{name}', agent.fullName).replaceAll('{status}', status)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: ManaText.raw(ref.t('confirm'))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(workforceProvider.notifier).updateAgentStatus(
            businessId: businessId,
            agentId: agent.agentId,
            status: status,
          );
    });
  }
}

class _OverviewTab extends ConsumerStatefulWidget {
  final AgentSummary agent;
  final String businessId;
  const _OverviewTab({required this.agent, required this.businessId});

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  /// Three distinct states, deliberately not collapsed into one int:
  /// still loading, no BF row at all (the agent cannot lend yet), and a
  /// real figure. Rendering "₹0" for "no row" would tell the Owner the
  /// agent is merely empty when in fact they have never been set up.
  bool _loadingBf = true;
  int? _bf;
  String? _bfError;

  /// The Agent's open ask, if there is one. Loaded with the float because the
  /// two are read together: "they have nothing, and they have asked for
  /// 30,000" is one fact, and splitting it across two loads would show the
  /// Owner half of it first.
  PendingBfRequest? _request;

  AgentSummary get agent => widget.agent;

  @override
  void initState() {
    super.initState();
    _loadBf();
  }

  Future<void> _loadBf() async {
    setState(() {
      _loadingBf = true;
      _bfError = null;
    });
    try {
      final membershipId = agent.membershipId;
      if (membershipId == null) {
        // A search result that is not yet a membership has no float.
        if (mounted) setState(() => _loadingBf = false);
        return;
      }
      final api = ref.read(ownerApiServiceProvider);
      final bf = await api.readAgentBf(agentMembershipId: membershipId);
      final request = await api.readPendingBfRequest(membershipId: membershipId);
      if (mounted) {
        setState(() {
          _bf = bf;
          _request = request;
          _loadingBf = false;
        });
      }
    } catch (e) {
      // Never show a number we could not read as if it were zero.
      if (mounted) {
        setState(() {
          _bfError = e.toString();
          _loadingBf = false;
        });
      }
    }
  }

  String _bfLabel(WidgetRef ref) {
    if (_loadingBf) return '…';
    if (_bfError != null) return ref.t('could_not_read');
    if (agent.membershipId == null) return '—';
    if (_bf == null) return ref.t('no_bf_granted_yet');
    return '₹${_bf!}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(
            child: ManaText.raw(agent.fullName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18))),
        Center(
            child: ManaText.raw(agent.mlid,
                style: ManaType.secondary)),
        const SizedBox(height: ManaSpacing.lg),
        _infoRow(ref.t('phone_number'), agent.phoneNumber),
        _infoRow(ref.t('status'), agent.status),
        _infoRow(ref.t('business_access'), agent.businessAccess),
        _infoRow(ref.t('current_route'), agent.currentRoute ?? '—'),
        _infoRow(ref.t('cash_in_hand_bf'), _bfLabel(ref)),
        // The agent cannot be lent against without a float, and
        // create_loan_with_bf_check refuses with INSUFFICIENT_FLOAT until
        // the Owner tops them up. This is where that happens.
        if (_request != null) _requestBanner(),
        if (agent.membershipId != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _openTopUpSheet,
                icon: const Icon(Icons.add, size: 18),
                label: ManaText.raw(ref.t('add_bf')),
              ),
            ),
          ),
        _infoRow(ref.t('todays_collections_label'),
            '₹${agent.todaysCollections.toStringAsFixed(0)}'),
        _infoRow(ref.t('todays_loans'), '₹${agent.todaysLoans.toStringAsFixed(0)}'),
        _infoRow(
            ref.t('joined_date'), DateFormat('d MMM yyyy').format(agent.joinedDate)),
        // "Never" is only truthful for your OWN record — devices is
        // self-only under RLS, so for any other agent the Owner simply
        // cannot see it. Saying "Never" there asserts something false.
        _infoRow(
            ref.t('last_login'),
            agent.lastLogin != null
                ? DateFormat('d MMM yyyy, hh:mm a').format(agent.lastLogin!)
                : agent.lastLoginVisible
                    ? ref.t('never')
                    : ref.t('not_visible')),
      ],
    );
  }

  /// The Agent asked. Until this existed the ask happened over the phone and
  /// the app knew nothing about it -- so the Owner had no record that anyone
  /// was waiting, and the Agent had no way to tell being refused from being
  /// forgotten.
  Widget _requestBanner() {
    final r = _request!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.statusWarnFaint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(
            '${agent.fullName} asked for ${manaRupees(r.requestedAmount)}',
            style: ManaType.strong,
          ),
          if (r.reason != null && r.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            ManaText.raw(r.reason!, style: ManaType.note),
          ],
          const SizedBox(height: ManaSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _decide(approve: false),
                  child: ManaText.raw(ref.t('reject')),
                ),
              ),
              const SizedBox(width: ManaSpacing.sm),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _decide(approve: true),
                  child: ManaText.raw(ref.t('accept')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decide({required bool approve}) async {
    final r = _request!;
    int? amount;

    if (approve) {
      // Prefilled with what was asked, and editable: the Owner is the one who
      // knows what is in the till, and granting a smaller figure is a normal
      // answer rather than a refusal.
      final controller = TextEditingController(text: '${r.requestedAmount}');
      amount = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          String? error;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              // Scrolls if it does not fit -- see ow_011_day_closure.dart.
              scrollable: true,
              title: ManaText.raw(ref.t('add_bf')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(
                    '${agent.fullName} asked for ${manaRupees(r.requestedAmount)}. '
                    'Send this amount, or change it.',
                    style: TextStyle(color: ManaColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      labelText: ref.t('amount'),
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: ManaText.raw(ref.t('cancel'))),
                ElevatedButton(
                  onPressed: () {
                    final v = int.tryParse(controller.text.trim());
                    if (v == null || v <= 0) {
                      setDialogState(() => error = ref.t('enter_whole_rupee_amount'));
                      return;
                    }
                    Navigator.pop(dialogContext, v);
                  },
                  child: ManaText.raw(ref.t('send')),
                ),
              ],
            ),
          );
        },
      );
      if (amount == null || !mounted) return;
    }

    // NetworkErrorHandler surfaces the server's own refusal -- notably
    // "Owner BF is only X, cannot top up Y", which is the answer the Owner
    // needs rather than a generic failure.
    final done = await NetworkErrorHandler.run(context, () async {
      await ref.read(ownerApiServiceProvider).decideBfRequest(
            requestId: r.requestId,
            approve: approve,
            amount: amount,
          );
      return true;
    });
    if (done != true || !mounted) return;

    // Re-read rather than adjusting locally: the float the Agent now holds is
    // the server's figure, and this screen has been wrong about money before
    // by assuming its own arithmetic agreed.
    await _loadBf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(approve
          ? 'Sent ${manaRupees(amount!)} to ${agent.fullName}.'
          : 'Rejected. ${agent.fullName} has been told.'),
    ));
  }

  Future<void> _openTopUpSheet() async {
    final controller = TextEditingController();
    final granted = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            // Scrolls if it does not fit -- see ow_011_day_closure.dart.
            scrollable: true,
            title: ManaText.raw(ref.t('add_bf')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(
                    ref.t('move_cash_to_float_note').replaceAll('{name}', agent.fullName),
                    style: TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13)),
                const SizedBox(height: ManaSpacing.md),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    labelText: ref.t('amount'),
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: ManaText.raw(ref.t('cancel'))),
              ElevatedButton(
                onPressed: () {
                  // Whole rupees only — every money column is numeric(_,0),
                  // so paise cannot be stored and must not be accepted.
                  final amount = int.tryParse(controller.text.trim());
                  if (amount == null || amount <= 0) {
                    setDialogState(() => error = ref.t('enter_whole_rupee_amount'));
                    return;
                  }
                  Navigator.pop(dialogContext, amount);
                },
                child: ManaText.raw(ref.t('add')),
              ),
            ],
          ),
        );
      },
    );

    if (granted == null || !mounted) return;

    // NetworkErrorHandler surfaces the server's own refusal — notably
    // "Owner BF is only X, cannot top up Y" — instead of a raw exception.
    final newFloat = await NetworkErrorHandler.run(context, () async {
      return ref.read(workforceProvider.notifier).grantAgentBf(
            businessId: widget.businessId,
            agentMembershipId: agent.membershipId!,
            amount: granted,
          );
    });

    if (!mounted || newFloat == null) return;
    // Trust the server's returned float, not local arithmetic.
    setState(() => _bf = newFloat);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: ManaText.raw(ref
              .t('bf_added_note')
              .replaceAll('{granted}', '$granted')
              .replaceAll('{name}', agent.fullName)
              .replaceAll('{newFloat}', '$newFloat'))),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: ManaText.raw(label,
                    style: TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13))),
            Flexible(
              child: ManaText.raw(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _PermissionsTab extends ConsumerStatefulWidget {
  final String agentId;
  final AgentProfile profile;
  const _PermissionsTab({required this.agentId, required this.profile});

  @override
  ConsumerState<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<_PermissionsTab> {
  // OFF by default per BR-236 pattern (can_apply_penalty, can_record_expenses,
  // ADDENDUM v7 §13) — every toggle here defaults to whatever the profile
  // reports, never silently assumed ON.
  // BUG FIXED: this listed 4 of the 20 permission columns, and NONE of the
  // ones AG-001 actually gates its Quick Action tiles on. The agent
  // dashboard shows "Collection Mode" only when can_access_collection_mode
  // is true, "Customer List" on can_view_customers, and so on — columns
  // the Owner had no way to switch on. That is why an agent had no way to
  // reach Collection Mode no matter what was granted here.
  //
  // Grouped, because 14 flat toggles is a wall. Order follows what an
  // Owner decides first: can they work at all, then what can they touch.
  static const _groups = <String, Map<String, String>>{
    'daily work': {
      'can_view_dashboard': 'perm_can_view_dashboard',
      'can_access_collection_mode': 'perm_can_access_collection_mode',
      'can_collect_payments': 'perm_can_collect_payments',
      'can_perform_day_settlement': 'perm_can_perform_day_settlement',
    },
    'customers & loans': {
      'can_view_customers': 'perm_can_view_customers',
      'can_create_customer': 'perm_can_create_customer',
      'can_edit_customer_contact': 'perm_can_edit_customer_contact',
      'can_issue_loans': 'perm_can_issue_loans',
      'can_apply_penalty': 'perm_can_apply_penalty',
    },
    'money & records': {
      'can_record_expenses': 'perm_can_record_expenses',
      'can_record_cheti': 'perm_can_record_cheti',
      'can_transfer_collections': 'perm_can_transfer_collections',
      'can_create_drafts': 'perm_can_create_drafts',
      'can_edit_own_drafts': 'perm_can_edit_own_drafts',
      'can_cancel_own_drafts': 'perm_can_cancel_own_drafts',
      'can_upload_documents': 'perm_can_upload_documents',
      'can_add_remarks': 'perm_can_add_remarks',
    },
    'pre-existing records': {
      // Deliberately its own group and its own column, not folded into
      // can_issue_loans: entering a pre-existing loan restates the opening
      // cash position, which is a heavier power than lending today.
      'can_migrate_records': 'perm_can_migrate_records',
    },
    'deleting': {
      // Its own group, and last, because it is the heaviest thing an agent
      // can be given: deleting a ledger record rewrites a past day's
      // closing balance and every day after it. Recoverable for 30 days,
      // then not. OFF by default like every other flag here.
      'can_delete_records': 'perm_can_delete_records',
    },
    'visibility': {
      'can_view_reports': 'perm_can_view_reports',
      'can_export_reports': 'perm_can_export_reports',
      'can_view_investor_info': 'perm_can_view_investor_info',
    },
  };

  static const _groupKeys = {
    'daily work': 'group_daily_work',
    'customers & loans': 'group_customers_loans',
    'money & records': 'group_money_records',
    'pre-existing records': 'group_pre_existing_records',
    'deleting': 'group_deleting',
    'visibility': 'group_visibility',
  };

  /// The working copy the switches render from. May hold unsaved edits.
  late Map<String, bool> _permissions;

  /// The last server state we adopted. Kept so [didUpdateWidget] can tell a
  /// genuine server change apart from an unrelated parent rebuild.
  late Map<String, bool> _serverPermissions;

  @override
  void initState() {
    super.initState();
    _serverPermissions = Map.of(widget.profile.permissions);
    _permissions = Map.of(widget.profile.permissions);
  }

  // BUG FIXED: _permissions was seeded in initState ONLY, with no
  // didUpdateWidget. This State outlives the widget, so once the provider
  // refetched after a save and rebuilt this tab with a fresh AgentProfile,
  // the switches kept rendering the PRE-save map. Observed on device: a
  // toggle showing OFF while the database already held true. On a screen that
  // decides what an agent is allowed to do with money, showing a value the
  // server does not hold is the same failure class as a confident wrong
  // amount — the Owner cannot tell granted from not.
  //
  // Resyncing UNCONDITIONALLY here would be a worse bug: any unrelated parent
  // rebuild would silently revert toggles the Owner had just flipped and not
  // yet saved. So adopt the incoming map only when the SERVER value actually
  // changed (our own save landing, or another device editing the same agent),
  // which leaves in-progress edits alone.
  @override
  void didUpdateWidget(covariant _PermissionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A different agent entirely — never carry one agent's edits onto another.
    if (oldWidget.agentId != widget.agentId) {
      _serverPermissions = Map.of(widget.profile.permissions);
      _permissions = Map.of(widget.profile.permissions);
      return;
    }

    if (!mapEquals(widget.profile.permissions, _serverPermissions)) {
      _serverPermissions = Map.of(widget.profile.permissions);
      _permissions = Map.of(widget.profile.permissions);
    }
  }

  Future<void> _save() async {
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(agentProfileProvider(widget.agentId).notifier)
          .updatePermissions(_permissions);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(
          ref.t('permissions_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        for (final group in _groups.entries) ...[
          ManaText.raw(ref.t(_groupKeys[group.key]!),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: ManaColors.textSecondary)),
          ...group.value.entries.map((e) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(ref.t(e.value)),
                value: _permissions[e.key] ?? false,
                onChanged: (v) => setState(() => _permissions[e.key] = v),
              )),
          const SizedBox(height: ManaSpacing.md),
        ],
        const SizedBox(height: ManaSpacing.sm),
        ElevatedButton(
            onPressed: _save, child: ManaText.raw(ref.t('save_permissions'))),
      ],
    );
  }
}

class _CompensationTab extends ConsumerStatefulWidget {
  final String agentId;
  final String businessId;
  final AgentProfile profile;
  const _CompensationTab({
    required this.agentId,
    required this.businessId,
    required this.profile,
  });

  @override
  ConsumerState<_CompensationTab> createState() => _CompensationTabState();
}

class _CompensationTabState extends ConsumerState<_CompensationTab> {
  late final _salary = TextEditingController(
      text:
          widget.profile.currentCompensation?.fixedSalary.toStringAsFixed(0) ??
              '');
  late final _allowance = TextEditingController(
      text: widget.profile.currentCompensation?.dailyAllowance
              ?.toStringAsFixed(0) ??
          '');
  late final _profitShare = TextEditingController(
      text: widget.profile.currentCompensation?.profitSharePercent
              ?.toStringAsFixed(1) ??
          '');
  String _cycle = 'Monthly';

  Future<void> _save() async {
    final salary = int.tryParse(_salary.text.trim());
    if (salary == null) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(agentProfileProvider(widget.agentId).notifier)
          .setCompensation(
            fixedSalary: salary, // whole rupees (M8)
            salaryCycle: _cycle,
            dailyAllowance: int.tryParse(_allowance.text.trim()),
            profitSharePercent: double.tryParse(_profitShare.text.trim()),
          );
    });
  }

  // Disposed with the State that owns them. Each controller holds a
  // listener list and a ChangeNotifier; a State that never disposes them
  // leaks one set per visit.
  @override
  void dispose() {
    _salary.dispose();
    _allowance.dispose();
    _profitShare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('compensation_structure'),
            style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _salary,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t('fixed_salary_amount_field')),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _cycle,
          decoration: InputDecoration(labelText: ref.t('salary_cycle_field')),
          items: [
            DropdownMenuItem(value: 'Monthly', child: ManaText.raw(ref.t('monthly'))),
            DropdownMenuItem(
                value: 'Custom', child: ManaText.raw(ref.t('custom_owner_defined'))),
          ],
          onChanged: (v) => setState(() => _cycle = v ?? 'Monthly'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _allowance,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: ref.t('daily_allowance_optional')),
        ),
        const SizedBox(height: ManaSpacing.xs),
        // CORRECTED: this used to read "reduced from final salary (BR-046)",
        // which CALC BR-068's rewrite explicitly supersedes. Daily Allowance
        // is paid same-day in cash and has ZERO relationship to Payable
        // Salary — it never appears in that formula in any form. Leaving the
        // old wording would have told the Owner the opposite of what the
        // salary engine now does.
        ManaText.raw(
            ref.t('daily_allowance_note'),
            style: ManaType.note),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _profitShare,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: ref.t('profit_share_percent_optional')),
        ),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
            ref.t('profit_share_reference_note'),
            style: ManaType.note),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
            onPressed: _save,
            child: ManaText.raw(ref.t('save_creates_new_history_entry'))),
        const Divider(height: ManaSpacing.xxl),
        // BR-232 requires this action on the Agent Profile as well as the
        // Investor Profile. Only the Investor side had it, so an Agent's
        // profit share could be agreed and never actually paid out.
        _AgentProfitShareSection(
            agentId: widget.agentId,
            businessId: widget.businessId,
            profile: widget.profile),
        const Divider(height: ManaSpacing.xxl),
        ManaText.raw(ref.t('compensation_history'),
            style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        if (widget.profile.compensationHistory.isEmpty)
          ManaText.raw(ref.t('no_history_yet'),
              style: ManaType.secondary)
        else
          ...widget.profile.compensationHistory.map((c) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(
                    '₹${c.fixedSalary.toStringAsFixed(0)} · ${c.salaryCycle}'),
                subtitle: ManaText.raw(
                    ref.t('effective_note').replaceAll('{date}', DateFormat('d MMM yyyy').format(c.effectiveDate))),
              )),
      ],
    );
  }
}

/// CALC BR-232 — "Distribute Profit Share" on the Agent Profile.
///
/// Manual entry only. The Owner types the actual rupee amount; the % on the
/// compensation structure above is never multiplied against anything, and
/// there is no system-calculated base (not Net Profit, not Gross
/// Collections). Declaration and payment are separate events (BR-058), so a
/// declared row shows a "mark paid" action once and cannot be declared
/// twice by accident.
class _AgentProfitShareSection extends ConsumerStatefulWidget {
  final String agentId;
  final String businessId;
  final AgentProfile profile;
  const _AgentProfitShareSection({
    required this.agentId,
    required this.businessId,
    required this.profile,
  });

  @override
  ConsumerState<_AgentProfitShareSection> createState() => _AgentProfitShareSectionState();
}

class _AgentProfitShareSectionState extends ConsumerState<_AgentProfitShareSection> {
  List<ProfitShareDeclaration> _declarations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref
          .read(ownerApiServiceProvider)
          .fetchAgentProfitShareDeclarations(agentId: widget.agentId);
      if (!mounted) return;
      setState(() {
        _declarations = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _declare() async {
    final amount = TextEditingController();
    final remarks = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          // Scrolls if it does not fit -- see ow_011_day_closure.dart.
          scrollable: true,
          title: ManaText.raw(ref.t('distribute_profit_share')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(
                ref.t('distribute_profit_share_note'),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${ref.t("amount")} *'),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: remarks,
                decoration: InputDecoration(labelText: ref.t('remarks')),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: ManaText.raw(ref.t('cancel'))),
            FilledButton(
              onPressed: double.tryParse(amount.text.trim()) != null
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: ManaText.raw(ref.t('declare')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(ownerApiServiceProvider).declareAgentProfitShare(
            businessId: widget.businessId,
            agentId: widget.agentId,
            amount: int.parse(amount.text.trim()), // whole rupees (M8)
            profitSharePercent: widget.profile.currentCompensation?.profitSharePercent ?? 0,
            remarks: remarks.text.trim().isEmpty ? null : remarks.text.trim(),
          );
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _markPaid(ProfitShareDeclaration d) async {
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(ownerApiServiceProvider).payAgentProfitShare(declarationId: d.declarationId);
      return true;
    });
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('profit_share_distribution'),
            style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _declare,
            icon: const Icon(Icons.add, size: 18),
            label: ManaText.raw(ref.t('distribute_profit_share')),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(ManaSpacing.md),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (_declarations.isEmpty)
          ManaText.raw(ref.t('nothing_distributed_yet'),
              style: ManaType.note)
        else
          ..._declarations.map((d) => Card(
                child: ListTile(
                  title: ManaText.raw('₹${d.declaredAmount.toStringAsFixed(0)}'),
                  subtitle: ManaText.raw(
                      '${DateFormat('d MMM yyyy').format(d.businessDate)}'
                      '${d.remarks == null ? '' : ' · ${d.remarks}'}',
                      style: ManaType.small),
                  trailing: d.status == 'Declared'
                      ? FilledButton(
                          onPressed: () => _markPaid(d),
                          child: ManaText.raw(ref.t('mark_paid')),
                        )
                      : ManaStatusPill(label: ref.t('paid'), status: ManaStatus.good),
                ),
              )),
      ],
    );
  }
}

class _AreasTab extends ConsumerWidget {
  final String businessId;
  final AgentSummary agent;
  final AgentProfile profile;
  const _AreasTab({required this.businessId, required this.agent, required this.profile});

  // BUG FIXED this pass: "add village" was onPressed: () {} — this is
  // the same assign-area-to-agent capability built for OW-012's
  // Operating Areas tab (business_management_state.dart's
  // assignOperatingAreaToAgent), just reached from the Agent's own
  // profile instead. Reused rather than duplicated.
  Future<void> _addVillage(BuildContext context, WidgetRef ref) async {
    if (agent.membershipId == null) return;
    final areas = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessManagementApiServiceProvider).fetchOperatingAreas(businessId: businessId);
    });
    if (areas == null || !context.mounted) return;
    final selected = await showModalBottomSheet<OperatingAreaSummary>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VillagePickerSheet(areas: areas),
    );
    if (selected == null || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).assignOperatingAreaToAgent(
            businessId: businessId,
            operatingAreaId: selected.operatingAreaId,
            agentId: agent.agentId,
            agentMembershipId: agent.membershipId!,
          );
      return ref.read(agentProfileProvider(agent.agentId).notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(
          ref.t('areas_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        if (profile.assignedAreas.isEmpty)
          ManaText.raw(ref.t('no_areas_assigned_yet'),
              style: ManaType.secondary)
        else
          ...profile.assignedAreas.map((a) => Card(
                child: ListTile(
                  leading: Icon(Icons.location_on_outlined,
                      color: ManaColors.brand),
                  title: ManaText.raw(a),
                ),
              )),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
            onPressed: () => _addVillage(context, ref),
            icon: const Icon(Icons.add),
            label: ManaText.raw(ref.t('add_village'))),
      ],
    );
  }
}

class _VillagePickerSheet extends ConsumerWidget {
  final List<OperatingAreaSummary> areas;
  const _VillagePickerSheet({required this.areas});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ManaText.raw(ref.t('select_village'), style: ManaType.cardTitle),
          ),
          if (areas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(ref.t('no_operating_areas_note'),
                  style: ManaType.note),
            )
          else
            ...areas.map((a) => ListTile(
                  leading: Icon(Icons.location_on_outlined, color: ManaColors.brand),
                  title: ManaText.raw(a.name),
                  subtitle: ManaText.raw(
                      '${a.villagesLabel}\n'
                      '${a.isUnassigned ? ref.t('no_agent_assigned') : ref.t('agents_label_note').replaceAll('{names}', a.assignedAgentsLabel)}',
                      style: ManaType.note),
                  isThreeLine: true,
                  onTap: () => Navigator.of(context).pop(a),
                )),
          const SizedBox(height: ManaSpacing.md),
        ],
      ),
    );
  }
}

class _DocumentsTab extends ConsumerWidget {
  final String agentId;
  const _DocumentsTab({required this.agentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Labels match customer_document_type_enum's real values (this table
    // reuses Module 3's enum) — 'Employment Documents'/'Identity Proof'
    // aren't real values, they never had (and never could have had) a
    // matching document.
    return DocumentsListView(
      expectedTypes: const ['Photo', 'Aadhaar', 'Address Proof', 'Other Documents'],
      fetchDocuments: () => ref.read(ownerApiServiceProvider).fetchAgentDocuments(agentId: agentId),
    );
  }
}

class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          ref.t('audit_note'),
          textAlign: TextAlign.center,
          style: ManaType.secondary,
        ),
      ),
    );
  }
}

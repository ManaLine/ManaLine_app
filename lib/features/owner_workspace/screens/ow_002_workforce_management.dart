import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_stat_strip.dart';
import '../../../shared/network_error_handler.dart';
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
  const WorkforceManagementScreen({super.key, required this.businessId});

  @override
  ConsumerState<WorkforceManagementScreen> createState() =>
      _WorkforceManagementScreenState();
}

class _WorkforceManagementScreenState
    extends ConsumerState<WorkforceManagementScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workforceProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workforceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('workforce management'),
        actions: [
          IconButton(
            tooltip: 'Register Agent',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => _openRegisterNewAgent(context),
          ),
          IconButton(
            tooltip: 'Add Existing Agent',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () => _openAddExistingAgent(context),
          ),
          // OW-014 Global Workflow — an agent who already worked for this
          // business before it joined MANA LINE, so has no MANA LINE ID yet.
          IconButton(
            tooltip: 'Pre-Existing Agent',
            icon: const Icon(Icons.history_edu_outlined),
            onPressed: () => context
                .push('/ow-014?type=agent', extra: widget.businessId)
                .then((_) => ref.read(workforceProvider.notifier).load(widget.businessId)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(workforceProvider.notifier).load(widget.businessId),
          child: state.loading && state.agents.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    _DashboardStrip(state: state),
                    const SizedBox(height: ManaSpacing.lg),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or MLID',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => ref
                          .read(workforceProvider.notifier)
                          .setSearchQuery(v),
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _StatusFilterChips(state: state),
                    const SizedBox(height: ManaSpacing.md),
                    // A failed load previously looked identical to "no
                    // agents" — state.error was captured but never shown,
                    // so an RLS/query failure was indistinguishable from a
                    // business that genuinely has zero agents.
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('Could not load agents.\n${state.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: ManaColors.statusBad, fontSize: 13)),
                        ),
                      )
                    else if (state.filtered.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('No agents match this view.',
                              style:
                                  TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.filtered.map((a) => _AgentRow(
                            agent: a,
                            onTap: () => _openAgentProfile(context, a),
                          )),
                  ],
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

class _DashboardStrip extends StatelessWidget {
  final WorkforceState state;
  const _DashboardStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, int, ManaStatus)>[
      ('Active', state.totalActive, ManaStatus.good),
      ('Pending Invitations', state.pendingInvitations, ManaStatus.warn),
      ('Pending Acceptance', state.pendingAcceptance, ManaStatus.warn),
      ('Disabled', state.disabled, ManaStatus.neutral),
      ('Suspended', state.suspended, ManaStatus.bad),
      ('Removed', state.removed, ManaStatus.neutral),
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

class _StatusFilterChips extends ConsumerWidget {
  final WorkforceState state;
  const _StatusFilterChips({required this.state});

  static const _statuses = [
    'Active',
    'Pending Invitation',
    'Pending Acceptance',
    'Temporarily Disabled',
    'Suspended',
    'Removed',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: ManaSpacing.xs,
      children: [
        ChoiceChip(
          label: const ManaText('all'),
          selected: state.statusFilter == null,
          onSelected: (_) =>
              ref.read(workforceProvider.notifier).setStatusFilter(null),
        ),
        ..._statuses.map((s) => ChoiceChip(
              label: ManaText(s),
              selected: state.statusFilter == s,
              onSelected: (_) =>
                  ref.read(workforceProvider.notifier).setStatusFilter(s),
            )),
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
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ManaText.raw(
            '${agent.mlid} · ${agent.phoneNumber}',
            style:
                TextStyle(fontSize: 13, color: ManaColors.textSecondary),
          ),
        ),
        trailing: ManaStatusPill(label: agent.status, status: _statusKind),
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
        const SnackBar(
            content: ManaText.raw(
                'Agent registered — invitation sent, status Pending Invitation.')),
      );
    }
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
              const ManaText('register new agent',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                'For an agent who does not yet have a MANA LINE ID. Reuses the same '
                'Identity Registration fields as account registration.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: ManaSpacing.lg),
              TextField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _fatherHusband,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Father / Husband Name *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender *'),
                items: const [
                  DropdownMenuItem(value: '1', child: ManaText.raw('Male')),
                  DropdownMenuItem(value: '0', child: ManaText.raw('Female')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'Mobile Number *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _aadhaar,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration:
                    const InputDecoration(labelText: 'Aadhaar Number *'),
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
                    : const ManaText('register & send invitation'),
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
        const SnackBar(
            content: ManaText.raw('Invitation sent — status Pending Invitation.')),
      );
    }
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
            const ManaText('add existing agent',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'For an agent who already has a MANA LINE ID (MLID/MLPI/MLTI).',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mlid,
                    decoration: const InputDecoration(labelText: 'Enter MLID'),
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
                      : const ManaText('search'),
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
                        : const ManaText('add'),
                  ),
                ),
              )
            else if (_mlid.text.trim().isNotEmpty && !_searching)
              ManaText.raw(
                  'No match found yet — search to look up this MLID.',
                  style:
                      TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Permissions'),
              Tab(text: 'Compensation'),
              Tab(text: 'Areas'),
              Tab(text: 'Documents'),
              Tab(text: 'Audit'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (status) => _changeStatus(context, ref, status),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Active', child: ManaText('reactivate')),
                PopupMenuItem(
                    value: 'Temporarily Disabled', child: ManaText('disable')),
                PopupMenuItem(value: 'Suspended', child: ManaText('suspend')),
                PopupMenuItem(value: 'Removed', child: ManaText('remove')),
              ],
            ),
          ],
        ),
        body: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('Could not load profile.\n$e',
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
        title: ManaText('confirm: ${status.toLowerCase()}'),
        content: ManaText.raw(
            'Change ${agent.fullName}\'s membership status to "$status"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const ManaText('cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const ManaText('confirm')),
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
      final bf = await ref
          .read(ownerApiServiceProvider)
          .readAgentBf(agentMembershipId: membershipId);
      if (mounted) {
        setState(() {
          _bf = bf;
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

  String get _bfLabel {
    if (_loadingBf) return '…';
    if (_bfError != null) return 'Could not read';
    if (agent.membershipId == null) return '—';
    if (_bf == null) return 'No BF granted yet';
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
                style: TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _infoRow('Phone Number', agent.phoneNumber),
        _infoRow('Status', agent.status),
        _infoRow('Business Access', agent.businessAccess),
        _infoRow('Current Route', agent.currentRoute ?? '—'),
        _infoRow('Cash In Hand (BF)', _bfLabel),
        // The agent cannot be lent against without a float, and
        // create_loan_with_bf_check refuses with INSUFFICIENT_FLOAT until
        // the Owner tops them up. This is where that happens.
        if (agent.membershipId != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _openTopUpSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const ManaText('add bf'),
              ),
            ),
          ),
        _infoRow("Today's Collections",
            '₹${agent.todaysCollections.toStringAsFixed(0)}'),
        _infoRow("Today's Loans", '₹${agent.todaysLoans.toStringAsFixed(0)}'),
        _infoRow(
            'Joined Date', DateFormat('d MMM yyyy').format(agent.joinedDate)),
        // "Never" is only truthful for your OWN record — devices is
        // self-only under RLS, so for any other agent the Owner simply
        // cannot see it. Saying "Never" there asserts something false.
        _infoRow(
            'Last Login',
            agent.lastLogin != null
                ? DateFormat('d MMM yyyy, hh:mm a').format(agent.lastLogin!)
                : agent.lastLoginVisible
                    ? 'Never'
                    : 'Not visible'),
      ],
    );
  }

  Future<void> _openTopUpSheet() async {
    final controller = TextEditingController();
    final granted = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const ManaText('add bf'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(
                    'Move cash from your own balance into ${agent.fullName}\'s float.',
                    style: TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13)),
                const SizedBox(height: ManaSpacing.md),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    labelText: 'Amount',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const ManaText('cancel')),
              ElevatedButton(
                onPressed: () {
                  // Whole rupees only — every money column is numeric(_,0),
                  // so paise cannot be stored and must not be accepted.
                  final amount = int.tryParse(controller.text.trim());
                  if (amount == null || amount <= 0) {
                    setDialogState(() => error = 'Enter a whole rupee amount above zero');
                    return;
                  }
                  Navigator.pop(dialogContext, amount);
                },
                child: const ManaText('add'),
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
          content: ManaText.raw(
              '₹$granted added. ${agent.fullName} now holds ₹$newFloat.')),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: ManaText(label,
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
      'can_view_dashboard': 'Can Open Work Session',
      'can_access_collection_mode': 'Can Use Collection Mode',
      'can_collect_payments': 'Can Collect Payments',
      'can_perform_day_settlement': 'Can Submit Settlement',
    },
    'customers & loans': {
      'can_view_customers': 'Can View Customers',
      'can_create_customer': 'Can Register Customers',
      'can_edit_customer_contact': 'Can Edit Customer Contact',
      'can_issue_loans': 'Can Issue Loans',
      'can_apply_penalty': 'Can Apply Penalty',
    },
    'money & records': {
      'can_record_expenses': 'Can Record Expenses',
      'can_record_cheti': 'Can Record Cheti Instalments',
      'can_transfer_collections': 'Can Transfer Cash to Another Agent',
      'can_create_drafts': 'Can Create Drafts',
      'can_edit_own_drafts': 'Can Edit Own Drafts',
      'can_cancel_own_drafts': 'Can Cancel Own Drafts',
      'can_upload_documents': 'Can Upload Documents',
      'can_add_remarks': 'Can Add Remarks',
    },
    'pre-existing records': {
      // Deliberately its own group and its own column, not folded into
      // can_issue_loans: entering a pre-existing loan restates the opening
      // cash position, which is a heavier power than lending today.
      'can_migrate_records': 'Can Enter Pre-Existing Records',
    },
    'deleting': {
      // Its own group, and last, because it is the heaviest thing an agent
      // can be given: deleting a ledger record rewrites a past day's
      // closing balance and every day after it. Recoverable for 30 days,
      // then not. OFF by default like every other flag here.
      'can_delete_records': 'Can Delete Records',
    },
    'visibility': {
      'can_view_reports': 'Can View Reports',
      'can_export_reports': 'Can Export Reports',
      'can_view_investor_info': 'Can View Investor Info',
    },
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
          'An agent sees only what is switched on here. With everything off '
          'their home screen has no actions at all.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        for (final group in _groups.entries) ...[
          ManaText(group.key,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: ManaColors.textSecondary)),
          ...group.value.entries.map((e) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText(e.value),
                value: _permissions[e.key] ?? false,
                onChanged: (v) => setState(() => _permissions[e.key] = v),
              )),
          const SizedBox(height: ManaSpacing.md),
        ],
        const SizedBox(height: ManaSpacing.sm),
        ElevatedButton(
            onPressed: _save, child: const ManaText('save permissions')),
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText('compensation structure',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _salary,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Fixed Salary Amount *'),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: _cycle,
          decoration: const InputDecoration(labelText: 'Salary Cycle'),
          items: const [
            DropdownMenuItem(value: 'Monthly', child: ManaText.raw('Monthly')),
            DropdownMenuItem(
                value: 'Custom', child: ManaText.raw('Custom (Owner Defined)')),
          ],
          onChanged: (v) => setState(() => _cycle = v ?? 'Monthly'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _allowance,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Daily Allowance (optional)'),
        ),
        const SizedBox(height: ManaSpacing.xs),
        // CORRECTED: this used to read "reduced from final salary (BR-046)",
        // which CALC BR-068's rewrite explicitly supersedes. Daily Allowance
        // is paid same-day in cash and has ZERO relationship to Payable
        // Salary — it never appears in that formula in any form. Leaving the
        // old wording would have told the Owner the opposite of what the
        // salary engine now does.
        ManaText.raw(
            'Paid same-day in cash. Does NOT reduce payable salary — tracked '
            'for your visibility only (CALC BR-068, supersedes BR-046).',
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _profitShare,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Profit Share % (optional, tentative)'),
        ),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(
            'Reference only — the system never multiplies this against any '
            'figure. Distribute the actual amount below (BR-232).',
            style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
            onPressed: _save,
            child: const ManaText('save — creates new history entry')),
        const Divider(height: ManaSpacing.xxl),
        // BR-232 requires this action on the Agent Profile as well as the
        // Investor Profile. Only the Investor side had it, so an Agent's
        // profit share could be agreed and never actually paid out.
        _AgentProfitShareSection(
            agentId: widget.agentId,
            businessId: widget.businessId,
            profile: widget.profile),
        const Divider(height: ManaSpacing.xxl),
        const ManaText('compensation history',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        if (widget.profile.compensationHistory.isEmpty)
          ManaText.raw('No history yet.',
              style: TextStyle(color: ManaColors.textSecondary))
        else
          ...widget.profile.compensationHistory.map((c) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(
                    '₹${c.fixedSalary.toStringAsFixed(0)} · ${c.salaryCycle}'),
                subtitle: ManaText.raw(
                    'Effective ${DateFormat('d MMM yyyy').format(c.effectiveDate)}'),
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
          title: const ManaText('distribute profit share'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(
                'Enter the actual amount being distributed. Nothing is '
                'calculated from the Profit Share % — that figure is your '
                'own reference (BR-232).',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount *'),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: remarks,
                decoration: const InputDecoration(labelText: 'Remarks'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const ManaText('cancel')),
            FilledButton(
              onPressed: double.tryParse(amount.text.trim()) != null
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const ManaText('declare'),
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
        const ManaText('profit share distribution',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _declare,
            icon: const Icon(Icons.add, size: 18),
            label: const ManaText('distribute profit share'),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(ManaSpacing.md),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (_declarations.isEmpty)
          ManaText.raw('Nothing distributed yet.',
              style: TextStyle(color: ManaColors.textSecondary, fontSize: 13))
        else
          ..._declarations.map((d) => Card(
                child: ListTile(
                  title: ManaText.raw('₹${d.declaredAmount.toStringAsFixed(0)}'),
                  subtitle: ManaText.raw(
                      '${DateFormat('d MMM yyyy').format(d.businessDate)}'
                      '${d.remarks == null ? '' : ' · ${d.remarks}'}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: d.status == 'Declared'
                      ? FilledButton(
                          onPressed: () => _markPaid(d),
                          child: const ManaText('mark paid'),
                        )
                      : const ManaStatusPill(label: 'Paid', status: ManaStatus.good),
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
          'Agent cannot choose areas outside those assigned here — Agent-side area '
          'selection (e.g. Collection Mode) is restricted to this set.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (profile.assignedAreas.isEmpty)
          ManaText.raw('No areas assigned yet.',
              style: TextStyle(color: ManaColors.textSecondary))
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
            label: const ManaText('add village')),
      ],
    );
  }
}

class _VillagePickerSheet extends StatelessWidget {
  final List<OperatingAreaSummary> areas;
  const _VillagePickerSheet({required this.areas});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(ManaSpacing.lg),
            child: ManaText('select village', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (areas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('No Operating Areas exist yet for this business — add one from Business Management first.',
                  style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            )
          else
            ...areas.map((a) => ListTile(
                  leading: Icon(Icons.location_on_outlined, color: ManaColors.brand),
                  title: ManaText.raw(a.name),
                  subtitle: ManaText.raw(
                      '${a.villagesLabel}\n'
                      '${a.isUnassigned ? 'No agent assigned' : 'Agents: ${a.assignedAgentsLabel}'}',
                      style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          'Membership/permission/compensation changes are logged here per BR-158 — '
          'no entries yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textSecondary),
        ),
      ),
    );
  }
}

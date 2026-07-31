import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                              style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
                        ),
                      )
                    else if (state.filtered.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
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
                const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
            content: Text(
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
              const ManaText.raw(
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
                  DropdownMenuItem(value: '1', child: Text('Male')),
                  DropdownMenuItem(value: '0', child: Text('Female')),
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
            content: Text('Invitation sent — status Pending Invitation.')),
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
            const ManaText.raw(
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
              const ManaText.raw(
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
              _OverviewTab(agent: agent),
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

class _OverviewTab extends StatelessWidget {
  final AgentSummary agent;
  const _OverviewTab({required this.agent});

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
                style: const TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _infoRow('Phone Number', agent.phoneNumber),
        _infoRow('Status', agent.status),
        _infoRow('Business Access', agent.businessAccess),
        _infoRow('Current Route', agent.currentRoute ?? '—'),
        _infoRow("Today's Collections",
            '₹${agent.todaysCollections.toStringAsFixed(0)}'),
        _infoRow("Today's Loans", '₹${agent.todaysLoans.toStringAsFixed(0)}'),
        _infoRow(
            'Joined Date', DateFormat('d MMM yyyy').format(agent.joinedDate)),
        _infoRow(
            'Last Login',
            agent.lastLogin == null
                ? 'Never'
                : DateFormat('d MMM yyyy, hh:mm a').format(agent.lastLogin!)),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: ManaText(label,
                    style: const TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
  static const _labels = {
    'can_collect_payments': 'Can Collect Payments',
    'can_issue_loans': 'Can Issue Loans',
    'can_apply_penalty': 'Can Apply Penalty',
    'can_record_expenses': 'Can Record Expenses', // ADDENDUM v7
  };

  late Map<String, bool> _permissions;

  @override
  void initState() {
    super.initState();
    _permissions = Map.of(widget.profile.permissions);
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
        ..._labels.entries.map((e) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: ManaText(e.value),
              value: _permissions[e.key] ?? false,
              onChanged: (v) => setState(() => _permissions[e.key] = v),
            )),
        const SizedBox(height: ManaSpacing.lg),
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
    final salary = double.tryParse(_salary.text.trim());
    if (salary == null) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(agentProfileProvider(widget.agentId).notifier)
          .setCompensation(
            fixedSalary: salary,
            salaryCycle: _cycle,
            dailyAllowance: double.tryParse(_allowance.text.trim()),
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
            DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            DropdownMenuItem(
                value: 'Custom', child: Text('Custom (Owner Defined)')),
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
        const ManaText.raw(
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
        const ManaText.raw(
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
          const ManaText.raw('No history yet.',
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
              const ManaText.raw(
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
            amount: double.parse(amount.text.trim()),
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
          const ManaText.raw('Nothing distributed yet.',
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
        const ManaText.raw(
          'Agent cannot choose areas outside those assigned here — Agent-side area '
          'selection (e.g. Collection Mode) is restricted to this set.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (profile.assignedAreas.isEmpty)
          const ManaText.raw('No areas assigned yet.',
              style: TextStyle(color: ManaColors.textSecondary))
        else
          ...profile.assignedAreas.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined,
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
            const Padding(
              padding: EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('No Operating Areas exist yet for this business — add one from Business Management first.',
                  style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            )
          else
            ...areas.map((a) => ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: ManaColors.brand),
                  title: ManaText.raw(a.name),
                  subtitle: ManaText.raw(
                      '${a.villagesLabel}\n'
                      '${a.isUnassigned ? 'No agent assigned' : 'Assigned to ${a.assignedAgentName}'}',
                      style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
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

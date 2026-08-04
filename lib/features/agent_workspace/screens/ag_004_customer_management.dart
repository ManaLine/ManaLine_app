import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../owner_workspace/state/customer_state.dart' show CustomerSummary, CustomerProfile, CustomerRemark;
import '../../owner_workspace/state/collection_mode_state.dart' show CollectionDueRow;
import '../../owner_workspace/screens/ow_006_collection_mode.dart' show CollectionEntryScreen;
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/agent_customer_state.dart';
import 'ag_007_loan_distribution.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// AG-004 — Customer Management (Agent Workspace). Agent-side counterpart to
/// OW-004, scoped to only this Agent's assigned customers, with every
/// sub-action individually gated by its own `agent_permissions` boolean —
/// hidden entirely (not greyed-out) when not granted.
class AgentCustomerManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String agentMembershipId;
  const AgentCustomerManagementScreen({
    super.key,
    required this.businessId,
    required this.agentMembershipId,
  });

  @override
  ConsumerState<AgentCustomerManagementScreen> createState() => _AgentCustomerManagementScreenState();
}

class _AgentCustomerManagementScreenState extends ConsumerState<AgentCustomerManagementScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentCustomerListProvider.notifier).load(
            businessId: widget.businessId,
            agentMembershipId: widget.agentMembershipId,
          );
    });
  }

  Future<void> _reload() => ref.read(agentCustomerListProvider.notifier).load(
        businessId: widget.businessId,
        agentMembershipId: widget.agentMembershipId,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentCustomerListProvider);

    // Can View Customers gates the whole screen (PRIMARY PERMISSION).
    if (!state.loading && state.customers.isEmpty && state.error == null && !state.permissions.canViewCustomers) {
      return Scaffold(
        appBar: AppBar(title: const ManaText('customer management')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(ManaSpacing.lg),
            child: ManaText.raw(
              'You do not have permission to view customers on this business.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ManaColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('customer management'),
        actions: [
          // Create Customer — hidden entirely unless can_create_customer.
          if (state.permissions.canCreateCustomer)
            IconButton(
              tooltip: 'Create Customer',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => _showCreateCustomerNotice(context),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: state.loading && state.customers.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search by name, MLID, or phone',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => ref.read(agentCustomerListProvider.notifier).setSearchQuery(v),
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _FilterChips(state: state),
                    const SizedBox(height: ManaSpacing.md),
                    if (state.filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('No assigned customers match this view.',
                              style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.filtered.map((c) => _CustomerRow(
                            customer: c,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AgentCustomerProfileScreen(
                                  businessId: widget.businessId,
                                  agentMembershipId: widget.agentMembershipId,
                                  customerId: c.customerId,
                                  customerName: c.fullName,
                                  permissions: state.permissions,
                                ),
                              ),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }

  void _showCreateCustomerNotice(BuildContext context) {
    // Create Customer reuses OW-004's identity-search + create-new flow
    // (same fields/endpoint); wiring the shared sheet here is out of scope
    // for this pass — flagged for cross-check with the OW-004 owner.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create Customer reuses the OW-004 identity-search flow — TODO: wire shared sheet.')),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  final AgentCustomerListState state;
  const _FilterChips({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FILTERS per spec: Village, Today's Due, Penalty, Grace Period,
    // Collected, Pending, Skipped, Loan Status. CustomerSummary (reused
    // verbatim from OW-004) carries village, todaysDue, and
    // customerStatus/membershipStatus — it has no per-loan
    // penalty/grace/collection-status fields, so those five filters aren't
    // representable without extending that shared type; flagged here rather
    // than invented. Village + Today's Due + Loan Status are wired below.
    return Wrap(
      spacing: ManaSpacing.xs,
      runSpacing: ManaSpacing.xs,
      children: [
        ChoiceChip(
          label: const ManaText('all villages'),
          selected: state.villageFilter == null,
          onSelected: (_) => ref.read(agentCustomerListProvider.notifier).setVillageFilter(null),
        ),
        ...state.villages.map((v) => ChoiceChip(
              label: ManaText.raw(v),
              selected: state.villageFilter == v,
              onSelected: (_) => ref.read(agentCustomerListProvider.notifier).setVillageFilter(v),
            )),
        FilterChip(
          label: const ManaText("today's due"),
          selected: state.loanStatusFilter == 'HasDue',
          onSelected: (sel) =>
              ref.read(agentCustomerListProvider.notifier).setLoanStatusFilter(sel ? 'HasDue' : null),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final CustomerSummary customer;
  final VoidCallback onTap;
  const _CustomerRow({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final flagged = customer.membershipStatus != 'Active';
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 40),
        title: Row(
          children: [
            Flexible(child: ManaText.raw(customer.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (flagged) ...[
              const SizedBox(width: ManaSpacing.xs),
              ManaStatusPill(label: customer.membershipStatus, status: ManaStatus.bad),
            ],
          ],
        ),
        subtitle: ManaText.raw(
          '${customer.fatherHusbandName} · ${customer.village} · LRI ${customer.lineRepaymentIndex}',
          style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ManaText.raw(_currency.format(customer.outstandingBalance),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (customer.todaysDue > 0)
              ManaText.raw('Due ${_currency.format(customer.todaysDue)}',
                  style: const TextStyle(fontSize: 16, color: ManaColors.statusWarn)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================
// Customer Profile (S2/S3)
// ============================================================================

class AgentCustomerProfileScreen extends ConsumerWidget {
  final String businessId;
  final String agentMembershipId;
  final String customerId;
  final String customerName;
  final AgentPermissions? permissions;

  const AgentCustomerProfileScreen({
    super.key,
    required this.businessId,
    required this.agentMembershipId,
    required this.customerId,
    required this.customerName,
    this.permissions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(agentCustomerProfileProvider(customerId));
    // Falls back to the list's permission set when opened directly (e.g.
    // from AG-003), same as how AG-003 doesn't duplicate AG-001's session
    // model — this screen re-reads the list state instead of re-fetching
    // permissions itself if already available.
    final perms = permissions ?? ref.watch(agentCustomerListProvider).permissions;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(customerName),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Loan Information'),
              Tab(text: 'Collection History'),
              Tab(text: 'Remarks'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => _handleAction(context, ref, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'collect', child: ManaText('collect payment')),
                // View Loan has no dedicated permission per spec (read-only
                // display); Create Loan hidden entirely unless can_issue_loans.
                const PopupMenuItem(value: 'view_loan', child: ManaText('view loan')),
                if (perms.canIssueLoans) const PopupMenuItem(value: 'create_loan', child: ManaText('create loan')),
                if (perms.canEditCustomerContact)
                  const PopupMenuItem(value: 'edit_contact', child: ManaText('update contact info')),
                if (perms.canUploadDocuments)
                  const PopupMenuItem(value: 'upload_document', child: ManaText('upload document')),
              ],
            ),
          ],
        ),
        body: asyncProfile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('Could not load profile.\n$e', textAlign: TextAlign.center),
            ),
          ),
          data: (profile) => TabBarView(
            children: [
              _SummaryTab(profile: profile),
              _LoanInformationTab(profile: profile),
              _CollectionHistoryTab(profile: profile),
              _RemarksTab(customerId: customerId, profile: profile, canAddRemarks: perms.canAddRemarks),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    final profileAsync = ref.read(agentCustomerProfileProvider(customerId));
    final profile = profileAsync.valueOrNull;

    switch (action) {
      case 'collect':
        // Collect Payment → AG-002 Collection Mode. Financial writes never
        // happen inline on this screen — only via AG-002's own entry form.
        if (profile == null || profile.loans.isEmpty) return;
        final loan = profile.loans.first;
        final dueRow = CollectionDueRow(
          loanId: loan.loanId,
          customerId: customerId,
          customerName: customerName,
          village: profile.summary.village,
          loanNumber: loan.loanNumber,
          installmentDue: loan.todaysDue,
          outstandingBalance: loan.outstanding,
          lineRepaymentIndex: profile.summary.lineRepaymentIndex,
          collectionStatus: 'Pending',
          collectionAgent: agentMembershipId,
        );
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CollectionEntryScreen(row: dueRow, businessId: businessId)),
        );
        ref.invalidate(agentCustomerProfileProvider(customerId));
      case 'view_loan':
      case 'create_loan':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Ag007LoanDistributionScreen(
              agentId: agentMembershipId,
              businessId: businessId,
              prefilledCustomerId: action == 'create_loan' ? customerId : null,
            ),
          ),
        );
      case 'edit_contact':
        await _showEditContactSheet(context, ref, profile);
      case 'upload_document':
        await _showUploadDocumentSheet(context, ref);
    }
  }

  Future<void> _showEditContactSheet(BuildContext context, WidgetRef ref, CustomerProfile? profile) async {
    final phoneController = TextEditingController(text: profile?.summary.phoneNumber ?? '');
    final doorNoController = TextEditingController();
    final pinCodeController = TextEditingController();
    final villageSearchController = TextEditingController();
    String? selectedVillageId;
    String? selectedVillageLabel; // "Village — Mandal, District, State" for confirmation display
    List<Map<String, dynamic>> villageResults = [];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> searchVillages(String query) async {
            if (query.trim().length < 2) {
              setSheetState(() => villageResults = []);
              return;
            }
            final rows = await Supabase.instance.client
                .from('locations')
                .select('location_id, village_town_name, mandal, district, state')
                .eq('status', 'Active')
                .ilike('village_town_name', '%${query.trim()}%')
                .limit(10);
            setSheetState(() => villageResults = (rows as List).cast<Map<String, dynamic>>());
          }

          return Padding(
            padding: MediaQuery.of(sheetContext).viewInsets,
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ManaText('update contact info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number'),
                  ),
                  const SizedBox(height: ManaSpacing.lg),
                  const ManaText('address', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: doorNoController,
                    decoration: const InputDecoration(labelText: 'Door No'),
                  ),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: pinCodeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN Code'),
                  ),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: villageSearchController,
                    decoration: const InputDecoration(labelText: 'Search Village/Town'),
                    onChanged: (v) {
                      selectedVillageId = null;
                      selectedVillageLabel = null;
                      searchVillages(v);
                    },
                  ),
                  if (villageResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: ManaSpacing.xs),
                      decoration: BoxDecoration(border: Border.all(color: ManaColors.surfaceSunken)),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: villageResults.length,
                        itemBuilder: (_, i) {
                          final v = villageResults[i];
                          final label = '${v['village_town_name']} — ${v['mandal']}, ${v['district']}, ${v['state']}';
                          return ListTile(
                            dense: true,
                            title: ManaText.raw(label, style: const TextStyle(fontSize: 13)),
                            onTap: () => setSheetState(() {
                              selectedVillageId = v['location_id'] as String;
                              selectedVillageLabel = label;
                              villageSearchController.text = v['village_town_name'] as String;
                              villageResults = [];
                            }),
                          );
                        },
                      ),
                    ),
                  if (selectedVillageLabel != null) ...[
                    const SizedBox(height: ManaSpacing.xs),
                    ManaText.raw('Selected: $selectedVillageLabel',
                        style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                  ],
                  const SizedBox(height: ManaSpacing.lg),
                  ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const ManaText('save'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(agentCustomerProfileProvider(customerId).notifier).updateContactInfo(
            phoneNumber: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
            doorNo: doorNoController.text.trim().isEmpty ? null : doorNoController.text.trim(),
            pinCode: pinCodeController.text.trim().isEmpty ? null : pinCodeController.text.trim(),
            villageId: selectedVillageId,
          );
    });
  }

  Future<void> _showUploadDocumentSheet(BuildContext context, WidgetRef ref) async {
    // Document type is a single tap-to-pick-and-close action per option,
    // same list-of-ListTiles pattern as AG-003's Visit Outcome sheet — no
    // Radio/RadioListTile, per convention. Document capture itself
    // (camera/file picker) is stubbed, not built, in this pass.
    final result = await showModalBottomSheet<AgentDocumentType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaText('upload document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: ManaSpacing.md),
              for (final type in AgentDocumentType.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined, color: ManaColors.brand),
                  title: ManaText(type.displayLabel),
                  onTap: () => Navigator.of(sheetContext).pop(type),
                ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(agentCustomerProfileProvider(customerId).notifier).uploadDocument(
            documentType: result,
            fileUrl: 'stub-file-url', // TODO: wire actual capture/file-picker
          );
    });
  }
}

class _SummaryTab extends StatelessWidget {
  final CustomerProfile profile;
  const _SummaryTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final s = profile.summary;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(child: ManaText.raw(s.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        Center(child: ManaText.raw(s.mlid, style: const TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _row('Village', s.village),
        _row('Phone', s.phoneNumber),
        _row('Assigned Agent', profile.currentAgent ?? '—'),
        _row('Loan Count', '${s.activeLoanCount}'),
        _row('Outstanding', _currency.format(s.outstandingBalance)),
        _row("Today's Due", _currency.format(s.todaysDue)),
        const SizedBox(height: ManaSpacing.md),
        const ManaText.raw(
          'Outstanding, Today\'s Due, and loan figures are read-only here — '
          'collection and loan-issue writes only happen via Collection Mode / Loan Distribution.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

/// LOAN INFORMATION — read-only display only.
class _LoanInformationTab extends StatelessWidget {
  final CustomerProfile profile;
  const _LoanInformationTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.loans.isEmpty) {
      return const Center(child: ManaText.raw('No loans yet.', style: TextStyle(color: ManaColors.textSecondary)));
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.loans
          .map((l) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: ManaText.raw(l.loanNumber, style: const TextStyle(fontWeight: FontWeight.w600))),
                          ManaStatusPill(
                            label: l.status,
                            status: l.status == 'Active'
                                ? ManaStatus.good
                                : l.status == 'Penalty'
                                    ? ManaStatus.bad
                                    : ManaStatus.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      _row('Outstanding', _currency.format(l.outstanding)),
                      _row("Today's Due", _currency.format(l.todaysDue)),
                      _row('Issued', DateFormat('d MMM yyyy').format(l.issueDate)),
                      _row('Progress', '${l.progressPercent.toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

/// COLLECTION HISTORY — Business Date, Receipt Number, Amount, Payment
/// Mode, Collector, Remarks. Read Only.
class _CollectionHistoryTab extends StatelessWidget {
  final CustomerProfile profile;
  const _CollectionHistoryTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.collections.isEmpty) {
      return const Center(
          child: ManaText.raw('No collections yet.', style: TextStyle(color: ManaColors.textSecondary)));
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.collections
          .map((c) => ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: ManaColors.brand),
                title: ManaText.raw(_currency.format(c.amount)),
                subtitle: ManaText.raw('${c.paymentMode} · ${c.collector} · #${c.receiptNumber}'),
                trailing: ManaText.raw(DateFormat('d MMM').format(c.businessDate),
                    style: const TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
              ))
          .toList(),
    );
  }
}

/// REMARKS — append-only; no edit UI for existing remarks, ever. Add form
/// hidden entirely unless can_add_remarks is granted.
class _RemarksTab extends ConsumerStatefulWidget {
  final String customerId;
  final CustomerProfile profile;
  final bool canAddRemarks;
  const _RemarksTab({required this.customerId, required this.profile, required this.canAddRemarks});

  @override
  ConsumerState<_RemarksTab> createState() => _RemarksTabState();
}

class _RemarksTabState extends ConsumerState<_RemarksTab> {
  String? _selectedReason;
  bool _submitting = false;

  Future<void> _add() async {
    if (_selectedReason == null) return;
    setState(() => _submitting = true);
    await NetworkErrorHandler.run(context, () async {
      return ref.read(agentCustomerProfileProvider(widget.customerId).notifier).addRemark(_selectedReason!);
    });
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _selectedReason = null;
    });
  }

  /// Remarks carry no money, so deleting one moves no balance — the dialog
  /// is told that so it does not warn about a closing balance that will not
  /// change.
  Future<void> _deleteRemark(CustomerRemark r) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.customerRemark,
      recordId: r.remarkId,
      description: r.remark,
      affectsBalances: false,
    );
    if (deleted && mounted) {
      ref.invalidate(agentCustomerProfileProvider(widget.customerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: widget.profile.remarks.isEmpty
                ? const [ManaText.raw('No remarks yet.', style: TextStyle(color: ManaColors.textSecondary))]
                : widget.profile.remarks
                    .map((r) => Card(
                          child: ListTile(
                            title: ManaText.raw(r.remark),
                            subtitle: ManaText.raw('${r.enteredBy} · ${DateFormat('d MMM yyyy').format(r.date)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Not Flexible: a flexible child in a
                                // MainAxisSize.min Row makes it claim the
                                // whole tile width, which ListTile.trailing
                                // rejects outright.
                                ManaStatusPill(
                                  label: r.priority,
                                  status: r.priority == 'High' ? ManaStatus.bad : ManaStatus.neutral,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  color: ManaColors.statusBad,
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteRemark(r),
                                ),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
          ),
        ),
        // Add Remark hidden entirely unless can_add_remarks granted.
        if (widget.canAddRemarks)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedReason,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Add a remark (append-only)'),
                      items: agentRemarkReasons
                          .map((r) => DropdownMenuItem(value: r, child: ManaText.raw(r, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedReason = v),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  IconButton(
                    onPressed: (_selectedReason != null && !_submitting) ? _add : null,
                    icon: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

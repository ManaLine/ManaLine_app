import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/live_photo_upload.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/photo_compression.dart';
import '../../owner_workspace/state/customer_state.dart' show CustomerSummary, CustomerProfile, CustomerRemark;
import '../../owner_workspace/state/collection_mode_state.dart' show CollectionDueRow;
import 'ag_002_collection_mode.dart' show AgentCollectionModeScreen;
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/agent_customer_state.dart';
import 'ag_007_loan_distribution.dart';
import '../../../design/components/mana_call_button.dart';


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

  // Disposed with the State that owns them -- see the sweep note elsewhere.
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentCustomerListProvider);

    // Can View Customers gates the whole screen (PRIMARY PERMISSION).
    if (!state.loading && state.customers.isEmpty && state.error == null && !state.permissions.canViewCustomers) {
      return Scaffold(
        appBar: AppBar(title: ManaText.raw(ref.t('customer_management'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ManaText.raw(
              ref.t('no_permission_view_customers'),
              textAlign: TextAlign.center,
              style: ManaType.secondary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('customer_management')),
        actions: [
          // Create Customer — hidden entirely unless can_create_customer.
          if (state.permissions.canCreateCustomer)
            IconButton(
              tooltip: ref.t('create_customer'),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => _showCreateCustomerNotice(context),
            ),
        ],
      ),
      body: SafeArea(
        child: state.loading && state.customers.isEmpty
            ? const ManaSkeletonList()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.lg, 0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText: ref.t('search_by_name_mlid_phone'),
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (v) =>
                              ref.read(agentCustomerListProvider.notifier).setSearchQuery(v),
                        ),
                        const SizedBox(height: ManaSpacing.sm),
                        _FilterChips(state: state),
                        const SizedBox(height: ManaSpacing.md),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      // PERF: builder, not a literal children list — this list is
                      // every customer assigned to this agent, which grows
                      // unbounded over the life of a route; the old eager form
                      // built every row on every rebuild regardless of scroll
                      // position.
                      child: state.filtered.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.all(ManaSpacing.lg),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                                  child: Center(
                                    child: ManaText.raw(ref.t('no_assigned_customers_match'),
                                        style: ManaType.secondary),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(ManaSpacing.lg),
                              itemCount: state.filtered.length,
                              itemBuilder: (context, i) {
                                final c = state.filtered[i];
                                return _CustomerRow(
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
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showCreateCustomerNotice(BuildContext context) {
    // Create Customer reuses OW-004's identity-search + create-new flow
    // (same fields/endpoint); wiring the shared sheet here is out of scope
    // for this pass — flagged for cross-check with the OW-004 owner.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('create_customer_todo_note'))),
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
    // Village is a DROPDOWN, not chips. It was one ChoiceChip per village
    // with no upper bound — an agent covering a dozen villages got a dozen
    // chips wrapping across the screen before reaching the customer list,
    // and village names are user data, so their width is unbounded too.
    //
    // Today's Due stays a single toggle: it is a boolean, and a two-item
    // dropdown reading "All / Today's Due" is a worse control than a switch
    // for something you flip constantly on a collection round.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: state.villageFilter,
          isExpanded: true,
          decoration: InputDecoration(labelText: ref.t('village'), isDense: true),
          items: [
            DropdownMenuItem(
              value: null,
              child: ManaText.raw(ref.t('all_villages'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ...state.villages.map((v) => DropdownMenuItem(
                  value: v,
                  child: ManaText.raw(v, maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) => ref.read(agentCustomerListProvider.notifier).setVillageFilter(v),
        ),
        const SizedBox(height: ManaSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: ManaText.raw(ref.t('todays_due'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: state.loanStatusFilter == 'HasDue',
            onSelected: (sel) => ref
                .read(agentCustomerListProvider.notifier)
                .setLoanStatusFilter(sel ? 'HasDue' : null),
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends ConsumerWidget {
  final CustomerSummary customer;
  final VoidCallback onTap;
  const _CustomerRow({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = customer.membershipStatus != 'Active';
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 40),
        title: Row(
          children: [
            Flexible(child: ManaText.raw(customer.fullName, style: ManaType.emphasis)),
            if (flagged) ...[
              const SizedBox(width: ManaSpacing.xs),
              ManaStatusPill(label: customer.membershipStatus, status: ManaStatus.bad),
            ],
          ],
        ),
        subtitle: ManaText.raw(
          '${customer.fatherHusbandName} · ${customer.village} · LRI ${customer.lineRepaymentIndex}',
          style: ManaType.note,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ManaText.raw(manaRupees(customer.outstandingBalance),
                style: ManaType.cardTitle),
            if (customer.todaysDue > 0)
              ManaText.raw(ref.t('due_note').replaceAll('{amount}', manaRupees(customer.todaysDue)),
                  style: TextStyle(fontSize: 16, color: ManaColors.statusWarn)),
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
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: ref.t('summary_tab')),
              Tab(text: ref.t('loan_information')),
              Tab(text: ref.t('collection_history')),
              Tab(text: ref.t('remarks_tab')),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => _handleAction(context, ref, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'collect', child: ManaText.raw(ref.t('collect_payment'))),
                // View Loan has no dedicated permission per spec (read-only
                // display); Create Loan hidden entirely unless can_issue_loans.
                PopupMenuItem(value: 'view_loan', child: ManaText.raw(ref.t('view_loan'))),
                if (perms.canIssueLoans)
                  PopupMenuItem(value: 'create_loan', child: ManaText.raw(ref.t('create_loan'))),
                if (perms.canEditCustomerContact)
                  PopupMenuItem(value: 'edit_contact', child: ManaText.raw(ref.t('update_contact_info'))),
                if (perms.canUploadDocuments)
                  PopupMenuItem(value: 'upload_document', child: ManaText.raw(ref.t('upload_document'))),
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
        // The round, opened on this loan. Collection is entered in the row
        // itself now, so there is no separate entry screen to push -- and
        // arriving at the round also shows the Agent what else is due at the
        // same door, which the old screen hid.
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgentCollectionModeScreen(
                businessId: businessId, focusLoanId: dueRow.loanId),
          ),
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
                  ManaText.raw(ref.t('update_contact_info'), style: ManaType.cardTitle),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: ref.t('phone_number_plain_field')),
                  ),
                  const SizedBox(height: ManaSpacing.lg),
                  ManaText.raw(ref.t('address'), style: ManaType.emphasis),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: doorNoController,
                    decoration: InputDecoration(labelText: ref.t('door_no_field')),
                  ),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: pinCodeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: ref.t('pin_code_plain_field')),
                  ),
                  const SizedBox(height: ManaSpacing.md),
                  TextField(
                    controller: villageSearchController,
                    decoration: InputDecoration(labelText: ref.t('search_village_town_plain_field')),
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
                            title: ManaText.raw(label, style: ManaType.small),
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
                    ManaText.raw(ref.t('selected_note').replaceAll('{value}', '$selectedVillageLabel'),
                        style: ManaType.note),
                  ],
                  const SizedBox(height: ManaSpacing.lg),
                  ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: ManaText.raw(ref.t('save')),
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
    // Radio/RadioListTile, per convention.
    final result = await showModalBottomSheet<AgentDocumentType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('upload_document'), style: ManaType.cardTitle),
              const SizedBox(height: ManaSpacing.md),
              for (final type in AgentDocumentType.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.description_outlined, color: ManaColors.brand),
                  title: ManaText.raw(type.displayLabel),
                  onTap: () => Navigator.of(sheetContext).pop(type),
                ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    // Camera first: an Agent doing this is standing in front of the customer
    // holding the card. Gallery is the fallback for a photo already taken.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: ManaColors.brand),
              title: ManaText.raw(ref.t('take_photo')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.image_outlined, color: ManaColors.brand),
              title: ManaText.raw(ref.t('choose_file')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    // Compression rejects an image it cannot bring under the bucket ceiling,
    // and that refusal carries the only message worth showing ("take it
    // again"). NetworkErrorHandler would flatten it into the generic string,
    // so it is caught here instead of being routed through it.
    final String fileUrl;
    try {
      fileUrl = await CustomerDocumentUpload.upload(
        bytes: bytes,
        customerId: customerId,
        documentType: result.displayLabel,
        stamp: manaNowIst().millisecondsSinceEpoch,
      );
    } on PhotoTooLargeException catch (e) {
      if (context.mounted) _snack(context, e.message);
      return;
    } on PhotoUnreadableException catch (e) {
      if (context.mounted) _snack(context, e.message);
      return;
    } catch (e) {
      // Anything else here is the storage upload itself — an RLS denial when
      // can_upload_documents is off, or a dead connection. Say which.
      if (context.mounted) {
        _snack(context, ref.t('could_not_upload_document_note').replaceAll('{error}', '$e'));
      }
      return;
    }
    if (!context.mounted) return;

    await NetworkErrorHandler.run(context, () async {
      return ref.read(agentCustomerProfileProvider(customerId).notifier).uploadDocument(
            documentType: result,
            fileUrl: fileUrl,
          );
    });
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: ManaText.raw(message)));
  }
}

class _SummaryTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _SummaryTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = profile.summary;
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(child: ManaText.raw(s.fullName, style: ManaType.sheetTitle)),
        Center(child: ManaText.raw(s.mlid, style: ManaType.secondary)),
        const SizedBox(height: ManaSpacing.lg),
        _row(ref.t('village'), s.village),
        // Tapping the number opens the handset's dialer with it keyed in —
        // the agent still presses call themselves.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: ManaText.raw(ref.t('phone'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.note)),
              const SizedBox(width: ManaSpacing.xs),
              ManaText.raw(s.phoneNumber,
                  style: ManaType.smallStrong),
              ManaCallButton(s.phoneNumber),
            ],
          ),
        ),
        _row(ref.t('assigned_agent'), profile.currentAgent ?? '—'),
        _row(ref.t('loan_count'), '${s.activeLoanCount}'),
        _row(ref.t('outstanding'), manaRupees(s.outstandingBalance)),
        _row(ref.t('todays_due'), manaRupees(s.todaysDue)),
        const SizedBox(height: ManaSpacing.md),
        ManaText.raw(
          ref.t('read_only_figures_note'),
          style: ManaType.note,
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: ManaText.raw(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ManaType.note)),
            const SizedBox(width: ManaSpacing.xs),
            ManaText.raw(value, style: ManaType.smallStrong),
          ],
        ),
      );
}

/// LOAN INFORMATION — read-only display only.
class _LoanInformationTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _LoanInformationTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.loans.isEmpty) {
      return Center(child: ManaText.raw(ref.t('no_loans_yet'), style: ManaType.secondary));
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
                              child: ManaText.raw(l.loanNumber, style: ManaType.emphasis)),
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
                      _row('Outstanding', manaRupees(l.outstanding)),
                      _row("Today's Due", manaRupees(l.todaysDue)),
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
            Expanded(
                child: ManaText.raw(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ManaType.note)),
            const SizedBox(width: ManaSpacing.xs),
            ManaText.raw(value, style: ManaType.smallStrong),
          ],
        ),
      );
}

/// COLLECTION HISTORY — Business Date, Receipt Number, Amount, Payment
/// Mode, Collector, Remarks. Read Only.
class _CollectionHistoryTab extends ConsumerWidget {
  final CustomerProfile profile;
  const _CollectionHistoryTab({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.collections.isEmpty) {
      return Center(
          child: ManaText.raw(ref.t('no_collections_yet'), style: ManaType.secondary));
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.collections
          .map((c) => ListTile(
                leading: Icon(Icons.receipt_long_outlined, color: ManaColors.brand),
                title: ManaText.raw(manaRupees(c.amount)),
                subtitle: ManaText.raw('${c.paymentMode} · ${c.collector} · #${c.receiptNumber}'),
                trailing: ManaText.raw(DateFormat('d MMM').format(c.businessDate),
                    style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
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
                ? [ManaText.raw(ref.t('no_remarks_yet'), style: ManaType.secondary)]
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
                                  tooltip: ref.t('delete'),
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
                      decoration: InputDecoration(labelText: ref.t('add_remark_append_only_field')),
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

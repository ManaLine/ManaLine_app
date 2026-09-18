import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/customer_row.dart';
import '../../../shared/widgets/workspace_nav.dart';
import '../../../shared/customer_collections_tab.dart';
import '../../../shared/mlti_upgrade_sheet.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_label_value_row.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/live_photo_upload.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/photo_compression.dart';
import '../../owner_workspace/state/customer_state.dart' show CustomerProfile, CustomerRemark;
import '../../owner_workspace/state/collection_mode_state.dart' show CollectionDueRow;
import '../../../shared/soft_delete_service.dart';
import '../../../shared/add_village_if_missing.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../../../shared/widgets/village_search_field.dart';
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
        // The bar stays even here. An Agent who may not view customers landed
        // on a permission notice with no back arrow (this bar's tabs use
        // go(), so there is nothing to pop) and no way off the screen.
        bottomNavigationBar: ManaWorkspaceNav(
            workspace: ManaWorkspace.agent,
            businessId: widget.businessId,
            currentIndex: 2),
        appBar: ManaAppBar(title: ref.t('customer_management')),
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
      // Index 2 is Customers, which is this screen.
      bottomNavigationBar: ManaWorkspaceNav(
          workspace: ManaWorkspace.agent,
          businessId: widget.businessId,
          currentIndex: 2),
      appBar: ManaAppBar(
        homeRoute: '/ag-001',
        title: ref.t('customer_management'),
        // No Create Customer action here any more.
        //
        // It was a snackbar reading "TODO: wire shared sheet" -- pressing it
        // told the Agent to go away. The header's + on every Owner and Agent
        // screen opens the real thing now, so a second entry point beside it
        // would be two buttons for one job, one of which never worked.
      ),
      body: SafeArea(
        child: state.loading && state.customers.isEmpty
            ? const ManaSkeletonList()
            : Column(
                children: [
                  // Counted off the list already in hand -- an MLTI is what
                  // the prefix says -- so this costs no query.
                  MltiUpgradeBanner(
                    count: state.customers
                        .where((c) => c.mlid.startsWith('MLTI'))
                        .length,
                    businessId: widget.businessId,
                  ),
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
                                return ManaCustomerRow(
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
        appBar: ManaAppBar(
          homeRoute: '/ag-004',
          title: customerName,
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
              _LoanInformationTab(
                profile: profile,
                onIssueLoan: perms.canIssueLoans
                    ? () => _handleAction(context, ref, 'create_loan')
                    : null,
              ),
              CustomerCollectionsTab(profile: profile),
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
        // Through the router, and the loan in the path: a pushed page sits
        // above GoRouter's pages, and the round carries the footer nav whose
        // tabs go(). The loan id is a query param rather than `extra`,
        // because `extra` is how every route here receives the businessId.
        await context.push('/ag-002?loan=${dueRow.loanId}', extra: businessId);
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
    String? selectedVillageId;
    String? selectedVillageLabel; // "Village — Mandal, District" for confirmation display
    // The submitted pin_code comes from the picked village's directory row —
    // ManaVillageSearchField owns PIN entry now (its PIN mode embeds
    // ManaVillagePickerField, which renders the PIN field), so there is no
    // separate screen-typed box to read it from.
    String? selectedVillagePinCode;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
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
                  ManaVillageSearchField(
                    businessId: businessId,
                    label: ref.t('search_village_town_plain_field'),
                    onPicked: (v) async {
                      if (v == null) {
                        setSheetState(() {
                          selectedVillageId = null;
                          selectedVillageLabel = null;
                          selectedVillagePinCode = null;
                        });
                        return;
                      }
                      // A reference suggestion has no location_id until it is
                      // picked. village_id is a FK, so it has to be a real row
                      // before this address is saved.
                      var id = v.locationId;
                      if (id.isEmpty) {
                        final resolved = await manaAddVillageIfMissing(
                          sheetContext,
                          ref,
                          pinCode: v.pinCode,
                          villageTownName: v.name,
                          areaType: 'Village',
                          mandal: v.mandal,
                          district: v.district,
                          state: v.state,
                        );
                        if (resolved == null) return; // already explained
                        id = resolved;
                      }
                      if (!sheetContext.mounted) return;
                      setSheetState(() {
                        selectedVillageId = id;
                        selectedVillageLabel = v.placeLabel.isEmpty
                            ? v.name
                            : '${v.name} — ${v.placeLabel}';
                        if (v.pinCode.isNotEmpty) {
                          selectedVillagePinCode = v.pinCode;
                        }
                      });
                    },
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
            pinCode: selectedVillagePinCode,
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
        ManaVerificationRing(
                            isVerified: s.isVerified ?? false,
                            ringColor: s.isVerified == null ? ManaColors.textSecondary : null,
                            size: 72,
                          ),
        const SizedBox(height: ManaSpacing.md),
        Center(child: ManaText.raw(s.fullName, style: ManaType.sheetTitle)),
        Center(child: ManaText.raw(s.mlid, style: ManaType.secondary)),
        const SizedBox(height: ManaSpacing.lg),
        ManaLabelValueRow(label: ref.t('village'), value: s.village),
        // Tapping the number opens the handset's dialer with it keyed in —
        // the agent still presses call themselves.
        ManaLabelValueRow(
          label: ref.t('phone'),
          value: s.phoneNumber,
          trailing: ManaCallButton(s.phoneNumber),
        ),
        ManaLabelValueRow(label: ref.t('assigned_agent'), value: profile.currentAgent ?? '—'),
        ManaLabelValueRow(label: ref.t('loan_count'), value: '${s.activeLoanCount}'),
        ManaLabelValueRow(label: ref.t('outstanding'), amount: s.outstandingBalance),
        ManaLabelValueRow(label: ref.t('todays_due'), amount: s.todaysDue),
        const SizedBox(height: ManaSpacing.md),
        ManaText.raw(
          ref.t('read_only_figures_note'),
          style: ManaType.note,
        ),
      ],
    );
  }


}

/// LOAN INFORMATION — read-only display only.
class _LoanInformationTab extends ConsumerWidget {
  final CustomerProfile profile;

  /// Null when this Agent may not issue loans, in which case the tab says what
  /// it says and offers nothing — the same rule the ⋮ menu already applies.
  final VoidCallback? onIssueLoan;

  const _LoanInformationTab({required this.profile, this.onIssueLoan});

  /// AN EMPTY TAB THAT OFFERS NOTHING IS A DEAD END.
  ///
  /// This said "No Loans Yet" and stopped, while Create Loan sat in the ⋮ menu
  /// two taps away behind a glyph. A customer with no loan is the single most
  /// likely person to be about to get one, so the empty state is exactly where
  /// that action belongs — reported from the handset as "he has no loan but I
  /// need here an option to create a loan".
  ///
  /// Routed through the SAME handler as the menu item rather than a second
  /// copy of the navigation: two ways to start a loan that drift apart is how
  /// one of them stops carrying the prefilled customer and quietly opens the
  /// wizard on nobody.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile.loans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(ref.t('no_loans_yet'), style: ManaType.secondary),
              if (onIssueLoan != null) ...[
                const SizedBox(height: ManaSpacing.lg),
                FilledButton.icon(
                  onPressed: onIssueLoan,
                  icon: const Icon(Icons.add, size: 18),
                  label: ManaText.raw(ref.t('create_loan')),
                ),
              ],
            ],
          ),
        ),
      );
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
                          // Grace overrides the status -- see the Owner's
                          // copy of this list. loans.loan_status never says
                          // 'Grace Period'; nothing writes it.
                          ManaStatusPill(
                            label: l.inGrace ? ref.t('grace_period') : l.status,
                            status: l.inGrace
                                ? ManaStatus.warn
                                : l.status == 'Active'
                                    ? ManaStatus.good
                                    : l.status == 'Penalty'
                                        ? ManaStatus.bad
                                        : ManaStatus.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      ManaLabelValueRow(dense: true, label: 'Outstanding', amount: l.outstanding),
                      ManaLabelValueRow(dense: true, label: "Today's Due", amount: l.todaysDue),
                      ManaLabelValueRow(dense: true, label: 'Issued', value: DateFormat('d MMM yyyy').format(l.issueDate)),
                      ManaLabelValueRow(dense: true, label: 'Progress', value: '${l.progressPercent.toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
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

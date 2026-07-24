import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/business_management_state.dart';

/// OW-012 — Business Management. Owner only. Create and manage Businesses.
///
/// S1 Business List is the landing state (list of Business Summary Cards,
/// "Create Business" available above the list — BR-119 Revised: one Owner
/// may own multiple Businesses). Drilling into a card opens S3 Business
/// Detail with tabs for Operating Areas / Business Agreements / Business
/// Members / Account Periods.
class BusinessManagementScreen extends ConsumerStatefulWidget {
  const BusinessManagementScreen({super.key});

  @override
  ConsumerState<BusinessManagementScreen> createState() => _BusinessManagementScreenState();
}

class _BusinessManagementScreenState extends ConsumerState<BusinessManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessListProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('business management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const _CreateBusinessScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const ManaText('create business'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(businessListProvider.notifier).load(),
          child: state.loading && state.businesses.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.businesses.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(ManaSpacing.xxl),
                      children: const [
                        Center(
                          child: ManaText.raw(
                            'No businesses yet. Tap "Create Business" to get started.',
                            style: TextStyle(color: ManaColors.textSecondary),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.xxl * 2),
                      children: state.businesses
                          .map((b) => _BusinessSummaryCard(
                                business: b,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => _BusinessDetailScreen(businessId: b.businessId)),
                                ),
                              ))
                          .toList(),
                    ),
        ),
      ),
    );
  }
}

class _BusinessSummaryCard extends StatelessWidget {
  final BusinessSummary business;
  final VoidCallback onTap;
  const _BusinessSummaryCard({required this.business, required this.onTap});

  ManaStatus get _statusKind => switch (business.businessStatus) {
        'Active' => ManaStatus.good,
        'Suspended' => ManaStatus.bad,
        _ => ManaStatus.neutral, // Not Started
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ManaColors.inkFaint,
                    backgroundImage: business.logoUrl != null ? NetworkImage(business.logoUrl!) : null,
                    child: business.logoUrl == null
                        ? const Icon(Icons.storefront, color: ManaColors.textSecondary)
                        : null,
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ManaText.raw(business.businessName,
                            style: Theme.of(context).textTheme.titleLarge),
                        ManaText.raw(business.mlbi,
                            style: const TextStyle(color: ManaColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  ManaStatusPill(label: business.businessStatus, status: _statusKind),
                ],
              ),
              const SizedBox(height: ManaSpacing.md),
              Wrap(
                spacing: ManaSpacing.md,
                runSpacing: ManaSpacing.xs,
                children: [
                  _StatChip(icon: Icons.location_on_outlined, label: '${business.operatingAreaCount} Areas'),
                  _StatChip(icon: Icons.people_outline, label: '${business.activeCustomers} Customers'),
                  _StatChip(icon: Icons.badge_outlined, label: '${business.activeAgents} Agents'),
                  _StatChip(icon: Icons.savings_outlined, label: '${business.activeInvestors} Investors'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ManaColors.textSecondary),
        const SizedBox(width: 4),
        ManaText.raw(label, style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
      ],
    );
  }
}

// ============================================================================
// S2 — Create Business
// ============================================================================

class _CreateBusinessScreen extends ConsumerStatefulWidget {
  const _CreateBusinessScreen();

  @override
  ConsumerState<_CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<_CreateBusinessScreen> {
  final _businessName = TextEditingController();
  final _registeredFinanceName = TextEditingController();
  final _businessType = TextEditingController();
  final _businessAddress = TextEditingController();
  final _businessPhone = TextEditingController();
  final _businessEmail = TextEditingController();

  bool get _valid => _businessName.text.trim().isNotEmpty && _registeredFinanceName.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(createBusinessFormProvider.notifier).submit(
            businessName: _businessName.text.trim(),
            registeredFinanceName: _registeredFinanceName.text.trim(),
            businessType: _businessType.text.trim().isEmpty ? null : _businessType.text.trim(),
            businessAddress: _businessAddress.text.trim().isEmpty ? null : _businessAddress.text.trim(),
            businessPhone: _businessPhone.text.trim().isEmpty ? null : _businessPhone.text.trim(),
            businessEmail: _businessEmail.text.trim().isEmpty ? null : _businessEmail.text.trim(),
          );
    });
    if (ok == true && mounted) {
      final businessId = ref.read(createBusinessFormProvider).createdBusinessId;
      ref.read(createBusinessFormProvider.notifier).reset();
      Navigator.of(context).pop();
      if (businessId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _BusinessDetailScreen(businessId: businessId)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(createBusinessFormProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('create business')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText.raw(
              'This is the same Create Business step covered in first-time setup — '
              'use it here to add another business, or to start one you skipped earlier.',
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            TextField(
              controller: _businessName,
              decoration: const InputDecoration(labelText: 'Business Name *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _registeredFinanceName,
              decoration: const InputDecoration(labelText: 'Registered Finance Name *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: _businessType, decoration: const InputDecoration(labelText: 'Business Type')),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessAddress,
              decoration: const InputDecoration(labelText: 'Business Address'),
              maxLines: 2,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessPhone,
              decoration: const InputDecoration(labelText: 'Business Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessEmail,
              decoration: const InputDecoration(labelText: 'Business Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: ManaSpacing.xxl),
            FilledButton(
              onPressed: (_valid && !formState.submitting) ? _submit : null,
              child: formState.submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('save business'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// S3 — Business Detail (tabs)
// ============================================================================

class _BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;
  const _BusinessDetailScreen({required this.businessId});

  @override
  ConsumerState<_BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<_BusinessDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessDetailProvider(widget.businessId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider(widget.businessId));
    final detail = state.detail;

    return DefaultTabController(
      length: 4,
      initialIndex: BusinessDetailTab.values.indexOf(state.activeTab),
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(detail?.summary.businessName ?? 'business detail'),
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => ref
                .read(businessDetailProvider(widget.businessId).notifier)
                .setTab(BusinessDetailTab.values[i]),
            tabs: const [
              Tab(text: 'Operating Areas'),
              Tab(text: 'Agreements'),
              Tab(text: 'Members'),
              Tab(text: 'Account Periods'),
            ],
          ),
        ),
        body: state.loading && detail == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _OperatingAreasTab(businessId: widget.businessId),
                  _AgreementsTab(businessId: widget.businessId),
                  _MembersTab(businessId: widget.businessId),
                  _AccountPeriodsTab(businessId: widget.businessId),
                ],
              ),
      ),
    );
  }
}

// --- Operating Areas tab -----------------------------------------------------
// Reuses the PIN → Village → Add flow already built for OW-000 Step 2. Also
// reachable to expand an already-Active business's areas (locked rule).

class _OperatingAreasTab extends ConsumerStatefulWidget {
  final String businessId;
  const _OperatingAreasTab({required this.businessId});

  @override
  ConsumerState<_OperatingAreasTab> createState() => _OperatingAreasTabState();
}

class _OperatingAreasTabState extends ConsumerState<_OperatingAreasTab> {
  final _pinCode = TextEditingController();

  Future<void> _addSelected() async {
    final selected = ref.read(operatingAreaSearchProvider).selected;
    if (selected == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).addOperatingArea(
            locationId: selected.locationId,
          );
    });
    if (ok == true) {
      ref.read(operatingAreaSearchProvider.notifier).reset();
      _pinCode.clear();
    }
  }

  Future<void> _configureCycle(OperatingAreaSummary area) async {
    final result = await showDialog<_CycleConfigInput>(
      context: context,
      builder: (_) => _CycleConfigDialog(initial: area),
    );
    if (result == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).configureAccountCycle(
            operatingAreaId: area.operatingAreaId,
            durationDays: result.duration,
            cycleUnit: result.unit,
            submissionTime: result.submissionTime,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(businessDetailProvider(widget.businessId)).operatingAreas;
    final search = ref.watch(operatingAreaSearchProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'Search PIN Code → Matching PIN List → Select PIN → Village Search → '
          'Select Village → Add. Repeat until complete. Unlimited villages allowed.',
          style: TextStyle(color: ManaColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _pinCode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'PIN Code'),
          onChanged: (v) {
            if (v.trim().length == 6) {
              ref.read(operatingAreaSearchProvider.notifier).searchByPin(v.trim());
            }
          },
        ),
        if (search.searching) const Center(child: CircularProgressIndicator()),
        if (!search.searching && search.matches.isNotEmpty)
          ...search.matches.map((m) {
            final selected = search.selected?.locationId == m.locationId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? ManaColors.statusGood : ManaColors.textSecondary,
              ),
              title: ManaText.raw('${m.villageTownName} — ${m.pinCode}'),
              onTap: () => ref.read(operatingAreaSearchProvider.notifier).selectVillage(m),
            );
          }),
        const SizedBox(height: ManaSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: search.selected != null ? _addSelected : null,
            icon: const Icon(Icons.add, size: 18),
            label: const ManaText('add area'),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        const Divider(),
        const SizedBox(height: ManaSpacing.sm),
        const ManaText('current operating areas', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        if (areas.isEmpty)
          const ManaText.raw('No Operating Areas yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...areas.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: ManaColors.brass),
                  title: ManaText.raw('${a.villageTownName} — ${a.pinCode}'),
                  subtitle: ManaText.raw(a.cycleConfigured
                      ? 'Cycle: ${a.accountCycleDuration} ${a.accountCycleUnit}, submits ${a.submissionTime}'
                      : 'Account cycle not yet configured'),
                  trailing: TextButton(
                    onPressed: () => _configureCycle(a),
                    child: ManaText(a.cycleConfigured ? 'edit cycle' : 'configure'),
                  ),
                ),
              )),
      ],
    );
  }
}

class _CycleConfigInput {
  final int duration;
  final String unit;
  final String submissionTime;
  _CycleConfigInput({required this.duration, required this.unit, required this.submissionTime});
}

class _CycleConfigDialog extends StatefulWidget {
  final OperatingAreaSummary initial;
  const _CycleConfigDialog({required this.initial});

  @override
  State<_CycleConfigDialog> createState() => _CycleConfigDialogState();
}

class _CycleConfigDialogState extends State<_CycleConfigDialog> {
  late final _duration = TextEditingController(text: '${widget.initial.accountCycleDuration ?? 3}');
  String _unit = 'Days';
  final _submissionTime = TextEditingController(text: '21:00');

  @override
  void initState() {
    super.initState();
    _unit = widget.initial.accountCycleUnit ?? 'Days';
    if (widget.initial.submissionTime != null) _submissionTime.text = widget.initial.submissionTime!;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ManaText('configure account cycle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Account Cycle Duration'),
          ),
          const SizedBox(height: ManaSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Account Cycle Unit'),
            items: const ['Days', 'Weeks', 'Months']
                .map((u) => DropdownMenuItem(value: u, child: ManaText.raw(u)))
                .toList(),
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _submissionTime,
            decoration: const InputDecoration(labelText: 'Submission Time (HH:MM)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
        FilledButton(
          onPressed: () {
            final duration = int.tryParse(_duration.text.trim()) ?? 3;
            Navigator.of(context).pop(
              _CycleConfigInput(duration: duration, unit: _unit, submissionTime: _submissionTime.text.trim()),
            );
          },
          child: const ManaText('save'),
        ),
      ],
    );
  }
}

// --- Business Agreements tab -------------------------------------------------

class _AgreementsTab extends ConsumerStatefulWidget {
  final String businessId;
  const _AgreementsTab({required this.businessId});

  @override
  ConsumerState<_AgreementsTab> createState() => _AgreementsTabState();
}

class _AgreementsTabState extends ConsumerState<_AgreementsTab> {
  Future<void> _createAgreement() async {
    final result = await showDialog<_AgreementInput>(
      context: context,
      builder: (_) => const _CreateAgreementDialog(),
    );
    if (result == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).createAgreement(
            agreementType: result.type,
            sourceType: result.sourceType,
            contentUrlOrText: result.content,
            effectiveDate: result.effectiveDate,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final agreements = ref.watch(businessDetailProvider(widget.businessId)).agreements;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'Business Agreements are business-specific — a multi-business Owner '
          'sets these independently per MLBI; they do not carry over.',
          style: TextStyle(color: ManaColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: ManaSpacing.md),
        FilledButton.tonalIcon(
          onPressed: _createAgreement,
          icon: const Icon(Icons.add, size: 18),
          label: const ManaText('create agreement'),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (agreements.isEmpty)
          const ManaText.raw('No agreements created yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...agreements.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined, color: ManaColors.ink),
                  title: ManaText.raw('${a.agreementType} Agreement · v${a.version}'),
                  subtitle: ManaText.raw('${a.sourceType} · effective ${a.effectiveDate}'),
                ),
              )),
      ],
    );
  }
}

class _AgreementInput {
  final String type;
  final String sourceType;
  final String content;
  final String effectiveDate;
  _AgreementInput({required this.type, required this.sourceType, required this.content, required this.effectiveDate});
}

class _CreateAgreementDialog extends StatefulWidget {
  const _CreateAgreementDialog();

  @override
  State<_CreateAgreementDialog> createState() => _CreateAgreementDialogState();
}

class _CreateAgreementDialogState extends State<_CreateAgreementDialog> {
  String _type = 'Customer';
  String _sourceType = 'In-App';
  final _content = TextEditingController();
  final _effectiveDate = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final valid = _content.text.trim().isNotEmpty && _effectiveDate.text.trim().isNotEmpty;

    return AlertDialog(
      title: const ManaText('create business agreement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Agreement Type'),
              items: const ['Customer', 'Agent', 'Investor']
                  .map((t) => DropdownMenuItem(value: t, child: ManaText.raw(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: ManaSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Uploaded PDF', label: ManaText.raw('Upload PDF')),
                ButtonSegment(value: 'In-App', label: ManaText.raw('Create Inside App')),
              ],
              selected: {_sourceType},
              onSelectionChanged: (s) => setState(() => _sourceType = s.first),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: _sourceType == 'Uploaded PDF' ? 'Document URL' : 'Agreement Text',
              ),
              maxLines: _sourceType == 'Uploaded PDF' ? 1 : 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _effectiveDate,
              decoration: const InputDecoration(labelText: 'Effective Date (YYYY-MM-DD)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_AgreementInput(
                    type: _type,
                    sourceType: _sourceType,
                    content: _content.text.trim(),
                    effectiveDate: _effectiveDate.text.trim(),
                  ))
              : null,
          child: const ManaText('save'),
        ),
      ],
    );
  }
}

// --- Business Members tab ----------------------------------------------------

class _MembersTab extends ConsumerStatefulWidget {
  final String businessId;
  const _MembersTab({required this.businessId});

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  Future<void> _addExisting(String role) async {
    final personId = await showDialog<String>(
      context: context,
      builder: (_) {
        final controller = TextEditingController();
        return AlertDialog(
          title: ManaText('add existing $role'.toLowerCase()),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Person ID / MLID'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const ManaText('add'),
            ),
          ],
        );
      },
    );
    if (personId == null || personId.isEmpty || !mounted) return;

    await NetworkErrorHandler.run(context, () async {
      final notifier = ref.read(businessDetailProvider(widget.businessId).notifier);
      return role == 'Agent'
          ? notifier.addExistingAgent(personId: personId)
          : notifier.addExistingCustomer(personId: personId);
    });
  }

  Future<void> _decideInvestorRequest(MembershipRequestSummary request, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const ManaText('reject investor request'),
            content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Reason')),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const ManaText('reject'),
              ),
            ],
          );
        },
      );
      if (reason == null || !mounted) return;
    }
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).decideInvestorRequest(
            requestId: request.requestId,
            approve: approve,
            rejectionReason: reason,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider(widget.businessId));
    final pendingInvitations = state.members.where((m) => m.membershipStatus == 'Pending Invitation').toList();
    final pendingAcceptance = state.members.where((m) => m.membershipStatus == 'Pending Acceptance').toList();
    final active = state.members.where((m) => m.membershipStatus == 'Active').toList();

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Wrap(
          spacing: ManaSpacing.sm,
          runSpacing: ManaSpacing.sm,
          children: [
            OutlinedButton(onPressed: () => _addExisting('Agent'), child: const ManaText('add existing agent')),
            OutlinedButton(
                onPressed: () => _addExisting('Customer'), child: const ManaText('add existing customer')),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.membershipRequests.isNotEmpty) ...[
          const ManaText('request queue (investors)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          ...state.membershipRequests.map((r) => Card(
                child: ListTile(
                  leading: const ManaVerificationRing(isVerified: false, size: 36),
                  title: ManaText.raw(r.fullName),
                  subtitle: ManaText.raw(
                    r.proposedInvestmentAmount != null
                        ? 'Proposed: ₹${r.proposedInvestmentAmount!.toStringAsFixed(0)}'
                        : r.requestedRole,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: ManaColors.statusBad),
                        onPressed: () => _decideInvestorRequest(r, false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: ManaColors.statusGood),
                        onPressed: () => _decideInvestorRequest(r, true),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingInvitations.isNotEmpty) ...[
          const ManaText('pending invitations', style: TextStyle(fontWeight: FontWeight.bold)),
          ...pendingInvitations.map((m) => _MemberRow(member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingAcceptance.isNotEmpty) ...[
          const ManaText('pending acceptance', style: TextStyle(fontWeight: FontWeight.bold)),
          ...pendingAcceptance.map((m) => _MemberRow(member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        const ManaText('active members', style: TextStyle(fontWeight: FontWeight.bold)),
        if (active.isEmpty)
          const ManaText.raw('No active members yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...active.map((m) => _MemberRow(member: m)),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final MemberSummary member;
  const _MemberRow({required this.member});

  ManaStatus get _statusKind => switch (member.membershipStatus) {
        'Active' => ManaStatus.good,
        'Pending Invitation' || 'Pending Acceptance' || 'Pending Approval' => ManaStatus.warn,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 36),
        title: ManaText.raw(member.fullName),
        subtitle: ManaText.raw(member.role),
        trailing: ManaStatusPill(label: member.membershipStatus, status: _statusKind),
      ),
    );
  }
}

// --- Account Periods tab -----------------------------------------------------

class _AccountPeriodsTab extends ConsumerWidget {
  final String businessId;
  const _AccountPeriodsTab({required this.businessId});

  ManaStatus _statusKind(String status) => switch (status) {
        'Running' => ManaStatus.good,
        'Overdue' => ManaStatus.bad,
        'Submitted' => ManaStatus.warn,
        _ => ManaStatus.neutral, // Approved / Locked
      };

  Future<void> _reviewSubmitted(BuildContext context, WidgetRef ref, AccountPeriodSummary period) async {
    // Inline Owner Review — no separate screen (spec NAVIGATION note).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('approve account period?'),
        content: ManaText.raw(
          '${period.operatingAreaLabel} · ${period.agentName}\n'
          'Approving locks this Account Period. Locked accounts cannot be modified.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const ManaText('cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const ManaText('approve')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessDetailProvider(businessId).notifier)
          .approveAccountPeriod(accountPeriodId: period.accountPeriodId);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(businessDetailProvider(businessId)).accountPeriods;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        if (periods.isEmpty)
          const ManaText.raw('No Account Periods yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...periods.map((p) => Card(
                child: ListTile(
                  title: ManaText.raw('${p.operatingAreaLabel} · ${p.agentName}'),
                  subtitle: ManaText.raw(
                    '${p.businessStartDate.toIso8601String().split("T").first} → '
                    '${p.plannedBusinessEndDate.toIso8601String().split("T").first}',
                  ),
                  trailing: p.status == 'Submitted'
                      ? FilledButton(
                          onPressed: () => _reviewSubmitted(context, ref, p),
                          child: const ManaText('review'),
                        )
                      : ManaStatusPill(label: p.status, status: _statusKind(p.status)),
                ),
              )),
      ],
    );
  }
}

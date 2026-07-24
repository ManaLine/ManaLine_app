import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/customer_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-004 — Customer Management. List is the default landing state (C2);
/// row click opens Customer Profile directly (C3 RESOLVED — no per-row
/// context menu); "Add Customer" is a header action (C4 sub-flow).
class CustomerManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  const CustomerManagementScreen({super.key, required this.businessId});

  @override
  ConsumerState<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends ConsumerState<CustomerManagementScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerListProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('customer management'),
        actions: [
          IconButton(
            tooltip: 'Add Customer',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AddCustomerSheet(businessId: widget.businessId),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(customerListProvider.notifier).load(widget.businessId),
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
                      onChanged: (v) => ref.read(customerListProvider.notifier).setSearchQuery(v),
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _StatusFilterChips(state: state),
                    const SizedBox(height: ManaSpacing.xs),
                    const ManaText.raw(
                      'Sorted by: highest outstanding → penalty → grace period → today\'s due → village → name',
                      style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (state.filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child:
                              ManaText.raw('No customers match this view.', style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.filtered.map((c) => _CustomerRow(
                            customer: c,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    CustomerProfileScreen(businessId: widget.businessId, customer: c),
                              ),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatusFilterChips extends ConsumerWidget {
  final CustomerListState state;
  const _StatusFilterChips({required this.state});

  static const _statuses = ['Active', 'Suspended', 'Removed'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: ManaSpacing.xs,
      children: [
        ChoiceChip(
          label: const ManaText('all'),
          selected: state.customerStatusFilter == null,
          onSelected: (_) => ref.read(customerListProvider.notifier).setCustomerStatusFilter(null),
        ),
        ..._statuses.map((s) => ChoiceChip(
              label: ManaText(s),
              selected: state.customerStatusFilter == s,
              onSelected: (_) => ref.read(customerListProvider.notifier).setCustomerStatusFilter(s),
            )),
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
          '${customer.village} · ${customer.mlid} · LRI ${customer.lineRepaymentIndex}',
          style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ManaText.raw(_currency.format(customer.outstandingBalance),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (customer.todaysDue > 0)
              ManaText.raw('Due ${_currency.format(customer.todaysDue)}',
                  style: const TextStyle(fontSize: 11, color: ManaColors.statusWarn)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// --- C4 Create Customer sub-flow ---------------------------------------

class _AddCustomerSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _AddCustomerSheet({required this.businessId});

  @override
  ConsumerState<_AddCustomerSheet> createState() => _AddCustomerSheetState();
}

enum _AddCustomerStage { search, found, createNew }

class _AddCustomerSheetState extends ConsumerState<_AddCustomerSheet> {
  _AddCustomerStage _stage = _AddCustomerStage.search;
  final _query = TextEditingController();
  CustomerSummary? _foundIdentity;
  bool _searching = false;

  // Create New fields (reuses LR-004 field set per spec)
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  String? _gender;
  bool _submitting = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).searchIdentity(fullName: _query.text.trim());
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (result != null) {
        _foundIdentity = result;
        _stage = _AddCustomerStage.found;
      } else {
        _stage = _AddCustomerStage.createNew;
      }
    });
  }

  Future<void> _linkExisting() async {
    if (_foundIdentity == null) return;
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).linkExisting(widget.businessId, _foundIdentity!.customerId);
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  bool get _canCreateNew =>
      _fullName.text.trim().length >= 2 &&
      _fatherHusband.text.trim().length >= 2 &&
      _gender != null &&
      _mobile.text.trim().length == 10 &&
      _aadhaar.text.trim().length == 12;

  Future<void> _createNew() async {
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).createNew(
            businessId: widget.businessId,
            fullName: _fullName.text.trim(),
            fatherHusbandName: _fatherHusband.text.trim(),
            genderDigit: _gender!,
            mobileNumber: _mobile.text.trim(),
            aadhaarNumber: _aadhaar.text.trim(),
            villageId: 'stub-village-id',
          );
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: ListView(
            controller: scrollController,
            children: [
              const ManaText('add customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: ManaSpacing.lg),
              if (_stage == _AddCustomerStage.search) ..._searchStage(),
              if (_stage == _AddCustomerStage.found) ..._foundStage(),
              if (_stage == _AddCustomerStage.createNew) ..._createNewStage(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchStage() => [
        const ManaText.raw(
          'Search by Phone, Aadhaar, MANA LINE ID, or Full Name.',
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Search'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ElevatedButton(
              onPressed: (_query.text.trim().isNotEmpty && !_searching) ? _search : null,
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('search'),
            ),
          ],
        ),
      ];

  List<Widget> _foundStage() => [
        const ManaText('identity found', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        Card(
          child: ListTile(
            leading: const ManaVerificationRing(isVerified: true, size: 40),
            title: ManaText.raw(_foundIdentity!.fullName),
            subtitle: ManaText.raw(_foundIdentity!.mlid),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: _submitting ? null : _linkExisting,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('confirm & link to business'),
        ),
        TextButton(
          onPressed: () => setState(() => _stage = _AddCustomerStage.search),
          child: const ManaText('search again'),
        ),
      ];

  List<Widget> _createNewStage() => [
        const ManaText('no match found — create new identity', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.xs),
        const ManaText.raw(
          'New customer must be physically present — this reuses the same '
          'registration fields as account registration.',
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
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
          decoration: const InputDecoration(labelText: 'Father / Husband Name *'),
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Mobile Number *'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _aadhaar,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Aadhaar Number *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_canCreateNew && !_submitting) ? _createNew : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('create & link to business'),
        ),
      ];
}

// --- C5 Customer Profile (tabbed drill-in) ------------------------------

class CustomerProfileScreen extends ConsumerWidget {
  final String businessId;
  final CustomerSummary customer;
  const CustomerProfileScreen({super.key, required this.businessId, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(customerProfileProvider(customer.customerId));

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(customer.fullName),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Loans'),
              Tab(text: 'Collections'),
              Tab(text: 'Documents'),
              Tab(text: 'Remarks'),
              Tab(text: 'History'),
              Tab(text: 'Audit'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => _handleAction(context, ref, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new_loan', child: ManaText('new loan')),
                PopupMenuItem(value: 'collect', child: ManaText('collect payment')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'suspend', child: ManaText('suspend customer')),
                PopupMenuItem(value: 'archive', child: ManaText('archive customer')),
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
          )),
          data: (profile) => TabBarView(
            children: [
              _SummaryTab(customer: customer, profile: profile),
              _LoansTab(profile: profile),
              _CollectionsTab(profile: profile),
              const _DocumentsTab(),
              _RemarksTab(customerId: customer.customerId, profile: profile),
              const _HistoryTab(),
              const _AuditTab(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'new_loan':
        context.push('/ow-005', extra: customer.customerId);
      case 'collect':
        context.push('/ow-006', extra: customer.customerId);
      case 'suspend':
      case 'archive':
        final status = action == 'suspend' ? 'Suspended' : 'Removed';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: ManaText('confirm: ${action == 'suspend' ? 'suspend' : 'archive'} customer'),
            content: ManaText.raw(
                'This never deletes ${customer.fullName}\'s history — only changes their membership status.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const ManaText('cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const ManaText('confirm')),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        await NetworkErrorHandler.run(context, () async {
          return ref.read(customerListProvider.notifier).updateStatus(businessId, customer.customerId, status);
        });
    }
  }
}

class _SummaryTab extends StatelessWidget {
  final CustomerSummary customer;
  final CustomerProfile profile;
  const _SummaryTab({required this.customer, required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(
            child:
                ManaText.raw(customer.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        Center(child: ManaText.raw(customer.mlid, style: const TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _row('Father / Husband', customer.fatherHusbandName),
        _row('Village', customer.village),
        _row('Phone', customer.phoneNumber),
        _row('Occupation', profile.occupation ?? '—'),
        _row('Address', profile.address ?? '—'),
        _row('Customer Since', DateFormat('d MMM yyyy').format(profile.customerSince)),
        _row('Current Agent', profile.currentAgent ?? '—'),
        _row('Current Status', customer.membershipStatus),
        _row('Line Repayment Index', '${customer.lineRepaymentIndex}'),
        _row('Loan Count', '${customer.activeLoanCount}'),
        _row('Outstanding Balance', _currency.format(customer.outstandingBalance)),
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

class _LoansTab extends StatelessWidget {
  final CustomerProfile profile;
  const _LoansTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.loans.isEmpty) {
      return const Center(
        child: ManaText.raw('No loans yet.', style: TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.loans
          .map((l) => Card(
                child: ListTile(
                  title: ManaText.raw(l.loanNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: ManaText.raw(
                    'Issued ${DateFormat('d MMM yyyy').format(l.issueDate)} · Outstanding ${_currency.format(l.outstanding)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: ManaStatusPill(
                    label: l.status,
                    status: l.status == 'Active'
                        ? ManaStatus.good
                        : l.status == 'Penalty'
                            ? ManaStatus.bad
                            : ManaStatus.neutral,
                  ),
                  onTap: () {}, // → OW-007 Loan Details, not yet built
                ),
              ))
          .toList(),
    );
  }
}

class _CollectionsTab extends StatelessWidget {
  final CustomerProfile profile;
  const _CollectionsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.collections.isEmpty) {
      return const Center(
        child: ManaText.raw('No collections yet.', style: TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: profile.collections
          .map((c) => ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: ManaColors.brass),
                title: ManaText.raw(_currency.format(c.amount)),
                subtitle: ManaText.raw('${c.paymentMode} · ${c.collector} · #${c.receiptNumber}'),
                trailing: ManaText.raw(DateFormat('d MMM').format(c.businessDate),
                    style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
              ))
          .toList(),
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab();

  @override
  Widget build(BuildContext context) {
    const docs = [
      'Aadhaar',
      'Photo',
      'Address Proof',
      'Customer Agreement',
      'Loan Agreement',
      'Guarantor Documents',
      'Other Documents',
    ];
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: docs
          .map((d) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: ManaText(d),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ))
          .toList(),
    );
  }
}

class _RemarksTab extends ConsumerStatefulWidget {
  final String customerId;
  final CustomerProfile profile;
  const _RemarksTab({required this.customerId, required this.profile});

  @override
  ConsumerState<_RemarksTab> createState() => _RemarksTabState();
}

class _RemarksTabState extends ConsumerState<_RemarksTab> {
  final _remark = TextEditingController();
  bool _submitting = false;

  Future<void> _add() async {
    if (_remark.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    await NetworkErrorHandler.run(context, () async {
      return ref.read(customerProfileProvider(widget.customerId).notifier).addRemark(_remark.text.trim());
    });
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _remark.clear();
    });
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
                            trailing: ManaStatusPill(
                              label: r.priority,
                              status: r.priority == 'High' ? ManaStatus.bad : ManaStatus.neutral,
                            ),
                          ),
                        ))
                    .toList(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _remark,
                    decoration: const InputDecoration(hintText: 'Add a remark (append-only)'),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                IconButton(
                  onPressed: _submitting ? null : _add,
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

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          'Chronological record: Customer Created, Loans Created, Loan Closures, '
          'Collections, Transfers, Address Changes, Agent Changes.\nNo entries yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textSecondary),
        ),
      ),
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
          'Who Changed, What Changed, Old Value, New Value — per BR-158. No entries yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textSecondary),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_stat_strip.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/text_utils.dart';
import '../state/investor_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-003 — Investor Management. Register New Investor is
/// Investor-initiated (LOCKED CORRECTION in spec) — this screen's C4 is
/// therefore an Approve/Reject queue over incoming requests, not a create
/// form; C5 Add Existing mirrors OW-002's MLID search pattern.
class InvestorManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  // Set by OW-001's "Add Existing Investor" Quick Action tile ('existing').
  final String? initialAction;
  // Set by the "Investor Requests" Quick Action tile to pre-filter the
  // list to a given membership status (e.g. 'Pending Acceptance').
  final String? initialFilter;
  const InvestorManagementScreen({
    super.key,
    required this.businessId,
    this.initialAction,
    this.initialFilter,
  });

  @override
  ConsumerState<InvestorManagementScreen> createState() => _InvestorManagementScreenState();
}

class _InvestorManagementScreenState extends ConsumerState<InvestorManagementScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Setting the filter here rather than synchronously in initState —
      // a provider write during any widget's build phase (including
      // initState) throws Riverpod's "tried to modify a provider while the
      // widget tree was building" (hit this for real in the sibling
      // OW-012 tab case — see that file's fix note).
      if (widget.initialFilter != null) {
        ref.read(investorWorkforceProvider.notifier).setStatusFilter(widget.initialFilter);
      }
      ref.read(investorWorkforceProvider.notifier).load(widget.businessId);
      if (widget.initialAction == 'existing') {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AddExistingInvestorSheet(businessId: widget.businessId),
        ).then((_) => ref.read(investorWorkforceProvider.notifier).load(widget.businessId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(investorWorkforceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('investor management'),
        actions: [
          IconButton(
            tooltip: 'Add Existing Investor',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AddExistingInvestorSheet(businessId: widget.businessId),
            ).then((_) => ref.read(investorWorkforceProvider.notifier).load(widget.businessId)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(investorWorkforceProvider.notifier).load(widget.businessId),
          child: state.loading && state.investors.isEmpty
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
                      onChanged: (v) => ref.read(investorWorkforceProvider.notifier).setSearchQuery(v),
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    _StatusFilterChips(state: state),
                    const SizedBox(height: ManaSpacing.md),
                    // C4 — Pending requests surfaced at top since these need
                    // an Owner decision (Investor-initiated, per spec).
                    ...state.investors
                        .where((i) => i.membershipStatus == 'Pending Acceptance')
                        .map((i) => _PendingRequestCard(businessId: widget.businessId, investor: i)),
                    // A failed load previously looked identical to "no
                    // investors" — state.error was captured but never
                    // shown, indistinguishable from a business that
                    // genuinely has zero investors.
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('Could not load investors.\n${state.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
                        ),
                      )
                    else if (state.filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw('No investors match this view.',
                              style: TextStyle(color: ManaColors.textSecondary)),
                        ),
                      )
                    else
                      ...state.filtered.map((i) => _InvestorRow(
                            investor: i,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    InvestorProfileScreen(businessId: widget.businessId, investor: i),
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

class _DashboardStrip extends StatelessWidget {
  final InvestorWorkforceState state;
  const _DashboardStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String, ManaStatus)>[
      ('Total', '${state.total}', ManaStatus.neutral),
      ('Active', '${state.active}', ManaStatus.good),
      ('Pending Invitations', '${state.pendingInvitations}', ManaStatus.warn),
      ('Pending Acceptance', '${state.pendingAcceptance}', ManaStatus.warn),
      ('Suspended', '${state.suspended}', ManaStatus.bad),
      ('Total Investment', _currency.format(state.totalInvestment), ManaStatus.neutral),
      ('Interest Payable', _currency.format(state.interestPayable), ManaStatus.neutral),
    ];
    return ManaStatStrip(
      valueFontSize: 16,
      stats: [
        for (final (label, value, status) in stats)
          ManaStat(value: value, label: label, status: status),
      ],
    );
  }
}

class _StatusFilterChips extends ConsumerWidget {
  final InvestorWorkforceState state;
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
          onSelected: (_) => ref.read(investorWorkforceProvider.notifier).setStatusFilter(null),
        ),
        ..._statuses.map((s) => ChoiceChip(
              label: ManaText(s),
              selected: state.statusFilter == s,
              onSelected: (_) => ref.read(investorWorkforceProvider.notifier).setStatusFilter(s),
            )),
      ],
    );
  }
}

class _PendingRequestCard extends ConsumerWidget {
  final String businessId;
  final InvestorSummary investor;
  const _PendingRequestCard({required this.businessId, required this.investor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: ManaColors.statusWarnFaint,
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ManaVerificationRing(isVerified: true, size: 36),
                const SizedBox(width: ManaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(investor.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ManaText.raw(investor.mlid,
                          style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => NetworkErrorHandler.run(context, () async {
                      return ref
                          .read(investorWorkforceProvider.notifier)
                          .rejectRequest(businessId, investor.investorId);
                    }),
                    child: const ManaText('reject'),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => NetworkErrorHandler.run(context, () async {
                      return ref
                          .read(investorWorkforceProvider.notifier)
                          .approveRequest(businessId, investor.investorId);
                    }),
                    child: const ManaText('approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvestorRow extends StatelessWidget {
  final InvestorSummary investor;
  final VoidCallback onTap;
  const _InvestorRow({required this.investor, required this.onTap});

  ManaStatus get _statusKind => switch (investor.membershipStatus) {
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
        title: ManaText.raw(investor.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: ManaText.raw(
          '${investor.mlid} · ${_currency.format(investor.investmentBalance)} @ ${roiLabel(investor.roi)}',
          style: const TextStyle(fontSize: 16, color: ManaColors.textSecondary),
        ),
        trailing: ManaStatusPill(label: investor.membershipStatus, status: _statusKind),
        onTap: onTap,
      ),
    );
  }
}

class _AddExistingInvestorSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _AddExistingInvestorSheet({required this.businessId});

  @override
  ConsumerState<_AddExistingInvestorSheet> createState() => _AddExistingInvestorSheetState();
}

class _AddExistingInvestorSheetState extends ConsumerState<_AddExistingInvestorSheet> {
  final _mlid = TextEditingController();
  InvestorSummary? _found;
  bool _searching = false;
  bool _adding = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(investorWorkforceProvider.notifier).searchByMlid(_mlid.text.trim());
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
      return ref.read(investorWorkforceProvider.notifier).addExisting(widget.businessId, _found!.personId!);
    });
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok == true && mounted) Navigator.of(context).pop();
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
            const ManaText('add existing investor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  onPressed: (_mlid.text.trim().isNotEmpty && !_searching) ? _search : null,
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const ManaText('search'),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.lg),
            if (_found != null)
              Card(
                child: ListTile(
                  leading: const ManaVerificationRing(isVerified: true, size: 40),
                  title: ManaText.raw(_found!.fullName),
                  subtitle: ManaText.raw(_found!.mlid),
                  trailing: ElevatedButton(
                    onPressed: _adding ? null : _add,
                    child: _adding
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const ManaText('add'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- C6 Investor Profile ---------------------------------------------

class InvestorProfileScreen extends ConsumerWidget {
  final String businessId;
  final InvestorSummary investor;
  const InvestorProfileScreen({super.key, required this.businessId, required this.investor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(investorProfileProvider(investor.investorId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(investor.fullName),
          bottom: const TabBar(tabs: [Tab(text: 'Overview'), Tab(text: 'Investments')]),
          actions: [
            PopupMenuButton<String>(
              onSelected: (status) => _changeStatus(context, ref, status),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Active', child: ManaText('reactivate')),
                PopupMenuItem(value: 'Temporarily Disabled', child: ManaText('disable')),
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
            child: ManaText.raw('Could not load profile.\n$e', textAlign: TextAlign.center),
          )),
          data: (profile) => TabBarView(
            children: [
              _OverviewTab(investor: investor),
              _InvestmentsTab(investorId: investor.investorId, profile: profile),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText('confirm: ${status.toLowerCase()}'),
        content: ManaText.raw('Change ${investor.fullName}\'s membership status to "$status"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const ManaText('cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const ManaText('confirm')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(investorWorkforceProvider.notifier).updateStatus(businessId, investor.investorId, status);
    });
  }
}

class _OverviewTab extends StatelessWidget {
  final InvestorSummary investor;
  const _OverviewTab({required this.investor});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const Center(child: ManaVerificationRing(isVerified: true, size: 72)),
        const SizedBox(height: ManaSpacing.md),
        Center(
            child:
                ManaText.raw(investor.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        Center(child: ManaText.raw(investor.mlid, style: const TextStyle(color: ManaColors.textSecondary))),
        const SizedBox(height: ManaSpacing.lg),
        _row('Phone Number', investor.phoneNumber),
        _row('Investment Balance', _currency.format(investor.investmentBalance)),
        _row('ROI', roiLabel(investor.roi)),
        _row('ROI, yearly equivalent', roiAnnualEquivalent(investor.roi)),
        _row('Interest Due', _currency.format(investor.interestDue)),
        _row('Membership Status', investor.membershipStatus),
        _row('Last Transaction',
            investor.lastTransaction == null ? '—' : DateFormat('d MMM yyyy').format(investor.lastTransaction!)),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );
}

class _InvestmentsTab extends ConsumerWidget {
  final String investorId;
  final InvestorProfile profile;
  const _InvestmentsTab({required this.investorId, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A Removed/Suspended/Pending investor should never be able to have
    // a NEW investment recorded against them — that produced exactly the
    // wrong-info case reported: recording an investment for a Removed
    // investor makes them show an active-looking balance while still
    // carrying Removed status everywhere else (Investor Management's
    // list, the dashboard's active-investor count, etc.).
    final isActive = profile.summary.membershipStatus == 'Active';
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ElevatedButton.icon(
          onPressed: isActive ? () => _showInvestDialog(context, ref) : null,
          icon: const Icon(Icons.add),
          label: const ManaText('record investment'),
        ),
        if (!isActive)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: ManaText.raw(
              'Only Active investors can have new investments recorded (current status: ${profile.summary.membershipStatus}).',
              style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ),
        const SizedBox(height: ManaSpacing.lg),
        if (profile.investments.isEmpty)
          const ManaText.raw('No investments recorded yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...profile.investments.map((inv) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ManaText.raw(_currency.format(inv.principalAmount),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          ManaStatusPill(
                            label: inv.status,
                            status: inv.status == 'Active' ? ManaStatus.good : ManaStatus.neutral,
                          ),
                          // Correcting a mis-typed investment. Edit keeps
                          // the old values in audit_log (BR-169's pattern
                          // for loans); Delete refuses once any interest
                          // payment or withdrawal exists, because that is
                          // money movement and BR-002 makes it permanent.
                          PopupMenuButton<String>(
                            tooltip: 'Investment options',
                            onSelected: (v) => v == 'edit'
                                ? _showInvestDialog(context, ref, existing: inv)
                                : _confirmDeleteInvestment(context, ref, inv),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: ManaText('edit investment')),
                              PopupMenuItem(
                                value: 'delete',
                                child: ManaText.raw('delete investment',
                                    style: TextStyle(color: ManaColors.statusBad)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      ManaText.raw(
                        '${roiLabel(inv.roiRate)} · ${inv.interestMethod} · since ${DateFormat('d MMM yyyy').format(inv.effectiveDate)}',
                        style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: _small('Accrued', _currency.format(inv.interestAccrued))),
                          Expanded(child: _small('Paid', _currency.format(inv.interestPaid))),
                        ],
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              // S7/S8 — enabled only when balance >= ₹1.00
                              onPressed: inv.principalAmount >= 1
                                  ? () => _showWithdrawDialog(context, ref, inv)
                                  : null,
                              child: const ManaText('withdraw'),
                            ),
                          ),
                          // BUG FIXED this pass: declareProfitShare/
                          // payProfitShare were fully implemented in
                          // investor_state.dart but never surfaced here —
                          // only shown when this investment actually has
                          // a profit-share agreement (percent > 0).
                          if ((inv.profitSharePercent ?? 0) > 0) ...[
                            const SizedBox(width: ManaSpacing.sm),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => _ProfitShareSheet(investment: inv),
                                ),
                                child: const ManaText('profit share'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _small(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText(label, style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );

  Future<void> _confirmDeleteInvestment(
      BuildContext context, WidgetRef ref, InvestmentRecord inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('delete investment?'),
        content: ManaText.raw(
          '${_currency.format(inv.principalAmount)} at ${roiLabel(inv.roiRate)}, '
          'effective ${DateFormat('d MMM yyyy').format(inv.effectiveDate)}.\n\n'
          'This removes the record entirely. It is refused if any interest '
          'payment or withdrawal has been made against it — correct those '
          'with Edit instead.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const ManaText('cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.of(context).pop(true),
            child: const ManaText('delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(investorProfileProvider(investorId).notifier)
          .deleteInvestment(investmentId: inv.investmentId);
    });
  }

  /// Records a new investment, or corrects an existing one when `existing`
  /// is supplied — same fields either way, so they share one dialog.
  Future<void> _showInvestDialog(BuildContext context, WidgetRef ref,
      {InvestmentRecord? existing}) async {
    final amount = TextEditingController(
        text: existing == null ? '' : existing.principalAmount.toStringAsFixed(0));
    final roi =
        TextEditingController(text: existing == null ? '' : existing.roiRate.toString());
    String method = existing?.interestMethod ?? 'Simple';
    // Defaults to today, but backdateable — a business onboarding onto
    // this app after already running for years needs to record
    // investments that started well before "today" (e.g. this investor's
    // original entry date), not just brand-new ones.
    DateTime effectiveDate = existing?.effectiveDate ?? DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: ManaText(existing == null ? 'record investment' : 'edit investment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount *'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: roi,
                // decimal:true — the plain number keyboard on Android has
                // no decimal point, and this field is routinely a fraction
                // (₹1.50 per 100).
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'ROI — ₹ per 100 per month *',
                  helperText: 'e.g. 1.5 means ₹1.50 per ₹100 each month',
                ),
                onChanged: (_) => setState(() {}),
              ),
              // The yearly number is the one most people sanity-check
              // against, so show it live rather than making the Owner do
              // x12 in their head while deciding whether they typed it
              // right.
              if (double.tryParse(roi.text.trim()) != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ManaText.raw(
                      '= ${roiAnnualEquivalent(double.parse(roi.text.trim()))}',
                      style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                    ),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Interest Method'),
                items: const [
                  DropdownMenuItem(value: 'Simple', child: Text('Simple')),
                  DropdownMenuItem(value: 'Yearly Compound', child: Text('Yearly Compound')),
                ],
                onChanged: (v) => setState(() => method = v ?? 'Simple'),
              ),
              const SizedBox(height: ManaSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const ManaText('Effective Date'),
                subtitle: ManaText.raw(DateFormat('d MMM yyyy').format(effectiveDate)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: effectiveDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => effectiveDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            // Was always enabled, and the parse failure afterwards just
            // `return`ed — a second silent no-op on top of the schema one.
            // Gate the button on the values actually parsing instead.
            ElevatedButton(
              onPressed: (double.tryParse(amount.text.trim()) != null &&
                      double.tryParse(roi.text.trim()) != null)
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const ManaText('save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amt = double.tryParse(amount.text.trim());
    final r = double.tryParse(roi.text.trim());
    if (amt == null || r == null) return;
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final notifier = ref.read(investorProfileProvider(investorId).notifier);
      return existing == null
          ? notifier.recordInvestment(
              amount: amt,
              roiRate: r,
              interestMethod: method,
              effectiveDate: effectiveDate.toIso8601String(),
            )
          : notifier.editInvestment(
              investmentId: existing.investmentId,
              amount: amt,
              roiRate: r,
              interestMethod: method,
              effectiveDate: effectiveDate.toIso8601String(),
            );
    });
  }

  Future<void> _showWithdrawDialog(BuildContext context, WidgetRef ref, InvestmentRecord inv) async {
    final amount = TextEditingController();
    String type = 'Interest Only';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const ManaText('request withdrawal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount * (cannot exceed available balance)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Withdrawal Type'),
                items: const [
                  DropdownMenuItem(value: 'Interest Only', child: Text('Interest Only')),
                  DropdownMenuItem(value: 'Principal Partial', child: Text('Principal Partial')),
                  DropdownMenuItem(value: 'Principal Full', child: Text('Principal Full')),
                  DropdownMenuItem(value: 'Principal + Interest', child: Text('Principal + Interest')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'Interest Only'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('submit')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final amt = double.tryParse(amount.text.trim());
    if (amt == null || amt > inv.principalAmount) return; // BR-252: withdrawals cannot exceed available balance
    if (!context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(investorProfileProvider(investorId).notifier)
          .requestWithdrawal(investmentId: inv.investmentId, amount: amt, withdrawalType: type);
    });
  }
}

class _ProfitShareSheet extends ConsumerStatefulWidget {
  final InvestmentRecord investment;
  const _ProfitShareSheet({required this.investment});

  @override
  ConsumerState<_ProfitShareSheet> createState() => _ProfitShareSheetState();
}

class _ProfitShareSheetState extends ConsumerState<_ProfitShareSheet> {
  late Future<List<ProfitShareDeclaration>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ProfitShareDeclaration>> _load() {
    return ref.read(investorApiServiceProvider).fetchProfitShareDeclarations(investmentId: widget.investment.investmentId);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _declare() async {
    final amountController = TextEditingController();
    final remarksController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText('declare profit share'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw('${widget.investment.profitSharePercent}% of total profit for this period',
                style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total Profit Amount *'),
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(controller: remarksController, decoration: const InputDecoration(labelText: 'Remarks')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const ManaText('cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const ManaText('declare')),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final amt = double.tryParse(amountController.text.trim());
    if (amt == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).declareProfitShare(
            investmentId: widget.investment.investmentId,
            totalProfitAmount: amt,
            remarks: remarksController.text.trim().isEmpty ? null : remarksController.text.trim(),
          );
      return true;
    });
    if (ok == true) _reload();
  }

  Future<void> _pay(ProfitShareDeclaration decl) async {
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).payProfitShare(declarationId: decl.declarationId);
      return true;
    });
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: ManaText('profit share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                FilledButton.tonalIcon(onPressed: _declare, icon: const Icon(Icons.add, size: 18), label: const ManaText('declare')),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            Expanded(
              child: FutureBuilder<List<ProfitShareDeclaration>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final declarations = snapshot.data ?? const [];
                  if (declarations.isEmpty) {
                    return const Center(
                      child: ManaText.raw('No profit share declared yet.', style: TextStyle(color: ManaColors.textSecondary)),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: declarations.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final d = declarations[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: ManaText.raw(_currency.format(d.declaredAmount)),
                        subtitle: ManaText.raw(
                            '${DateFormat('d MMM yyyy').format(d.businessDate)} · of ${_currency.format(d.totalProfitAmount)} total'),
                        trailing: d.status == 'Declared'
                            ? FilledButton(onPressed: () => _pay(d), child: const ManaText('pay'))
                            : const ManaStatusPill(label: 'Paid', status: ManaStatus.good),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

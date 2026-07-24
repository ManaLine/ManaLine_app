import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/investor_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-003 — Investor Management. Register New Investor is
/// Investor-initiated (LOCKED CORRECTION in spec) — this screen's C4 is
/// therefore an Approve/Reject queue over incoming requests, not a create
/// form; C5 Add Existing mirrors OW-002's MLID search pattern.
class InvestorManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  const InvestorManagementScreen({super.key, required this.businessId});

  @override
  ConsumerState<InvestorManagementScreen> createState() => _InvestorManagementScreenState();
}

class _InvestorManagementScreenState extends ConsumerState<InvestorManagementScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(investorWorkforceProvider.notifier).load(widget.businessId);
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
            icon: const Icon(Icons.savings_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AddExistingInvestorSheet(businessId: widget.businessId),
            ),
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
                    if (state.filtered.isEmpty)
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
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: ManaSpacing.sm),
        itemBuilder: (context, i) {
          final (label, value, status) = stats[i];
          return Card(
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(ManaSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ManaStatusPill(label: label, status: status),
                ],
              ),
            ),
          );
        },
      ),
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
                          style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
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
          '${investor.mlid} · ${_currency.format(investor.investmentBalance)} @ ${investor.roi}%',
          style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary),
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
      return ref.read(investorWorkforceProvider.notifier).addExisting(widget.businessId, _found!.investorId);
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(investor.fullName),
          bottom: const TabBar(tabs: [Tab(text: 'Overview'), Tab(text: 'Investments'), Tab(text: 'Membership')]),
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
              _MembershipTab(investor: investor),
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
        _row('ROI', '${investor.roi}%'),
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
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ElevatedButton.icon(
          onPressed: () => _showInvestDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const ManaText('record investment'),
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
                        ],
                      ),
                      ManaText.raw(
                        '${inv.roiRate}% ROI · ${inv.interestMethod} · since ${DateFormat('d MMM yyyy').format(inv.effectiveDate)}',
                        style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary),
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: _small('Accrued', _currency.format(inv.interestAccrued))),
                          Expanded(child: _small('Paid', _currency.format(inv.interestPaid))),
                        ],
                      ),
                      const SizedBox(height: ManaSpacing.sm),
                      OutlinedButton(
                        // S7/S8 — enabled only when balance >= ₹1.00
                        onPressed: inv.principalAmount >= 1
                            ? () => _showWithdrawDialog(context, ref, inv)
                            : null,
                        child: const ManaText('withdraw'),
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
          ManaText(label, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
          ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );

  Future<void> _showInvestDialog(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    final roi = TextEditingController();
    String method = 'Simple';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const ManaText('record investment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount *'),
              ),
              TextField(
                controller: roi,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ROI % *'),
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const ManaText('cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const ManaText('save')),
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
      return ref.read(investorProfileProvider(investorId).notifier).recordInvestment(
            amount: amt,
            roiRate: r,
            interestMethod: method,
            effectiveDate: DateTime.now().toIso8601String(),
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

class _MembershipTab extends StatelessWidget {
  final InvestorSummary investor;
  const _MembershipTab({required this.investor});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'One Investor may invest in multiple Businesses; each Business keeps a '
          'fully independent Investment Ledger (BR-247–250).',
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.md),
        Card(
          child: ListTile(
            title: const ManaText('this business'),
            subtitle: ManaText.raw(investor.membershipStatus),
            trailing: ManaStatusPill(
              label: investor.membershipStatus,
              status: investor.membershipStatus == 'Active' ? ManaStatus.good : ManaStatus.neutral,
            ),
          ),
        ),
      ],
    );
  }
}

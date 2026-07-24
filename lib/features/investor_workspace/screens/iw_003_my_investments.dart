import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/my_investments_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

/// IW-003 — My Investments. List (S1) + Detail View (S2, drilled in on
/// the same screen) + Empty (S3 — Active Membership exists but Owner
/// hasn't recorded an Investment via OW-003 → INVEST yet).
///
/// Reachable directly from IW-005 My Profile/Memberships (locked this
/// session, not built here) by tapping an Investor-role membership —
/// that entry point pre-scopes this screen to a single businessId, which
/// is exactly what the required `businessId` constructor param already
/// does; no separate "entry mode" is needed.
class MyInvestmentsScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String investorId;
  const MyInvestmentsScreen({super.key, required this.businessId, required this.investorId});

  @override
  ConsumerState<MyInvestmentsScreen> createState() => _MyInvestmentsScreenState();
}

class _MyInvestmentsScreenState extends ConsumerState<MyInvestmentsScreen> {
  String? _selectedInvestmentId;

  ({String businessId, String investorId}) get _key =>
      (businessId: widget.businessId, investorId: widget.investorId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(myInvestmentsListProvider(_key).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedInvestmentId != null) {
      return _InvestmentDetailScreen(
        investmentId: _selectedInvestmentId!,
        onBack: () => setState(() => _selectedInvestmentId = null),
      );
    }

    final state = ref.watch(myInvestmentsListProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('my investments'),
        leading: BackButton(onPressed: () => context.go('/iw-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(myInvestmentsListProvider(_key).notifier).load(),
          child: state.loading && state.investments.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.investments.isEmpty
                  ? _errorState(context)
                  : state.isEmpty
                      // S3 Empty
                      ? _emptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(ManaSpacing.lg),
                          itemCount: state.investments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.sm),
                          itemBuilder: (context, i) =>
                              _InvestmentListCard(investment: state.investments[i], onTap: () {
                            setState(() => _selectedInvestmentId = state.investments[i].investmentId);
                          }),
                        ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.savings_outlined, size: 48, color: ManaColors.textSecondary),
                  const SizedBox(height: ManaSpacing.md),
                  const ManaText('no investments recorded yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: ManaSpacing.sm),
                  const ManaText.raw(
                    "Your Business Membership is active. The Owner records "
                    "the actual investment (Amount, ROI, Interest Method) "
                    "after receiving funds offline — it will appear here "
                    "once entered.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ManaColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load investments'),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(
              onPressed: () => ref.read(myInvestmentsListProvider(_key).notifier).load(),
              child: const ManaText('retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S1 INVESTMENT LIST ---------------------------------------------------

class _InvestmentListCard extends StatelessWidget {
  final InvestorInvestmentSummary investment;
  final VoidCallback onTap;
  const _InvestmentListCard({required this.investment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: ManaText.raw(_currency.format(investment.principalAmount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ManaStatusPill(
              label: investment.status,
              status: investment.status == 'Active' ? ManaStatus.good : ManaStatus.neutral,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                '${investment.investmentId} · ${investment.roiRate}% ROI · ${investment.interestMethod} · since ${_dateFmt.format(investment.effectiveDate)}',
                style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ManaText.raw('Accrued: ${_currency.format(investment.interestAccrued)}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: ManaText.raw('Paid: ${_currency.format(investment.interestPaid)}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        isThreeLine: true,
      ),
    );
  }
}

// --- S2 INVESTMENT DETAIL VIEW ---------------------------------------------

class _InvestmentDetailScreen extends ConsumerWidget {
  final String investmentId;
  final VoidCallback onBack;
  const _InvestmentDetailScreen({required this.investmentId, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(investmentDetailProvider(investmentId));

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('investment detail'),
        leading: BackButton(onPressed: onBack),
        actions: [
          IconButton(
            tooltip: 'Download Statement',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => NetworkErrorHandler.run(context, () async {
              final url = await ref.read(investmentDetailProvider(investmentId).notifier).downloadStatement();
              if (url == null) throw Exception('Statement download failed');
              return url;
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ManaText('could not load investment detail'),
                  const SizedBox(height: ManaSpacing.sm),
                  ElevatedButton(
                    onPressed: () => ref.read(investmentDetailProvider(investmentId).notifier).refresh(),
                    child: const ManaText('retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (detail) => RefreshIndicator(
            onRefresh: () => ref.read(investmentDetailProvider(investmentId).notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                _AgreementSnapshotCard(snapshot: detail.agreementSnapshot, profitSharePercent: detail.profitSharePercent),
                const SizedBox(height: ManaSpacing.lg),
                _InterestLedgerSection(entries: detail.interestLedger),
                const SizedBox(height: ManaSpacing.lg),
                _WithdrawalHistorySection(entries: detail.withdrawalHistory),
                // Distribution History — only rendered when
                // profit_share_percent is enabled for THIS investment
                // (per-investment, not a global toggle).
                if (detail.hasProfitShare) ...[
                  const SizedBox(height: ManaSpacing.lg),
                  _DistributionHistorySection(entries: detail.distributionHistory),
                ],
                const SizedBox(height: ManaSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/iw-004', extra: investmentId),
                    icon: const Icon(Icons.request_page_outlined),
                    label: const ManaText('request withdrawal'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Agreement Snapshot (frozen terms — BR-034, never live-recalculated) --

class _AgreementSnapshotCard extends StatelessWidget {
  final AgreementSnapshot snapshot;
  final double? profitSharePercent;
  const _AgreementSnapshotCard({required this.snapshot, this.profitSharePercent});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('agreement snapshot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const ManaText.raw('Frozen terms at time of investment — never live-recalculated.',
                style: TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            _row('Original Principal Amount', _currency.format(snapshot.originalPrincipalAmount)),
            _row('ROI Rate', '${snapshot.roiRate}%'),
            _row('Interest Type', snapshot.interestType),
            _row('Effective Date', _dateFmt.format(snapshot.effectiveDate)),
            if (profitSharePercent != null) _row('Profit Share %', '${profitSharePercent}%'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: ManaText(label, style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}

// --- Interest Ledger --------------------------------------------------

class _InterestLedgerSection extends StatelessWidget {
  final List<InterestLedgerEntry> entries;
  const _InterestLedgerSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('interest ledger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              const ManaText.raw('No interest ledger entries yet.', style: TextStyle(color: ManaColors.textSecondary))
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ManaText(e.entryType, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ManaText.raw(_dateFmt.format(e.businessDate),
                                  style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                              if (e.remarks != null && e.remarks!.isNotEmpty)
                                ManaText.raw(e.remarks!, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ManaText.raw(_currency.format(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ManaStatusPill(
                                label: e.ownerVerified ? 'Owner Verified' : 'Not Verified',
                                status: e.ownerVerified ? ManaStatus.good : ManaStatus.warn,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// --- Withdrawal History (this investment only) --------------------------

class _WithdrawalHistorySection extends StatelessWidget {
  final List<InvestmentWithdrawalHistoryEntry> entries;
  const _WithdrawalHistorySection({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('withdrawal history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              const ManaText.raw('No withdrawals recorded yet.', style: TextStyle(color: ManaColors.textSecondary))
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ManaText(e.withdrawalType, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ManaText.raw(
                                '${_dateFmt.format(e.businessDate)} · Approved by ${e.approvedBy}',
                                style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                              ),
                              if (e.remarks != null && e.remarks!.isNotEmpty)
                                ManaText.raw(e.remarks!, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ManaText.raw(_currency.format(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// --- Distribution History (Profit Share) — two-stage: Declared, Paid ---

class _DistributionHistorySection extends StatelessWidget {
  final List<DistributionHistoryEntry> entries;
  const _DistributionHistorySection({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText('distribution history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const ManaText.raw(
              'Profit Share — Declaration and Payment are recorded separately; '
              'a row may show Declared with no Paid data yet.',
              style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              const ManaText.raw('No profit share declarations yet.', style: TextStyle(color: ManaColors.textSecondary))
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ManaText.raw('Declared: ${_currency.format(e.declaredAmount)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            ManaStatusPill(
                              label: e.declaredStatus,
                              status: e.isPaid ? ManaStatus.good : ManaStatus.warn,
                            ),
                          ],
                        ),
                        ManaText.raw(_dateFmt.format(e.declaredDate),
                            style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                        if (e.isPaid) ...[
                          const SizedBox(height: 4),
                          ManaText.raw(
                            'Paid: ${_currency.format(e.paidAmount ?? 0)} on ${_dateFmt.format(e.paidDate!)}'
                            '${(e.paidInterestAmount ?? 0) > 0 ? ' (+ ${_currency.format(e.paidInterestAmount!)} interest on unpaid gap)' : ''}',
                            style: const TextStyle(fontSize: 12, color: ManaColors.statusGood),
                          ),
                        ],
                        const Divider(height: ManaSpacing.lg),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/translation_service.dart';
import '../state/my_investments_state.dart';

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
  const MyInvestmentsScreen(
      {super.key, required this.businessId, required this.investorId});

  @override
  ConsumerState<MyInvestmentsScreen> createState() =>
      _MyInvestmentsScreenState();
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
        title: ManaText.raw(ref.t('my_investments')),
        leading: BackButton(
            onPressed: () => context.go('/iw-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(myInvestmentsListProvider(_key).notifier).load(),
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: ManaSpacing.sm),
                          itemBuilder: (context, i) => _InvestmentListCard(
                              investment: state.investments[i],
                              onTap: () {
                                setState(() => _selectedInvestmentId =
                                    state.investments[i].investmentId);
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
                  Icon(Icons.savings_outlined,
                      size: 48, color: ManaColors.textSecondary),
                  const SizedBox(height: ManaSpacing.md),
                  ManaText.raw(ref.t('no_investments_recorded_yet'),
                      style:
                          ManaType.cardTitle),
                  const SizedBox(height: ManaSpacing.sm),
                  ManaText.raw(
                    ref.t('no_investments_note'),
                    textAlign: TextAlign.center,
                    style: ManaType.secondary,
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
            Icon(Icons.cloud_off,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('could_not_load_investments')),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(
              onPressed: () =>
                  ref.read(myInvestmentsListProvider(_key).notifier).load(),
              child: ManaText.raw(ref.t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S1 INVESTMENT LIST ---------------------------------------------------

class _InvestmentListCard extends ConsumerWidget {
  final InvestorInvestmentSummary investment;
  final VoidCallback onTap;
  const _InvestmentListCard({required this.investment, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: ManaText.raw(manaRupees(investment.principalAmount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ManaStatusPill(
              label: investment.status,
              status: investment.status == 'Active'
                  ? ManaStatus.good
                  : ManaStatus.neutral,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                ref
                    .t('investment_meta_note')
                    .replaceAll('{id}', investment.investmentId)
                    .replaceAll('{roi}', roiLabel(investment.roiRate))
                    .replaceAll('{method}', investment.interestMethod)
                    .replaceAll('{date}', _dateFmt.format(investment.effectiveDate)),
                style: TextStyle(
                    fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ManaText.raw(
                        ref
                            .t(investment.isCompound ? 'accrued_this_year_note' : 'accrued_note')
                            .replaceAll('{amount}', manaRupees(investment.interestAccrued))
                            .replaceAll('{total}', manaRupees(investment.totalInterestEarned)),
                        style: const TextStyle(fontSize: 16)),
                  ),
                  Expanded(
                    child: ManaText.raw(
                        ref.t('paid_short_note').replaceAll('{amount}', manaRupees(investment.interestPaid)),
                        style: const TextStyle(fontSize: 16)),
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
  const _InvestmentDetailScreen(
      {required this.investmentId, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(investmentDetailProvider(investmentId));

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('investment_detail')),
        leading: BackButton(onPressed: onBack),
        actions: [
          IconButton(
            tooltip: ref.t('view_statement'),
            icon: const Icon(Icons.download_outlined),
            // BUG FIXED this pass: this made a real network round trip
            // (get_investment_statement RPC) and then just discarded the
            // result — no save, no share, no viewer, tapping visibly did
            // nothing. The RPC itself only ever returned raw JSON for
            // client-side formatting (see its own migration comment),
            // never a downloadable file, so this shows it in-app rather
            // than pretending a "download" happened.
            onPressed: () async {
              final raw = await NetworkErrorHandler.run(context, () async {
                final result = await ref.read(investmentDetailProvider(investmentId).notifier).downloadStatement();
                if (result == null) throw Exception('Statement could not be loaded.');
                return result;
              });
              if (raw == null || !context.mounted) return;
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _StatementSheet(json: raw),
              );
            },
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
                  ManaText.raw(ref.t('could_not_load_investment_detail')),
                  const SizedBox(height: ManaSpacing.sm),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(investmentDetailProvider(investmentId).notifier)
                        .refresh(),
                    child: ManaText.raw(ref.t('retry')),
                  ),
                ],
              ),
            ),
          ),
          data: (detail) => RefreshIndicator(
            onRefresh: () => ref
                .read(investmentDetailProvider(investmentId).notifier)
                .refresh(),
            child: ListView(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              children: [
                _AgreementSnapshotCard(
                    snapshot: detail.agreementSnapshot,
                    profitSharePercent: detail.profitSharePercent),
                const SizedBox(height: ManaSpacing.lg),
                _InterestLedgerSection(entries: detail.interestLedger),
                const SizedBox(height: ManaSpacing.lg),
                _WithdrawalHistorySection(entries: detail.withdrawalHistory),
                // Distribution History — only rendered when
                // profit_share_percent is enabled for THIS investment
                // (per-investment, not a global toggle).
                if (detail.hasProfitShare) ...[
                  const SizedBox(height: ManaSpacing.lg),
                  _DistributionHistorySection(
                      entries: detail.distributionHistory),
                ],
                const SizedBox(height: ManaSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/iw-004', extra: investmentId),
                    icon: const Icon(Icons.request_page_outlined),
                    label: ManaText.raw(ref.t('request_withdrawal')),
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

class _StatementSheet extends ConsumerWidget {
  final String json;
  const _StatementSheet({required this.json});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }
    final ledger = (data?['interest_ledger'] as List?) ?? const [];
    final distributions = (data?['distributions'] as List?) ?? const [];
    final withdrawals = (data?['withdrawal_requests'] as List?) ?? const [];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: data == null
            ? Center(child: ManaText.raw(ref.t('could_not_read_statement')))
            : ListView(
                controller: scrollController,
                children: [
                  ManaText.raw(ref.t('statement'), style: ManaType.sheetTitle),
                  const SizedBox(height: ManaSpacing.md),
                  ManaText.raw(ref.t('interest_ledger'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: ManaSpacing.xs),
                  if (ledger.isEmpty)
                    ManaText.raw(ref.t('no_entries_yet'), style: ManaType.note)
                  else
                    ...ledger.map((e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: ManaText.raw('${e['entry_type']} · ${manaRupees((e['amount'] as num).toInt())}'),
                          subtitle: ManaText.raw('${e['business_date']}${e['remarks'] != null ? ' · ${e['remarks']}' : ''}',
                              style: const TextStyle(fontSize: 16)),
                        )),
                  const SizedBox(height: ManaSpacing.md),
                  ManaText.raw(ref.t('distributions'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: ManaSpacing.xs),
                  if (distributions.isEmpty)
                    ManaText.raw(ref.t('no_entries_yet'), style: ManaType.note)
                  else
                    ...distributions.map((d) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: ManaText.raw(
                              '${d['status']} · ${manaRupees((d['declared_amount'] as num).toInt())}'),
                          subtitle: ManaText.raw(
                              '${d['business_date']}${d['paid_amount'] != null ? ' · paid ${manaRupees((d['paid_amount'] as num).toInt())}' : ''}',
                              style: const TextStyle(fontSize: 16)),
                        )),
                  const SizedBox(height: ManaSpacing.md),
                  ManaText.raw(ref.t('withdrawal_requests'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: ManaSpacing.xs),
                  if (withdrawals.isEmpty)
                    ManaText.raw(ref.t('no_entries_yet'), style: ManaType.note)
                  else
                    ...withdrawals.map((w) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: ManaText.raw(
                              '${w['withdrawal_type']} · ${manaRupees((w['requested_amount'] as num).toDouble())}'),
                          subtitle: ManaText.raw('${w['status']} · ${w['created_at']}', style: const TextStyle(fontSize: 16)),
                        )),
                ],
              ),
      ),
    );
  }
}

// --- Agreement Snapshot (frozen terms — BR-034, never live-recalculated) --

class _AgreementSnapshotCard extends ConsumerWidget {
  final AgreementSnapshot snapshot;
  final double? profitSharePercent;
  const _AgreementSnapshotCard(
      {required this.snapshot, this.profitSharePercent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('agreement_snapshot'),
                style: ManaType.cardTitle),
            const SizedBox(height: 4),
            ManaText.raw(
                ref.t('frozen_terms_note'),
                style:
                    ManaType.note),
            const SizedBox(height: ManaSpacing.md),
            _row(ref.t('original_principal_amount'),
                manaRupees(snapshot.originalPrincipalAmount)),
            _row(ref.t('roi_rate'), roiLabel(snapshot.roiRate)),
            _row(ref.t('yearly_equivalent'), roiAnnualEquivalent(snapshot.roiRate)),
            _row(ref.t('interest_type'), snapshot.interestType),
            _row(ref.t('effective_date'), _dateFmt.format(snapshot.effectiveDate)),
            if (profitSharePercent != null)
              _row(ref.t('profit_share_percent'), '$profitSharePercent%'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: ManaText.raw(label,
                    style: TextStyle(
                        color: ManaColors.textSecondary, fontSize: 13))),
            ManaText.raw(value,
                style:
                    ManaType.smallStrong),
          ],
        ),
      );
}

// --- Interest Ledger --------------------------------------------------

class _InterestLedgerSection extends ConsumerWidget {
  final List<InterestLedgerEntry> entries;
  const _InterestLedgerSection({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('interest_ledger'),
                style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              ManaText.raw(ref.t('no_interest_ledger_entries_yet'),
                  style: ManaType.secondary)
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
                              ManaText.raw(e.entryType,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              ManaText.raw(_dateFmt.format(e.businessDate),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: ManaColors.textSecondary)),
                              if (e.remarks != null && e.remarks!.isNotEmpty)
                                ManaText.raw(e.remarks!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: ManaColors.textSecondary)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ManaText.raw(manaRupees(e.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              ManaStatusPill(
                                label: ref.t(e.ownerVerified ? 'owner_verified' : 'not_verified'),
                                status: e.ownerVerified
                                    ? ManaStatus.good
                                    : ManaStatus.warn,
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

class _WithdrawalHistorySection extends ConsumerWidget {
  final List<InvestmentWithdrawalHistoryEntry> entries;
  const _WithdrawalHistorySection({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('withdrawal_history'),
                style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              ManaText.raw(ref.t('no_withdrawals_recorded_yet'),
                  style: ManaType.secondary)
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
                              ManaText.raw(e.withdrawalType,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              ManaText.raw(
                                ref
                                    .t('approved_by_note')
                                    .replaceAll('{date}', _dateFmt.format(e.businessDate))
                                    .replaceAll('{by}', e.approvedBy),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: ManaColors.textSecondary),
                              ),
                              if (e.remarks != null && e.remarks!.isNotEmpty)
                                ManaText.raw(e.remarks!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: ManaColors.textSecondary)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ManaText.raw(manaRupees(e.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
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

class _DistributionHistorySection extends ConsumerWidget {
  final List<DistributionHistoryEntry> entries;
  const _DistributionHistorySection({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('distribution_history'),
                style: ManaType.cardTitle),
            const SizedBox(height: 4),
            ManaText.raw(
              ref.t('profit_share_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.sm),
            if (entries.isEmpty)
              ManaText.raw(ref.t('no_profit_share_declarations_yet'),
                  style: ManaType.secondary)
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ManaText.raw(
                                  ref.t('declared_note').replaceAll('{amount}', manaRupees(e.declaredAmount)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16)),
                            ),
                            ManaStatusPill(
                              label: e.declaredStatus,
                              status:
                                  e.isPaid ? ManaStatus.good : ManaStatus.warn,
                            ),
                          ],
                        ),
                        ManaText.raw(_dateFmt.format(e.declaredDate),
                            style: TextStyle(
                                fontSize: 13, color: ManaColors.textSecondary)),
                        if (e.isPaid) ...[
                          const SizedBox(height: 4),
                          ManaText.raw(
                            ref
                                    .t('paid_note')
                                    .replaceAll('{amount}', manaRupees(e.paidAmount ?? 0))
                                    .replaceAll('{date}', _dateFmt.format(e.paidDate!)) +
                                ((e.paidInterestAmount ?? 0) > 0
                                    ? ref.t('paid_interest_extra').replaceAll('{amount}', manaRupees(e.paidInterestAmount!))
                                    : ''),
                            style: TextStyle(
                                fontSize: 16, color: ManaColors.statusGood),
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

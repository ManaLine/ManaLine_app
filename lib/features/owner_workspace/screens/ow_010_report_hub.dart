import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/report_hub_state.dart';

final _shortDateFmt = DateFormat('dd MMM');
const _monthKeys = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// OW-010 — Report Hub (Digital Record Book). One row per CLOSED
/// business-day-account, grouped by `day_closures.account_group_id`
/// when Day Closure was delayed across multiple calendar days — a
/// From/To date range, not a single Business Date. Never shows a
/// health/quality rating (locked principle — facts only).
///
/// Explicitly out of scope here: Customer Outstanding, Loan Portfolio,
/// Agent Status, Route Status, Finance-domain reporting — those live in
/// their own workspaces. NOT the same screen as OW-009 Daily Record Book
/// (which shows every raw, possibly-still-Open Business Day).
class ReportHubScreen extends ConsumerStatefulWidget {
  final String businessId;
  const ReportHubScreen({super.key, required this.businessId});

  @override
  ConsumerState<ReportHubScreen> createState() => _ReportHubScreenState();
}

class _ReportHubScreenState extends ConsumerState<ReportHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportHubProvider.notifier).loadMonth(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportHubProvider);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('report_hub'), homeRoute: '/ow-001'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(reportHubProvider.notifier).loadMonth(widget.businessId),
          child: Column(
            children: [
              _MonthSelector(
                year: state.selectedYear,
                month: state.selectedMonth,
                onChanged: (y, m) => ref
                    .read(reportHubProvider.notifier)
                    .loadMonth(widget.businessId, year: y, month: m),
              ),
              Expanded(
                child: state.loading && state.rows.isEmpty
                    ? const ManaSkeletonList()
                    : ListView(
                        padding: const EdgeInsets.all(ManaSpacing.lg),
                        children: [
                          if (state.monthlySummary != null)
                            _MonthlySummaryCard(summary: state.monthlySummary!),
                          const SizedBox(height: ManaSpacing.md),
                          if (state.rows.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: ManaSpacing.xxl),
                              child: Center(
                                child: ManaText.raw(
                                  ref.t('no_closed_accounts_this_month'),
                                  style: TextStyle(
                                      color: ManaColors.textSecondary),
                                ),
                              ),
                            )
                          else
                            ...state.rows.map((row) => Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: ManaSpacing.sm),
                                  child: _RecordBookRowCard(
                                    row: row,
                                    onTap: () => _openRowDetail(context, row),
                                  ),
                                )),
                          if (state.monthlyClosing != null) ...[
                            const SizedBox(height: ManaSpacing.md),
                            _MonthlyClosingCard(closing: state.monthlyClosing!),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRowDetail(BuildContext context, RecordBookRow row) async {
    await ref
        .read(reportHubProvider.notifier)
        .openRowDetail(widget.businessId, row.businessDayAccountId);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RowDetailSheet(businessId: widget.businessId, row: row),
    );
    ref.read(reportHubProvider.notifier).closeRowDetail();
  }
}

/// Annual archive navigation — Year → Month, permanently browsable per
/// OW-010's "Annual archive" section (nothing is ever deleted).
class _MonthSelector extends ConsumerWidget {
  final int year;
  final int month;
  final void Function(int year, int month) onChanged;
  const _MonthSelector(
      {required this.year, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentYear = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              final prevMonth = month == 1 ? 12 : month - 1;
              final prevYear = month == 1 ? year - 1 : year;
              onChanged(prevYear, prevMonth);
            },
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: Row(
                children: [
                  Flexible(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: month,
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                            value: i + 1,
                            child: ManaText.raw(ref.t(_monthKeys[i]),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ),
                      onChanged: (m) => m != null ? onChanged(year, m) : null,
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  Flexible(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: year,
                      items: List.generate(
                        6,
                        (i) => DropdownMenuItem(
                            value: currentYear - i,
                            child: ManaText.raw('${currentYear - i}')),
                      ),
                      onChanged: (y) => y != null ? onChanged(y, month) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final nextMonth = month == 12 ? 1 : month + 1;
              final nextYear = month == 12 ? year + 1 : year;
              onChanged(nextYear, nextMonth);
            },
          ),
        ],
      ),
    );
  }
}

class _MonthlySummaryCard extends ConsumerWidget {
  final MonthlySummary summary;
  const _MonthlySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.brandFaint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw('📅 ${ref.t(_monthKeys[summary.month - 1])} ${summary.year}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: ManaSpacing.sm),
          _line(ref.t('business_day_accounts'), '${summary.businessDayAccounts}'),
          _line(ref.t('total_collections'), manaRupees(summary.totalCollections)),
          _line(ref.t('total_loans_given'), manaRupees(summary.totalLoansGiven)),
          _line(ref.t('total_expenses'), manaRupees(summary.totalExpenses)),
          _line(ref.t('pending_customers'), '${summary.pendingCustomers}'),
          _line(ref.t('outstanding_amount'),
              manaRupees(summary.outstandingAmount)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: ManaText.raw(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: ManaSpacing.xs),
            ManaText.raw(value,
                style: ManaType.emphasis)
          ],
        ),
      );
}

class _MonthlyClosingCard extends ConsumerWidget {
  final MonthlyClosing closing;
  const _MonthlyClosingCard({required this.closing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.inkFaint,
        border: Border.all(color: ManaColors.ink, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(
            '${ref.t('monthly_closing').toUpperCase()} — ${ref.t(_monthKeys[closing.month - 1]).toUpperCase()} ${closing.year}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: ManaSpacing.sm),
          _line(ref.t('business_day_accounts'), '${closing.businessDayAccounts}'),
          _line(ref.t('collections'), manaRupees(closing.collections)),
          _line(ref.t('loans_given'), manaRupees(closing.loansGiven)),
          _line(ref.t('expenses'), manaRupees(closing.expenses)),
          _line(ref.t('net_cash_movement'), manaRupees(closing.netCashMovement)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: ManaText.raw(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: ManaSpacing.xs),
            ManaText.raw(value,
                style: ManaType.emphasis)
          ],
        ),
      );
}

class _RecordBookRowCard extends ConsumerWidget {
  final RecordBookRow row;
  final VoidCallback onTap;
  const _RecordBookRowCard({required this.row, required this.onTap});

  ManaStatus get _balanceStatus => switch (row.agentBalanceStatus) {
        'Balanced' => ManaStatus.good,
        'Short' => ManaStatus.bad,
        'Excess' => ManaStatus.warn,
        _ => ManaStatus.neutral,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = row.spansMultipleDays
        ? ref
            .t('from_to_date_range_note')
            .replaceAll('{from}', _shortDateFmt.format(row.dateFrom))
            .replaceAll('{to}', _shortDateFmt.format(row.dateTo))
        : _shortDateFmt.format(row.dateFrom);

    return Card(
      elevation: 0,
      color: ManaColors.surfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ManaText.raw(dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.heavy),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaStatusPill(
                        label: row.agentBalanceStatus, status: _balanceStatus),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              Wrap(
                spacing: ManaSpacing.lg,
                runSpacing: ManaSpacing.xs,
                children: [
                  _figure(ref.t('collections'), manaRupees(row.collectionsTotal)),
                  _figure(ref.t('loans_given'), manaRupees(row.loansGivenTotal)),
                  _figure(ref.t('expenses'), manaRupees(row.expensesTotal)),
                  _figure(ref.t('closing_cash'), manaRupees(row.closingCash)),
                  _figure(ref.t('pending_customers'), '${row.pendingCustomersCount}'),
                ],
              ),
              if (row.remarks != null && row.remarks!.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(row.remarks!,
                    style: TextStyle(
                        fontSize: 13, color: ManaColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(label,
              style: TextStyle(
                  fontSize: 13, color: ManaColors.textSecondary)),
          ManaText.raw(value,
              style:
                  ManaType.smallStrong),
        ],
      );
}

/// Row drill-down — full Daily Business Report detail (Collections,
/// Loans, Expenses, Agent Summary, Pending Customers, Corrections, Day
/// Closure Details), per ADDENDUM v5 §11.
class _RowDetailSheet extends ConsumerStatefulWidget {
  final String businessId;
  final RecordBookRow row;
  const _RowDetailSheet({required this.businessId, required this.row});

  @override
  ConsumerState<_RowDetailSheet> createState() => _RowDetailSheetState();
}

class _RowDetailSheetState extends ConsumerState<_RowDetailSheet> {
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportHubProvider);
    final detail = state.detail;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: state.detailLoading
              ? const Center(child: CircularProgressIndicator())
              : state.detailError != null
                  ? Center(
                      child: ManaText.raw(state.detailError!,
                          style: ManaType.bad))
                  : detail == null
                      ? const SizedBox.shrink()
                      : ListView(
                          controller: scrollController,
                          children: [
                            ManaText.raw(
                              widget.row.spansMultipleDays
                                  ? ref
                                      .t('from_to_date_range_note')
                                      .replaceAll('{from}', _shortDateFmt.format(widget.row.dateFrom))
                                      .replaceAll('{to}', _shortDateFmt.format(widget.row.dateTo))
                                  : _shortDateFmt.format(widget.row.dateFrom),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: ManaSpacing.md),
                            _section(ref.t('collections'), detail.collections),
                            _section(ref.t('loans'), detail.loans),
                            _section(ref.t('expenses'), detail.expenses),
                            const SizedBox(height: ManaSpacing.sm),
                            ManaText.raw(ref.t('agent_summary'),
                                style: ManaType.heavy),
                            ManaText.raw(detail.agentSummary.isEmpty
                                ? '—'
                                : detail.agentSummary),
                            const SizedBox(height: ManaSpacing.md),
                            _section(
                                ref.t('pending_customers'), detail.pendingCustomers),
                            _section(ref.t('corrections'), detail.corrections),
                            const SizedBox(height: ManaSpacing.sm),
                            ManaText.raw(ref.t('day_closure_details'),
                                style: ManaType.heavy),
                            ManaText.raw(detail.dayClosureDetails.isEmpty
                                ? '—'
                                : detail.dayClosureDetails),
                            const SizedBox(height: ManaSpacing.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _remarksController
                                      ..text = widget.row.remarks ?? '',
                                    decoration: InputDecoration(
                                      labelText: ref.t('remarks_optional_freeform_note'),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: ManaSpacing.sm),
                                Flexible(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: ManaColors.accent),
                                    onPressed: () async {
                                      final ok = await NetworkErrorHandler.run(
                                          context, () async {
                                        return ref
                                            .read(reportHubProvider.notifier)
                                            .updateRemarks(
                                              widget.businessId,
                                              widget.row.businessDayAccountId,
                                              _remarksController.text,
                                            );
                                      });
                                      if (ok == true && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: ManaText.raw(ref.t('remarks_saved_note'))));
                                      }
                                    },
                                    child: ManaText.raw(ref.t('save')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
        );
      },
    );
  }

  Widget _section(String title, List<ReportHubLineItem> items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(title,
                style: ManaType.heavy),
            ManaText.raw('—',
                style: ManaType.secondary),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(title, style: ManaType.heavy),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: ManaText.raw(e.label)),
                    ManaText.raw(manaRupees(e.amount)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

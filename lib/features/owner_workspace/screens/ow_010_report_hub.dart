import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/report_hub_state.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _shortDateFmt = DateFormat('dd MMM');
final _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
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
      appBar: AppBar(
        title: const ManaText('report hub'),
        leading: BackButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/ow-001')),
      ),
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
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(ManaSpacing.lg),
                        children: [
                          if (state.monthlySummary != null)
                            _MonthlySummaryCard(summary: state.monthlySummary!),
                          const SizedBox(height: ManaSpacing.md),
                          if (state.rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: ManaSpacing.xxl),
                              child: Center(
                                child: ManaText.raw(
                                  'No closed business-day-accounts this month yet.',
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
class _MonthSelector extends StatelessWidget {
  final int year;
  final int month;
  final void Function(int year, int month) onChanged;
  const _MonthSelector(
      {required this.year, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
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
            child: Center(
              child: DropdownButtonHideUnderline(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<int>(
                      value: month,
                      items: List.generate(
                        12,
                        (i) => DropdownMenuItem(
                            value: i + 1, child: ManaText(_monthNames[i])),
                      ),
                      onChanged: (m) => m != null ? onChanged(year, m) : null,
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    DropdownButton<int>(
                      value: year,
                      items: List.generate(
                        6,
                        (i) => DropdownMenuItem(
                            value: currentYear - i,
                            child: ManaText.raw('${currentYear - i}')),
                      ),
                      onChanged: (y) => y != null ? onChanged(y, month) : null,
                    ),
                  ],
                ),
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

class _MonthlySummaryCard extends StatelessWidget {
  final MonthlySummary summary;
  const _MonthlySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.brassFaint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw('📅 ${_monthNames[summary.month - 1]} ${summary.year}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: ManaSpacing.sm),
          _line('Business-Day-Accounts', '${summary.businessDayAccounts}'),
          _line(
              'Total Collections', _currency.format(summary.totalCollections)),
          _line('Total Loans Given', _currency.format(summary.totalLoansGiven)),
          _line('Total Expenses', _currency.format(summary.totalExpenses)),
          _line('Pending Customers', '${summary.pendingCustomers}'),
          _line('Outstanding Amount',
              _currency.format(summary.outstandingAmount)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText(label),
            ManaText.raw(value,
                style: const TextStyle(fontWeight: FontWeight.w600))
          ],
        ),
      );
}

class _MonthlyClosingCard extends StatelessWidget {
  final MonthlyClosing closing;
  const _MonthlyClosingCard({required this.closing});

  @override
  Widget build(BuildContext context) {
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
            'MONTHLY CLOSING — ${_monthNames[closing.month - 1].toUpperCase()} ${closing.year}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: ManaSpacing.sm),
          _line('Business-Day-Accounts', '${closing.businessDayAccounts}'),
          _line('Collections', _currency.format(closing.collections)),
          _line('Loans Given', _currency.format(closing.loansGiven)),
          _line('Expenses', _currency.format(closing.expenses)),
          _line('Net Cash Movement', _currency.format(closing.netCashMovement)),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ManaText(label),
            ManaText.raw(value,
                style: const TextStyle(fontWeight: FontWeight.w600))
          ],
        ),
      );
}

class _RecordBookRowCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final dateLabel = row.spansMultipleDays
        ? 'From: ${_shortDateFmt.format(row.dateFrom)}  To: ${_shortDateFmt.format(row.dateTo)}'
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
                children: [
                  Expanded(
                    child: ManaText.raw(dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ManaStatusPill(
                      label: row.agentBalanceStatus, status: _balanceStatus),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              Wrap(
                spacing: ManaSpacing.lg,
                runSpacing: ManaSpacing.xs,
                children: [
                  _figure(
                      'Collections', _currency.format(row.collectionsTotal)),
                  _figure('Loans Given', _currency.format(row.loansGivenTotal)),
                  _figure('Expenses', _currency.format(row.expensesTotal)),
                  _figure('Closing Cash', _currency.format(row.closingCash)),
                  _figure('Pending Customers', '${row.pendingCustomersCount}'),
                ],
              ),
              if (row.remarks != null && row.remarks!.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(row.remarks!,
                    style: const TextStyle(
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
          ManaText(label,
              style: const TextStyle(
                  fontSize: 13, color: ManaColors.textSecondary)),
          ManaText.raw(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                          style: const TextStyle(color: ManaColors.statusBad)))
                  : detail == null
                      ? const SizedBox.shrink()
                      : ListView(
                          controller: scrollController,
                          children: [
                            ManaText.raw(
                              widget.row.spansMultipleDays
                                  ? 'From: ${_shortDateFmt.format(widget.row.dateFrom)}  To: ${_shortDateFmt.format(widget.row.dateTo)}'
                                  : _shortDateFmt.format(widget.row.dateFrom),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: ManaSpacing.md),
                            _section('Collections', detail.collections),
                            _section('Loans', detail.loans),
                            _section('Expenses', detail.expenses),
                            const SizedBox(height: ManaSpacing.sm),
                            const ManaText('agent summary',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            ManaText.raw(detail.agentSummary.isEmpty
                                ? '—'
                                : detail.agentSummary),
                            const SizedBox(height: ManaSpacing.md),
                            _section(
                                'Pending Customers', detail.pendingCustomers),
                            _section('Corrections', detail.corrections),
                            const SizedBox(height: ManaSpacing.sm),
                            const ManaText('day closure details',
                                style: TextStyle(fontWeight: FontWeight.w700)),
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
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Remarks (optional, freeform — BR-097)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: ManaSpacing.sm),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: ManaColors.brass),
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('Remarks saved.')));
                                    }
                                  },
                                  child: const ManaText('save'),
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
            ManaText(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const ManaText.raw('—',
                style: TextStyle(color: ManaColors.textSecondary)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: ManaText.raw(e.label)),
                    ManaText.raw(_currency.format(e.amount)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/record_book_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('dd MMM yyyy');

/// OW-009 — Daily Record Book. One row per Business Day (`day_ledger`),
/// including still-Open days. Selecting a row opens an inline "View Day
/// Details" drill-down (Collections/Loans/Expenses/Deposits/Withdrawals/
/// Adjustments/Audit/Timeline), per OW-009_Daily_Record_Book.md.
///
/// NOT the same screen as OW-010 Report Hub — OW-010 shows one row per
/// CLOSED business-day-account with From/To ranges and monthly rollups;
/// this screen shows every raw Business Day, Open or Closed, one date each.
class DailyRecordBookScreen extends ConsumerStatefulWidget {
  final String businessId;
  const DailyRecordBookScreen({super.key, required this.businessId});

  @override
  ConsumerState<DailyRecordBookScreen> createState() => _DailyRecordBookScreenState();
}

class _DailyRecordBookScreenState extends ConsumerState<DailyRecordBookScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recordBookProvider.notifier).load(widget.businessId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordBookProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ManaText('daily record book'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Filter by status',
            onSelected: (status) => ref
                .read(recordBookProvider.notifier)
                .load(widget.businessId, status: status),
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: ManaText('all')),
              PopupMenuItem(value: 'Open', child: ManaText('open')),
              PopupMenuItem(value: 'Closed', child: ManaText('closed')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref
              .read(recordBookProvider.notifier)
              .load(widget.businessId, status: state.statusFilter),
          child: state.loading && state.rows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.rows.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                          child: Center(
                            child: ManaText.raw('No business days recorded yet.',
                                style: TextStyle(color: ManaColors.textSecondary)),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      itemCount: state.rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.sm),
                      itemBuilder: (context, i) => _LedgerRowCard(
                        row: state.rows[i],
                        onTap: () => _openDayDetails(context, state.rows[i]),
                      ),
                    ),
        ),
      ),
    );
  }

  Future<void> _openDayDetails(BuildContext context, DayLedgerRow row) async {
    await ref.read(recordBookProvider.notifier).openDayDetails(widget.businessId, row.businessDate);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DayDetailsSheet(businessId: widget.businessId, row: row),
    );
    ref.read(recordBookProvider.notifier).closeDayDetails();
  }
}

class _LedgerRowCard extends StatelessWidget {
  final DayLedgerRow row;
  final VoidCallback onTap;
  const _LedgerRowCard({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
                    child: ManaText.raw(
                      _dateFmt.format(row.businessDate),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ManaStatusPill(
                    label: row.status,
                    status: row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              Wrap(
                spacing: ManaSpacing.lg,
                runSpacing: ManaSpacing.xs,
                children: [
                  _figure('Opening (BF)', row.openingBalance),
                  _figure('Collections', row.totalCollections),
                  _figure('Loan Dist.', row.totalLoanDistribution),
                  _figure('Investor Dep.', row.investorDeposits),
                  _figure('Investor W/D', row.investorWithdrawals),
                  _figure('Expenses', row.totalExpenses),
                  _figure('Short', row.shortAmount, warn: row.shortAmount > 0),
                  _figure('Excess', row.excessAmount, warn: row.excessAmount > 0),
                  _figure('Difference', row.difference),
                  _figure('Closing', row.closingBalance),
                ],
              ),
              if (row.remarks != null && row.remarks!.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(row.remarks!,
                    style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure(String label, double amount, {bool warn = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText(label, style: const TextStyle(fontSize: 10, color: ManaColors.textSecondary)),
        ManaText.raw(
          _currency.format(amount),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: warn ? ManaColors.statusWarn : ManaColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// VIEW DAY DETAILS — Collections/Loans/Expenses/Deposits/Withdrawals/
/// Adjustments/Audit/Timeline, all filtered to one Business Date.
class _DayDetailsSheet extends ConsumerStatefulWidget {
  final String businessId;
  final DayLedgerRow row;
  const _DayDetailsSheet({required this.businessId, required this.row});

  @override
  ConsumerState<_DayDetailsSheet> createState() => _DayDetailsSheetState();
}

class _DayDetailsSheetState extends ConsumerState<_DayDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordBookProvider);
    final detail = state.dayDetail;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.only(top: ManaSpacing.md),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: ManaText.raw(
                        _dateFmt.format(widget.row.businessDate),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    ManaStatusPill(
                      label: widget.row.status,
                      status: widget.row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                    ),
                  ],
                ),
              ),
              if (widget.row.isClosed)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: ManaSpacing.lg, vertical: ManaSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ManaText.raw(
                      'Read-only — this day is closed. Corrections still go through '
                      'each entry type\'s own screen as a new offsetting entry.',
                      style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
                    ),
                  ),
                ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Collections'),
                  Tab(text: 'Loans'),
                  Tab(text: 'Expenses'),
                  Tab(text: 'Deposits'),
                  Tab(text: 'Withdrawals'),
                  Tab(text: 'Adjustments'),
                  Tab(text: 'Audit'),
                  Tab(text: 'Timeline'),
                ],
              ),
              Expanded(
                child: state.detailLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.detailError != null
                        ? Center(
                            child: ManaText.raw(state.detailError!,
                                style: const TextStyle(color: ManaColors.statusBad)),
                          )
                        : detail == null
                            ? const SizedBox.shrink()
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _EntryList(
                                    entries: detail.collections,
                                    emptyLabel: 'No collections this day.',
                                    onOpenSource: (loanId) => _goTo(context, '/ow-006', loanId),
                                  ),
                                  _EntryList(
                                    entries: detail.loans,
                                    emptyLabel: 'No loans distributed this day.',
                                    onOpenSource: (loanId) => _goTo(context, '/ow-007', loanId),
                                  ),
                                  _EntryList(entries: detail.expenses, emptyLabel: 'No expenses this day.'),
                                  _EntryList(entries: detail.deposits, emptyLabel: 'No investor deposits this day.'),
                                  _EntryList(
                                      entries: detail.withdrawals,
                                      emptyLabel: 'No investor withdrawals this day.'),
                                  _EntryList(
                                    entries: detail.adjustments,
                                    emptyLabel: 'No corrections/adjustments this day.',
                                  ),
                                  _AuditList(entries: detail.auditLog),
                                  _EntryList(
                                    entries: detail.timeline,
                                    emptyLabel: 'Nothing recorded this day yet.',
                                  ),
                                ],
                              ),
              ),
              Padding(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _remarksController..text = widget.row.remarks ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Remarks (optional, freeform — BR-097)',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 500,
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: ManaColors.brass),
                      onPressed: () async {
                        final ok = await NetworkErrorHandler.run(context, () async {
                          return ref.read(recordBookProvider.notifier).updateRemarks(
                                widget.businessId,
                                widget.row.businessDate,
                                _remarksController.text,
                              );
                        });
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Remarks saved.')));
                        }
                      },
                      child: const ManaText('save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _goTo(BuildContext context, String route, String? extra) {
    Navigator.of(context).pop();
    context.push(route, extra: extra);
  }
}

class _EntryList extends StatelessWidget {
  final List<DayDetailEntry> entries;
  final String emptyLabel;
  final void Function(String loanId)? onOpenSource;
  const _EntryList({required this.entries, required this.emptyLabel, this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: ManaText.raw(emptyLabel, style: const TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: ManaSpacing.lg),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: ManaText.raw(e.label),
          subtitle: ManaText.raw(DateFormat('dd MMM, hh:mm a').format(e.timestamp),
              style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(_currency.format(e.amount),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (e.isCorrection) ...[
                const SizedBox(width: ManaSpacing.xs),
                const ManaStatusPill(label: 'Correction', status: ManaStatus.warn),
              ],
              if (onOpenSource != null && e.sourceLoanId != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => onOpenSource!(e.sourceLoanId!),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// `audit_log` is administrative/security events ONLY (BR-124/158) — a
/// Day Reopen, a Loan/Collection Correction record, a permission change,
/// etc. Routine collections/loans/expenses do NOT appear here (they're
/// already the "Collections"/"Loans"/etc. tabs above).
class _AuditList extends StatelessWidget {
  final List<AuditLogEntry> entries;
  const _AuditList({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: ManaText.raw('No administrative/security events this day.',
            style: TextStyle(color: ManaColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: ManaSpacing.lg),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: ManaText(e.actionType),
          subtitle: ManaText.raw('${e.entityType} · ${e.entityId}',
              style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
          trailing: ManaText.raw(DateFormat('dd MMM, hh:mm a').format(e.entryTimestamp),
              style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/record_book_state.dart';

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
      appBar: ManaAppBar(
        homeRoute: '/ow-001',
        title: ref.t('daily_record_book'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: ref.t('filter_by_status'),
            onSelected: (status) => ref
                .read(recordBookProvider.notifier)
                .load(widget.businessId, status: status),
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: ManaText.raw(ref.t('all'))),
              PopupMenuItem(value: 'Open', child: ManaText.raw(ref.t('open'))),
              PopupMenuItem(value: 'Closed', child: ManaText.raw(ref.t('closed'))),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: ref.t('recent_deletes'),
            icon: const Icon(Icons.restore_from_trash),
            onPressed: () => context.push('/recent-deletes?businessId=${widget.businessId}'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref
              .read(recordBookProvider.notifier)
              .load(widget.businessId, status: state.statusFilter),
          child: state.loading && state.rows.isEmpty
              // Ledger rows carry ~10 figures each, so the placeholders are
              // tall to match — a short skeleton would jump when data lands.
              ? const ManaSkeletonList(itemHeight: 220)
              : state.rows.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                          child: Center(
                            child: ManaText.raw(ref.t('no_business_days_yet'),
                                style: ManaType.secondary),
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

class _LedgerRowCard extends ConsumerWidget {
  final DayLedgerRow row;
  final VoidCallback onTap;
  const _LedgerRowCard({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    child: ManaText.raw(
                      _dateFmt.format(row.businessDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.heavy,
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaStatusPill(
                      label: row.status,
                      status: row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              Wrap(
                spacing: ManaSpacing.lg,
                runSpacing: ManaSpacing.xs,
                children: [
                  _figure(ref, ref.t('opening_bf'), row.openingBalance),
                  _figure(ref, ref.t('collections'), row.totalCollections),
                  // Sits beside Collections, not inside it — these rupees
                  // arrived as part of ordinary collections and are already
                  // counted there and in Closing. This line classifies them
                  // as penalty income; it is not a separate inflow.
                  _figure(ref, ref.t('penalty_collected'), row.penaltyCollected),
                  _figure(ref, ref.t('loan_dist'), row.totalLoanDistribution),
                  _figure(ref, ref.t('investor_dep'), row.investorDeposits),
                  _figure(ref, ref.t('investor_wd'), row.investorWithdrawals),
                  _figure(ref, ref.t('expenses'), row.totalExpenses),
                  // Cash moved into and out of chetis. Kept separate from
                  // Expenses on purpose: a cheti instalment is recoverable
                  // (it comes back as the availed lumpsum), so it is an asset
                  // movement, not a cost. Folding it into Expenses would sink
                  // line profit every period and then show one phantom gain.
                  _figure(ref, ref.t('cheti_paid'), row.chetiPaid),
                  _figure(ref, ref.t('cheti_received'), row.chetiReceived),
                  _figure(ref, ref.t('short'), row.shortAmount, warn: row.shortAmount > 0),
                  _figure(ref, ref.t('excess'), row.excessAmount, warn: row.excessAmount > 0),
                  _figure(ref, ref.t('difference'), row.difference),
                  _figure(ref, ref.t('closing'), row.closingBalance),
                ],
              ),
              if (row.remarks != null && row.remarks!.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(row.remarks!,
                    style: ManaType.note),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure(WidgetRef ref, String label, int amount, {bool warn = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(label, style: ManaType.note),
        ManaText.raw(
          manaRupees(amount),
          style: TextStyle(
            fontSize: 16,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ManaText.raw(
                        _dateFmt.format(widget.row.businessDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.xs),
                    Flexible(
                      child: ManaStatusPill(
                        label: widget.row.status,
                        status: widget.row.isClosed ? ManaStatus.neutral : ManaStatus.good,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.row.isClosed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg, vertical: ManaSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ManaText.raw(
                      ref.t('read_only_day_closed_note'),
                      style: ManaType.note,
                    ),
                  ),
                ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: [
                  Tab(text: ref.t('collections')),
                  Tab(text: ref.t('loans')),
                  Tab(text: ref.t('expenses')),
                  Tab(text: ref.t('deposits')),
                  Tab(text: ref.t('withdrawals')),
                  Tab(text: ref.t('adjustments')),
                  Tab(text: ref.t('audit')),
                  Tab(text: ref.t('timeline')),
                ],
              ),
              Expanded(
                child: state.detailLoading
                    ? const ManaSkeletonList(itemCount: 5, itemHeight: 64)
                    : state.detailError != null
                        ? Center(
                            child: ManaText.raw(state.detailError!,
                                style: ManaType.bad),
                          )
                        : detail == null
                            ? const SizedBox.shrink()
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _EntryList(
                                    entries: detail.collections,
                                    emptyLabel: ref.t('no_collections_this_day'),
                                    onOpenSource: (loanId) => _goTo(
                                        context, '/ow-006?loan=$loanId', null),
                                    deletableAs: DeletableEntity.collection,
                                    businessId: widget.businessId,
                                  ),
                                  _EntryList(
                                    entries: detail.loans,
                                    emptyLabel: ref.t('no_loans_distributed_this_day'),
                                    onOpenSource: (loanId) => _goTo(context, '/ow-007', loanId),
                                    deletableAs: DeletableEntity.loan,
                                    businessId: widget.businessId,
                                  ),
                                  _EntryList(
                                      entries: detail.expenses,
                                      emptyLabel: ref.t('no_expenses_this_day'),
                                      deletableAs: DeletableEntity.expense,
                                      businessId: widget.businessId),
                                  _EntryList(
                                      entries: detail.deposits,
                                      emptyLabel: ref.t('no_investor_deposits_this_day'),
                                      deletableAs: DeletableEntity.investment,
                                      businessId: widget.businessId),
                                  _EntryList(
                                      entries: detail.withdrawals,
                                      emptyLabel: ref.t('no_investor_withdrawals_this_day'),
                                      deletableAs: DeletableEntity.investmentWithdrawal,
                                      businessId: widget.businessId),
                                  _EntryList(
                                    entries: detail.adjustments,
                                    emptyLabel: ref.t('no_corrections_adjustments_this_day'),
                                    deletableAs: DeletableEntity.settlementAdjustment,
                                    businessId: widget.businessId,
                                  ),
                                  _AuditList(entries: detail.auditLog),
                                  _EntryList(
                                    entries: detail.timeline,
                                    emptyLabel: ref.t('nothing_recorded_this_day_yet'),
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
                        decoration: InputDecoration(
                          labelText: ref.t('remarks_optional_freeform_note'),
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 500,
                      ),
                    ),
                    const SizedBox(width: ManaSpacing.sm),
                    Flexible(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: ManaColors.accent),
                        onPressed: () async {
                          final ok = await NetworkErrorHandler.run(context, () async {
                            return ref.read(recordBookProvider.notifier).updateRemarks(
                                  widget.businessId,
                                  widget.row.businessDate,
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
              ),
            ],
          ),
        );
      },
    );
  }

  /// Closes the day-detail sheet, then opens the record it came from.
  ///
  /// `extra` is the businessId where a route wants one. A route that needs to
  /// know WHICH record takes it in the path -- /ow-006 read a loan id off
  /// `extra` until the footer nav started sending a business id through the
  /// same channel.
  void _goTo(BuildContext context, String route, String? extra) {
    Navigator.of(context).pop();
    context.push(route, extra: extra ?? widget.businessId);
  }
}

class _EntryList extends ConsumerWidget {
  final List<DayDetailEntry> entries;
  final String emptyLabel;
  final void Function(String loanId)? onOpenSource;

  /// What kind of record these rows are. Null makes the tab read-only —
  /// used for tabs whose rows are not individually deletable.
  final DeletableEntity? deletableAs;

  /// Needed to refresh the day after a delete changes its figures.
  final String? businessId;

  const _EntryList({
    required this.entries,
    required this.emptyLabel,
    this.onOpenSource,
    this.deletableAs,
    this.businessId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Center(
        child: ManaText.raw(emptyLabel, style: ManaType.secondary),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: ManaSpacing.lg),
      itemBuilder: (context, i) {
        final e = entries[i];
        // The amount and the Correction pill moved OUT of `trailing` and
        // onto the subtitle line. ListTile's trailing slot must size to its
        // content, and amount + pill + open + delete together consumed the
        // whole tile width — which ListTile rejects outright rather than
        // merely overflowing. Actions stay in trailing; facts read below the
        // title, in a Wrap so they can drop to a second line when scaled.
        return ListTile(
          contentPadding: EdgeInsets.zero,
          isThreeLine: e.isCorrection,
          title: ManaText.raw(e.label),
          subtitle: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ManaSpacing.sm,
            runSpacing: ManaSpacing.xs,
            children: [
              ManaText.raw(DateFormat('dd MMM, hh:mm a').format(e.timestamp),
                  style: TextStyle(
                      fontSize: 13, color: ManaColors.textSecondary)),
              ManaText.raw(manaRupees(e.amount),
                  style: ManaType.emphasis),
              if (e.isCorrection)
                ManaStatusPill(label: ref.t('correction'), status: ManaStatus.warn),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onOpenSource != null && e.sourceLoanId != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => onOpenSource!(e.sourceLoanId!),
                ),
              if (deletableAs != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: ManaColors.statusBad,
                  tooltip: ref.t('delete'),
                  onPressed: () => _delete(context, ref, e),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, DayDetailEntry e) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: deletableAs!,
      recordId: e.id,
      description: '${e.label} — ${manaRupees(e.amount)}',
    );
    if (!deleted || !context.mounted || businessId == null) return;
    // The day's figures moved, and so did every day after it. Reload rather
    // than removing the row from the list and leaving the totals stale.
    await ref.read(recordBookProvider.notifier).load(businessId!);
  }
}

/// `audit_log` is administrative/security events ONLY (BR-124/158) — a
/// Day Reopen, a Loan/Collection Correction record, a permission change,
/// etc. Routine collections/loans/expenses do NOT appear here (they're
/// already the "Collections"/"Loans"/etc. tabs above).
class _AuditList extends ConsumerWidget {
  final List<AuditLogEntry> entries;
  const _AuditList({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Center(
        child: ManaText.raw(ref.t('no_admin_security_events_this_day'),
            style: ManaType.secondary),
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
              style: ManaType.note),
          trailing: ManaText.raw(DateFormat('dd MMM, hh:mm a').format(e.entryTimestamp),
              style: ManaType.note),
        );
      },
    );
  }
}

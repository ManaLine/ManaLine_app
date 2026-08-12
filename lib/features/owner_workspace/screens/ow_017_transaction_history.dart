import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design/components/mana_ledger.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/ledger_history_service.dart';
import '../../../shared/ledger_history_state.dart';
import '../../../shared/ledger_labels.dart';
import '../../../shared/ledger_filter_sheet.dart';
import '../../../shared/translation_service.dart';

/// OW-017 — Transaction History, Owner view.
///
/// Rebuilt on `app.ledger_history`. What this replaces was assembled from
/// three client-side queries — collections, loans, settlement adjustments —
/// and called the business's history. `day_ledger` names eight money
/// categories; expenses, investor deposits, investor withdrawals and both
/// cheti directions were missing, so the screen was quietly incomplete. It
/// also fetched the entire history with no limit and summed whichever rows it
/// held into a figure labelled "Net Change", which was not the month, not the
/// balance, and not anything the business could check.
///
/// Now: every category, keyset-paginated, grouped by BUSINESS DAY, with the
/// month figure read from day_ledger — the same derived ledger Day Closure
/// reconciles against.
class TransactionHistoryScreen extends ConsumerStatefulWidget {
  final String businessId;
  const TransactionHistoryScreen({super.key, required this.businessId});

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ledgerHistoryProvider(widget.businessId).notifier).load();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) {
      ref.read(ledgerHistoryProvider(widget.businessId).notifier).loadMore();
    }
  }

  LedgerHistoryNotifier get _notifier =>
      ref.read(ledgerHistoryProvider(widget.businessId).notifier);

  Future<void> _openFilters() async {
    final current = ref.read(ledgerHistoryProvider(widget.businessId)).filter;
    final next = await showLedgerFilterSheet(context, ref, current);
    if (next != null) await _notifier.applyFilter(next);
  }

  Future<void> _openMonthSheet(LedgerMonthSummary summary) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                _monthLabel(summary.monthStart),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ManaSpacing.md),
              ManaLedgerMonthBreakdown(
                summary: summary,
                receivedLabel: ref.t('money_received'),
                spentLabel: ref.t('money_spent'),
                openingLabel: ref.t('opening_balance'),
                closingLabel: ref.t('closing_balance_label'),
              ),
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(
                ref.t('month_totals_from_ledger_note'),
                style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthLabel(String isoDate) =>
      DateFormat('MMMM yyyy').format(DateTime.parse(isoDate));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerHistoryProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('history')),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/ow-001', extra: widget.businessId),
        ),
        actions: [
          // Icon-only, not a labelled button. A TextButton.icon carrying a
          // translated "My Statements" overflows the AppBar by ~35px at 2.0x
          // text scale on a 360dp screen — the label is longer in every
          // language other than English. The tooltip keeps it nameable.
          IconButton(
            onPressed: () => context.push('/ow-017-statement', extra: widget.businessId),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: ref.t('my_statements'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SearchBar(
              controller: _search,
              hint: ref.t('search_transactions'),
              activeCount: state.filter.activeCount,
              onSubmitted: (v) =>
                  _notifier.applyFilter(state.filter.copyWith(search: v)),
              onFilterTap: _openFilters,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _notifier.load(),
                child: _body(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(LedgerHistoryState state) {
    if (state.loading && state.events.isEmpty) {
      return const ManaSkeletonList(itemCount: 6);
    }
    if (state.error != null && state.events.isEmpty) {
      return _Message(
        text: ref.t('could_not_load_history'),
        tone: ManaColors.statusBad,
        actionLabel: ref.t('retry'),
        onAction: () => _notifier.load(),
      );
    }
    if (state.isEmpty) {
      return _Message(
        text: state.filter.isActive
            ? ref.t('no_transactions_match_filters')
            : ref.t('no_transactions_yet'),
        tone: ManaColors.textSecondary,
        actionLabel: state.filter.isActive ? ref.t('clear_all') : null,
        onAction: state.filter.isActive
            ? () => _notifier.applyFilter(const LedgerFilter())
            : null,
      );
    }

    // Flattened so one lazy ListView covers headers and rows — a Column of
    // per-day ListViews would build every row up front, which is what the
    // unbounded fetch this replaces already cost us once.
    final slivers = <Widget>[];
    if (state.summary != null) {
      slivers.add(ManaLedgerMonthBand(
        monthLabel: _monthLabel(state.summary!.monthStart),
        summary: state.summary,
        onTap: () => _openMonthSheet(state.summary!),
      ));
      slivers.add(Divider(height: 1, color: ManaColors.divider));
    }
    for (final day in state.days) {
      slivers.add(ManaLedgerDayHeader(
        dateLabel: ledgerDayLabel(day.businessDate),
        trailingLabel: ref.t('day_net'),
        trailingAmount: day.netOfLoadedEvents,
      ));
      for (final e in day.events) {
        slivers.add(ManaLedgerRow(
          event: e,
          actionLabel: ledgerActionLabel(ref, e),
          timeLabel: ledgerTimeLabel(e),
          onTap: () => _showDetail(e),
        ));
      }
    }
    if (state.loadingMore) {
      slivers.add(const Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }

    return ListView.builder(
      controller: _scroll,
      itemCount: slivers.length,
      itemBuilder: (_, i) => slivers[i],
    );
  }

  void _showDetail(LedgerEvent e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(
                ledgerActionLabel(ref, e),
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              if (e.counterparty != null)
                ManaText.raw(
                  e.counterparty!,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: ManaSpacing.md),
              _detailLine(ref.t('amount'), null, e),
              _detailLine(ref.t('date'), ledgerDayLabel(e.businessDate), null),
              _detailLine(ref.t('time'), ledgerTimeLabel(e), null),
              if (e.reference != null) _detailLine(ref.t('reference'), e.reference, null),
              if (e.method != null) _detailLine(ref.t('details'), e.method, null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String? value, LedgerEvent? amountOf) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: ManaText.raw(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          ),
          const SizedBox(width: ManaSpacing.sm),
          if (amountOf != null)
            ManaLedgerAmount(event: amountOf)
          else
            Flexible(
              child: ManaText.raw(value ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int activeCount;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onFilterTap;

  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.activeCount,
    required this.onSubmitted,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, ManaSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: hint,
                filled: true,
                fillColor: ManaColors.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: ManaSpacing.sm),
          // Badged rather than a bare icon: an active filter that looks
          // identical to no filter is how people conclude money is missing.
          Badge(
            isLabelVisible: activeCount > 0,
            label: Text('$activeCount'),
            child: IconButton(
              onPressed: onFilterTap,
              icon: const Icon(Icons.tune),
              tooltip: 'Filters',
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Color tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.text,
    required this.tone,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on an empty or failed list.
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(ManaSpacing.xxl),
          child: Column(
            children: [
              ManaText.raw(text, textAlign: TextAlign.center, style: TextStyle(color: tone)),
              if (actionLabel != null) ...[
                const SizedBox(height: ManaSpacing.md),
                TextButton(onPressed: onAction, child: ManaText(actionLabel!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

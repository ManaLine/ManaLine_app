import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// AG-010 — Transaction History, Agent view. The Agent footer's 4th tab.
///
/// Same feed and same components as OW-017, because it calls the same
/// `app.ledger_history`. That function is SECURITY INVOKER, so RLS decides
/// what comes back: for an agent that is collections and loans for customers
/// on their own route, expenses they recorded, adjustments where they are the
/// agent, and investments only with can_view_investor_info. No permission
/// logic is duplicated here — widening what an agent may see is a policy
/// change in the database, not an edit to this file.
///
/// WHAT THIS SCREEN MUST NOT DO. The feed is a PARTIAL slice, so any total
/// over it is this agent's own activity and not the business's position:
///
///   * no month band — day_ledger is business-wide and the agent's feed is
///     not, so the two would contradict each other on the same screen;
///   * no day net — netting an incomplete set produces a confident wrong
///     number, the exact failure the Day Closure opening balance had;
///   * no closing balance, ever.
///
/// The day header therefore reports what this agent collected, labelled as
/// theirs. That is a true statement about a partial view; a net is not.
class Ag010TransactionHistoryScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String agentMembershipId;

  const Ag010TransactionHistoryScreen({
    super.key,
    required this.businessId,
    required this.agentMembershipId,
  });

  @override
  ConsumerState<Ag010TransactionHistoryScreen> createState() =>
      _Ag010TransactionHistoryScreenState();
}

class _Ag010TransactionHistoryScreenState
    extends ConsumerState<Ag010TransactionHistoryScreen> {
  final _scroll = ScrollController();

  /// What an agent's feed can contain. Cheti and investor withdrawals have no
  /// agent SELECT policy at all, so offering them as filters would present an
  /// absent permission as missing money.
  static const _agentVisibleTypes = <LedgerEventType>{
    LedgerEventType.collection,
    LedgerEventType.loanDistribution,
    LedgerEventType.expense,
    LedgerEventType.investorDeposit,
    LedgerEventType.adjustmentShort,
    LedgerEventType.adjustmentExcess,
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // withSummary: false — see the class note. The month summary is
      // business-wide and this feed is not.
      ref.read(ledgerHistoryProvider(widget.businessId).notifier)
          .load(withSummary: false);
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels < 400) {
      ref.read(ledgerHistoryProvider(widget.businessId).notifier).loadMore();
    }
  }

  LedgerHistoryNotifier get _notifier =>
      ref.read(ledgerHistoryProvider(widget.businessId).notifier);

  Future<void> _openFilters() async {
    final current = ref.read(ledgerHistoryProvider(widget.businessId)).filter;
    final next = await showLedgerFilterSheet(
      context,
      ref,
      current,
      availableTypes: _agentVisibleTypes,
    );
    if (next != null) await _notifier.applyFilter(next, withSummary: false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerHistoryProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('transaction_history')),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: state.filter.activeCount > 0,
              label: Text('${state.filter.activeCount}'),
              child: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _notifier.load(withSummary: false),
          child: _body(state),
        ),
      ),
    );
  }

  Widget _body(LedgerHistoryState state) {
    if (state.loading && state.events.isEmpty) {
      return const ManaSkeletonList(itemCount: 6);
    }
    if (state.error != null && state.events.isEmpty) {
      return _agentMessage(ref.t('could_not_load_history'), ManaColors.statusBad);
    }
    if (state.isEmpty) {
      return _agentMessage(
        state.filter.isActive
            ? ref.t('no_transactions_match_filters')
            : ref.t('no_transactions_recorded_yet'),
        ManaColors.textSecondary,
      );
    }

    final rows = <Widget>[
      // Says plainly that this is the agent's own slice. Without it, a
      // shorter list than the owner's reads as data loss rather than scope.
      Container(
        width: double.infinity,
        color: ManaColors.brandFaint,
        padding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
        child: ManaText.raw(
          ref.t('your_activity_only_note'),
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
        ),
      ),
    ];

    for (final day in state.days) {
      rows.add(ManaLedgerDayHeader(
        dateLabel: ledgerDayLabel(day.businessDate),
        trailingLabel: ref.t('you_collected'),
        trailingAmount: day.moneyIn,
        // Not a net: money in only, so no sign and no positive tone. A `+`
        // here would imply the day netted this much, which this view cannot
        // know.
        trailingIsNet: false,
      ));
      for (final e in day.events) {
        rows.add(ManaLedgerRow(
          event: e,
          actionLabel: ledgerActionLabel(ref, e),
          timeLabel: ledgerTimeLabel(e),
        ));
      }
    }
    if (state.loadingMore) {
      rows.add(const Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }

    return ListView.builder(
      controller: _scroll,
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _agentMessage(String text, Color tone) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(ManaSpacing.xxl),
            child: ManaText.raw(text,
                textAlign: TextAlign.center, style: TextStyle(color: tone)),
          ),
        ],
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_ledger.dart';
import '../design/components/mana_skeleton.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/tokens/spacing.dart';
import 'ledger_history_service.dart';
import 'ledger_history_state.dart';
import 'ledger_labels.dart';
import 'ledger_filter_sheet.dart';
import 'translation_service.dart';

/// Transaction history, for whichever ledger the person is entitled to see.
///
/// OW-017 and AG-010 rendered the same feed, the same rows and the same
/// notifier through two screens that differed in 327 lines -- almost all of it
/// duplication. The real difference is three things, and they are all here:
///
///   * WHOSE balances. A null [membershipId] is the business ledger; a set one
///     is that Agent's own float. It is passed to the notifier, which asks
///     day_balances for one or the other.
///   * The MONTH BAND. Read from day_ledger, which is the business's position.
///     An Agent has no business position, so they do not get one.
///   * One LABEL. An unclosed day is "day net" to an Owner and "you collected"
///     to an Agent, because their feeds mean different things.
///
/// Everything else -- keyset pagination, the filter sheet, day grouping, the
/// brought-forward and carried-forward lines -- is identical and was being
/// maintained twice.
class ManaLedgerHistoryView extends ConsumerStatefulWidget {
  final String businessId;

  /// The Agent's own membership, or null for the business ledger.
  ///
  /// This is NOT cosmetic: it decides which float the opening and closing
  /// lines describe. An Agent shown the business's closing balance would read
  /// it as cash they are holding.
  final String? membershipId;

  /// Where back goes when there is nothing to pop.
  final String homeRoute;

  /// Owner-only. Null draws no action.
  final String? statementRoute;

  /// Passed in for the same reason homeRoute is: History is the fourth tab in
  /// both workspaces, and the four destinations behind it differ by role.
  final Widget? bottomNavigationBar;

  const ManaLedgerHistoryView({
    super.key,
    required this.businessId,
    required this.homeRoute,
    this.membershipId,
    this.statementRoute,
    this.bottomNavigationBar,
  });

  @override
  ConsumerState<ManaLedgerHistoryView> createState() => _ManaLedgerHistoryViewState();
}

class _ManaLedgerHistoryViewState extends ConsumerState<ManaLedgerHistoryView> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// withSummary only for the business ledger -- see the class note. Whose
  /// feed it is now comes from the provider's own key, not an argument.
  Future<void> _load() => _notifier.load(withSummary: _scope.membershipId == null);

  LedgerScope get _scope =>
      (businessId: widget.businessId, membershipId: widget.membershipId);

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
      ref.read(ledgerHistoryProvider(_scope).notifier).loadMore();
    }
  }

  LedgerHistoryNotifier get _notifier =>
      ref.read(ledgerHistoryProvider(_scope).notifier);

  Future<void> _openFilters() async {
    final current = ref.read(ledgerHistoryProvider(_scope)).filter;
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
                style: ManaType.fine,
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
    final state = ref.watch(ledgerHistoryProvider(_scope));

    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: ManaAppBar(
        title: ref.t('history'),
        homeRoute: widget.homeRoute,
        homeExtra: widget.businessId,
        actions: [
          if (widget.statementRoute != null)
            // Icon-only, not a labelled button. A TextButton.icon carrying a
            // translated "My Statements" overflows the AppBar by ~35px at 2.0x
            // text scale on a 360dp screen -- the label is longer in every
            // language other than English. The tooltip keeps it nameable.
            IconButton(
              onPressed: () =>
                  context.push(widget.statementRoute!, extra: widget.businessId),
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
                onRefresh: () => _load(),
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
        onAction: _load,
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
    if (widget.membershipId != null) {
      // Says plainly that this is the Agent's own slice. Without it, a shorter
      // list than the Owner's reads as data loss rather than scope -- and this
      // is the one line that stops an Agent treating their float as the
      // business's position. Dropped in the first pass of this consolidation;
      // the test that asserts it is why it is back.
      slivers.add(Container(
        width: double.infinity,
        color: ManaColors.brandFaint,
        padding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
        child: ManaText.raw(ref.t('your_activity_only_note'), style: ManaType.fine),
      ));
    }
    if (state.summary != null && widget.membershipId == null) {
      slivers.add(ManaLedgerMonthBand(
        monthLabel: _monthLabel(state.summary!.monthStart),
        summary: state.summary,
        onTap: () => _openMonthSheet(state.summary!),
      ));
      slivers.add(Divider(height: 1, color: ManaColors.divider));
    }
    for (final day in state.days) {
      // The closing balance, not the day's swing. A day that lends more than
      // it collects swings negative while the cash box stays positive, and
      // showing the swing made every lending day read as a loss.
      // An unclosed day means different things to the two roles, and the
      // difference is not cosmetic.
      //
      // For the Owner it is the day's NET -- what the business is up or down,
      // sign and all. For an Agent it must never be a net: their feed is an
      // RLS-filtered subset and never a position, so a negative figure would
      // be arithmetic over rows they cannot all see. They get money IN only,
      // unsigned, labelled as their own.
      final agent = widget.membershipId != null;
      slivers.add(ManaLedgerDayHeader(
        dateLabel: ledgerDayLabel(day.businessDate),
        trailingLabel: day.closingBf != null
            ? ref.t('day_closing')
            : ref.t(agent ? 'you_collected' : 'day_net'),
        trailingAmount: day.closingBf ??
            (agent ? day.moneyIn : day.netOfLoadedEvents),
        trailingIsNet: day.closingBf == null && !agent,
      ));
      // The day's first line is the cash carried into it.
      if (day.openingBf != null) {
        slivers.add(ManaLedgerOpeningRow(
          amount: day.openingBf!,
          label: ref.t('brought_forward'),
        ));
      }
      for (final e in day.events) {
        // A BF grant read from the Agent's own ledger.
        //
        // The event is the business's: money moving from the Owner's pocket
        // to an Agent's, a transfer that changes no total, which is what the
        // Owner's ledger correctly shows in grey as "BF Given To <agent>".
        // Read from inside the Agent's own book it is the opposite -- cash
        // arriving -- and it was drawn grey, with a sideways arrow, naming the
        // Agent to themselves. Same row, wrong reader.
        final bfToMe =
            widget.membershipId != null && e.type == LedgerEventType.bfGrant;
        slivers.add(ManaLedgerRow(
          event: e,
          actionLabel: bfToMe ? ref.t('bf_received') : ledgerActionLabel(ref, e),
          directionFor: bfToMe ? LedgerDirection.moneyIn : null,
          // The counterparty on this row IS this agent. Naming the reader to
          // themselves says nothing; the label already says what happened.
          showCounterparty: !bfToMe,
          timeLabel: ledgerHasKnownTime(e) ? ledgerTimeLabel(e) : '',
          onTap: () => _showDetail(e),
        ));
      }
      // …and what was left at the end of it. A day now reads as a small
      // account: carried in, what moved, carried out — and the closing of one
      // day is the opening of the next, which is the thing an Owner checks.
      if (day.closingBf != null) {
        slivers.add(ManaLedgerOpeningRow(
          amount: day.closingBf!,
          label: ref.t('carried_forward'),
          isClosing: true,
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
    // Same reader, same perspective as the row that was tapped -- see the
    // list above. A detail sheet that contradicts the row it opened from is
    // worse than either version alone.
    final bfToMe =
        widget.membershipId != null && e.type == LedgerEventType.bfGrant;
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
                bfToMe ? ref.t('bf_received') : ledgerActionLabel(ref, e),
                style: ManaType.note,
              ),
              if (!bfToMe && e.counterparty != null)
                ManaText.raw(
                  e.counterparty!,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: ManaSpacing.md),
              _detailLine(ref.t('amount'), null, e,
                  directionFor: bfToMe ? LedgerDirection.moneyIn : null),
              _detailLine(ref.t('date'), ledgerDayLabel(e.businessDate), null),
              // Only when the ledger actually knows one — see
              // ledgerHasKnownTime.
              if (ledgerHasKnownTime(e))
                _detailLine(ref.t('time'), ledgerTimeLabel(e), null),
              if (e.reference != null) _detailLine(ref.t('reference'), e.reference, null),
              // "Payment: More Than The Instalment", not "Details: Excess".
              // The raw result_type read as a warning when it only means the
              // customer paid more than one instalment at once.
              if (e.method != null)
              _detailLine(ref.t('payment'), ledgerOutcomeLabel(ref, e), null),
              // Where it was taken and who handed it over. Fetched when the
              // sheet opens rather than carried by the feed, and shown only
              // when there is something to say -- an absent location is the
              // normal case for anything recorded before locations were,
              // and "Location: —" on every old row is noise.
              if (e.type == LedgerEventType.collection)
                FutureBuilder<ManaCollectionExtras?>(
                  future: ref
                      .read(ledgerHistoryServiceProvider)
                      .collectionExtras(e.id.split(':').last),
                  builder: (context, snap) {
                    final x = snap.data;
                    if (x == null) return const SizedBox.shrink();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (x.locationName != null && x.locationName!.isNotEmpty)
                          _detailLine(ref.t('location'), x.locationName, null),
                        // Only when it was NOT the customer: saying "Paid By:
                        // Customer" on every ordinary collection tells nobody
                        // anything.
                        if (x.someoneElsePaid)
                          _detailLine(
                              ref.t('paid_by'),
                              [x.payerName, x.payerType]
                                  .where((v) => v != null && v.isNotEmpty)
                                  .join(' - '),
                              null),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String? value, LedgerEvent? amountOf,
      {LedgerDirection? directionFor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: ManaText.raw(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ManaType.note),
          ),
          const SizedBox(width: ManaSpacing.sm),
          if (amountOf != null)
            ManaLedgerAmount(event: amountOf, directionFor: directionFor)
          else
            Flexible(
              child: ManaText.raw(value ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: ManaType.small),
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

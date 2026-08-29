/// Paging state for the ledger feed, shared by OW-017 and AG-010.
///
/// One notifier for both because the paging, filtering and refresh behaviour
/// is identical — only what the server returns differs, and that is decided by
/// the membership passed to `app.ledger_history`.
///
/// It used to say RLS decided it, citing a SECURITY INVOKER note. The function
/// is SECURITY DEFINER and took no membership at all, so nothing was deciding
/// anything: every feed was the whole business. Both halves are fixed in
/// migration 20260829102054.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ledger_history_service.dart';

class LedgerHistoryState {
  final List<LedgerEvent> events;
  final LedgerMonthSummary? summary;
  final LedgerFilter filter;
  final bool loading;

  /// A page request is in flight below the fold. Separate from [loading] so
  /// the list is not replaced by a spinner while appending.
  final bool loadingMore;

  /// The last page came back short, so there is nothing further back.
  final bool reachedEnd;
  final String? error;

  /// What each loaded day opened and closed on, keyed by business date.
  /// Fetched, not summed — see [LedgerDay.openingBf].
  final Map<String, LedgerDayBalance> balances;

  const LedgerHistoryState({
    this.events = const [],
    this.balances = const {},
    this.summary,
    this.filter = const LedgerFilter(),
    this.loading = true,
    this.loadingMore = false,
    this.reachedEnd = false,
    this.error,
  });

  List<LedgerDay> get days => groupByBusinessDate(events, balances: balances);

  bool get isEmpty => !loading && error == null && events.isEmpty;

  LedgerHistoryState copyWith({
    List<LedgerEvent>? events,
    Map<String, LedgerDayBalance>? balances,
    LedgerMonthSummary? summary,
    LedgerFilter? filter,
    bool? loading,
    bool? loadingMore,
    bool? reachedEnd,
    String? error,
    bool clearError = false,
  }) =>
      LedgerHistoryState(
        events: events ?? this.events,
        balances: balances ?? this.balances,
        summary: summary ?? this.summary,
        filter: filter ?? this.filter,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        reachedEnd: reachedEnd ?? this.reachedEnd,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Which ledger this is: a business, and optionally the one membership inside
/// it whose work the feed is limited to.
///
/// BOTH halves are the key. Keyed on businessId alone, the Owner's business
/// ledger and an Agent's ledger were one state object: opening an agent's
/// transactions from OW-002 left the agent's rows sitting in the provider, and
/// a History screen already built lower in the stack never re-ran initState to
/// correct itself. The Owner went on reading the agent's feed as their own.
typedef LedgerScope = ({String businessId, String? membershipId});

/// Keyed by business AND membership so neither the previous business's money
/// nor another person's work is on screen for a frame.
class LedgerHistoryNotifier
    extends FamilyNotifier<LedgerHistoryState, LedgerScope> {
  static const pageSize = 50;

  @override
  LedgerHistoryState build(LedgerScope scope) {
    // Deliberately does not auto-load: screens call load() from initState so
    // tests can seed this provider instead of reaching the network.
    return const LedgerHistoryState();
  }

  /// Whose feed this is. Null means the business ledger, Owner only.
  String? get _membershipId => arg.membershipId;

  LedgerHistoryService get _svc => ref.read(ledgerHistoryServiceProvider);

  /// First page plus the month summary. Also the pull-to-refresh path.
  ///
  /// [withSummary] is false for AG-010: the month summary comes from
  /// day_ledger, which is the whole business, and an agent must never be
  /// shown a business-wide figure derived from data their feed does not
  /// contain.
  Future<void> load({bool withSummary = true}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final events = await _svc.page(
        businessId: arg.businessId,
        membershipId: _membershipId,
        limit: pageSize,
        filter: state.filter,
      );
      final summary = withSummary
          ? await _svc.monthSummary(businessId: arg.businessId)
          : null;
      state = state.copyWith(
        events: events,
        balances: await _balancesFor(events),
        summary: summary,
        loading: false,
        reachedEnd: events.length < pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Openings and closings for every day the loaded feed touches.
  ///
  /// One call for the whole span rather than one per day. A failure here
  /// leaves the balances empty and the days simply show no BF line: a missing
  /// opening must not take the history down with it.
  Future<Map<String, LedgerDayBalance>> _balancesFor(
      List<LedgerEvent> events) async {
    if (events.isEmpty) return const {};
    final dates = events.map((e) => e.businessDate).toList()..sort();
    try {
      return await _svc.dayBalances(
        businessId: arg.businessId,
        from: DateTime.parse(dates.first),
        to: DateTime.parse(dates.last),
        membershipId: _membershipId,
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.reachedEnd || state.events.isEmpty) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final next = await _svc.page(
        businessId: arg.businessId,
        membershipId: _membershipId,
        before: state.events.last.occurredAt,
        limit: pageSize,
        filter: state.filter,
      );
      final all = [...state.events, ...next];
      state = state.copyWith(
        events: all,
        // The appended page reaches further back, so the span grew.
        balances: {...state.balances, ...await _balancesFor(all)},
        loadingMore: false,
        reachedEnd: next.length < pageSize,
      );
    } catch (e) {
      // Keep what is already on screen; a failed append must not blank a
      // list the user is reading.
      state = state.copyWith(loadingMore: false, error: e.toString());
    }
  }

  /// Replaces the filter and reloads from the top. Never filters in memory —
  /// see LedgerFilter's own note.
  ///
  /// The month summary follows the scope rather than a caller's argument: it
  /// comes from day_ledger, which is the whole business. Filtering an Agent's
  /// history used to fetch it anyway, because the default was true and the
  /// screen did not override it -- so a business-wide band appeared over one
  /// person's rows the moment they touched the filter sheet.
  Future<void> applyFilter(LedgerFilter filter) async {
    state = state.copyWith(filter: filter, events: const [], reachedEnd: false);
    await load(withSummary: _membershipId == null);
  }
}

final ledgerHistoryProvider = NotifierProvider.family<LedgerHistoryNotifier,
    LedgerHistoryState, LedgerScope>(
  LedgerHistoryNotifier.new,
);

/// Paging state for the ledger feed, shared by OW-017 and AG-010.
///
/// One notifier for both because the paging, filtering and refresh behaviour
/// is identical — only what the server returns differs, and that is decided by
/// RLS inside `app.ledger_history`, not here. See the SECURITY INVOKER note in
/// migration 20260812130348.
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

  const LedgerHistoryState({
    this.events = const [],
    this.summary,
    this.filter = const LedgerFilter(),
    this.loading = true,
    this.loadingMore = false,
    this.reachedEnd = false,
    this.error,
  });

  List<LedgerDay> get days => groupByBusinessDate(events);

  bool get isEmpty => !loading && error == null && events.isEmpty;

  LedgerHistoryState copyWith({
    List<LedgerEvent>? events,
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
        summary: summary ?? this.summary,
        filter: filter ?? this.filter,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        reachedEnd: reachedEnd ?? this.reachedEnd,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Keyed by businessId so switching business does not show the previous
/// business's money for a frame.
class LedgerHistoryNotifier extends FamilyNotifier<LedgerHistoryState, String> {
  static const pageSize = 50;

  @override
  LedgerHistoryState build(String businessId) {
    // Deliberately does not auto-load: screens call load() from initState so
    // tests can seed this provider instead of reaching the network.
    return const LedgerHistoryState();
  }

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
        businessId: arg,
        limit: pageSize,
        filter: state.filter,
      );
      final summary = withSummary
          ? await _svc.monthSummary(businessId: arg)
          : null;
      state = state.copyWith(
        events: events,
        summary: summary,
        loading: false,
        reachedEnd: events.length < pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.reachedEnd || state.events.isEmpty) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final next = await _svc.page(
        businessId: arg,
        before: state.events.last.occurredAt,
        limit: pageSize,
        filter: state.filter,
      );
      state = state.copyWith(
        events: [...state.events, ...next],
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
  Future<void> applyFilter(LedgerFilter filter, {bool withSummary = true}) async {
    state = state.copyWith(filter: filter, events: const [], reachedEnd: false);
    await load(withSummary: withSummary);
  }
}

final ledgerHistoryProvider =
    NotifierProvider.family<LedgerHistoryNotifier, LedgerHistoryState, String>(
  LedgerHistoryNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../owner_workspace/state/collection_mode_state.dart' show PaymentSplit;
import '../../../shared/mana_time.dart';

/// AG-003 Today's Route — stub API. Per the spec's own API BINDING, no
/// dedicated route endpoint exists: the route is composed client-side from
/// `GET /businesses/{business_id}/loans?agent_membership_id=&status=`
/// (03_Database_Schema.md §1.4/1.5 `routes`/`route_locations` supply the
/// village grouping + visit_order server-side, folded into each loan row's
/// `village`/`visitOrder` fields below rather than fetched as a separate
/// route object) plus the day's collections/no-collection-visits already
/// recorded. "Visit outcome" is not one endpoint but two existing ones —
/// `POST /loans/{loan_id}/collections` (Collected/Partial, via the AG-002
/// handoff) and `POST /loans/{loan_id}/no-collection-visits` (every other
/// outcome) — both already defined on `collectionModeProvider`
/// (owner_workspace/state/collection_mode_state.dart); this file does not
/// duplicate either write path.
class TodaysRouteApiService {
  SupabaseClient get _db => Supabase.instance.client;

  // GET /businesses/{business_id}/loans?agent_membership_id=&status=Active
  // — route is derived client-side from this list. SCHEMA GAP FLAGGED (not
  // silently guessed around): route_locations (03_Database_Schema.md §1.5)
  // orders by `location_id` (routes -> route_locations -> locations),
  // giving the Owner-assigned visit_order — but there is no query path
  // from a given loan's assigned agent + business back to which
  // route/route_locations row that specific customer's stop belongs to
  // without a routes/route_locations join keyed on something this
  // customer-loan list doesn't carry (route assignment is Owner-side,
  // AG-003 only ever reads visit_order, never derives it). `visitOrder`
  // defaults to 0 for every stop pending that join being defined; village
  // grouping IS correctly resolved via person_addresses.village_id ->
  // locations.village_town_name below (an earlier version of this
  // comment incorrectly claimed person_addresses stores a free-text
  // village name — it doesn't, it's a real FK, now joined correctly).
  Future<List<RouteStop>> fetchRoute({
    required String businessId,
    required String agentMembershipId,
  }) async {
    final today = manaBusinessDate();

    // M4: loans RLS calls app.agent_covers_customer() on the loan's customer,
    // so the area-based scoping happens server-side; the explicit
    // customers.assigned_agent_membership_id filter (and column) are gone.
    final loanRows = await _db
        .from('loans')
        .select('loan_id, customer_id, loan_number, remaining_balance, installment_amount, '
            'loan_status, '
            'customers!inner(customer_id, person_id, '
            'persons!inner(full_name, person_addresses(village_id, is_current, locations(village_town_name))))')
        .eq('business_id', businessId)
        .eq('loan_status', 'Active');

    final loanList = (loanRows as List).cast<Map<String, dynamic>>();
    if (loanList.isEmpty) return [];
    final loanIds = loanList.map((r) => r['loan_id'] as String).toList();

    final collectionRows = await _db
        .from('collections')
        .select('loan_id, result_type')
        .inFilter('loan_id', loanIds)
        .eq('business_date', today);
    final collectionsByLoan = {
      for (final r in (collectionRows as List).cast<Map<String, dynamic>>()) r['loan_id'] as String: r['result_type'] as String?,
    };

    final noCollectionRows = await _db
        .from('no_collection_visits')
        .select('loan_id, reason')
        .inFilter('loan_id', loanIds)
        .eq('business_date', today);
    final noCollectionByLoan = {
      for (final r in (noCollectionRows as List).cast<Map<String, dynamic>>()) r['loan_id'] as String: r['reason'] as String?,
    };

    return loanList.map((r) {
      final loanId = r['loan_id'] as String;
      final customer = r['customers'] as Map<String, dynamic>?;
      final person = customer?['persons'] as Map<String, dynamic>?;
      final addresses = (person?['person_addresses'] as List?) ?? const [];
      final currentAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['is_current'] == true,
            orElse: () => addresses.isNotEmpty ? addresses.first as Map<String, dynamic> : null,
          );
      final village = (currentAddress?['locations'] as Map<String, dynamic>?)?['village_town_name'] as String?;
      final resultType = collectionsByLoan[loanId];
      CollectionOutcome? outcome;
      if (resultType == 'Full' || resultType == 'Excess') {
        outcome = CollectionOutcome.collected;
      } else if (resultType == 'Partial') {
        outcome = CollectionOutcome.partial;
      }
      return RouteStop(
        loanId: loanId,
        customerId: r['customer_id'] as String,
        customerName: person?['full_name'] as String? ?? '',
        village: village ?? 'Unknown',
        visitOrder: 0, // see SCHEMA GAP note above
        loanNumber: r['loan_number'] as String,
        todaysDue: (r['installment_amount'] as num).toInt(),
        outstandingBalance: (r['remaining_balance'] as num).toInt(),
        lineRepaymentIndex: 0, // no line_repayment_index column exists anywhere in the real schema — see fix note above; matches the same KNOWN SIMPLIFICATION already used in customer_state.dart/agent_customer_state.dart
        loanStatus: r['loan_status'] as String,
        collectionOutcome: outcome,
        noCollectionReason: noCollectionByLoan[loanId],
      );
    }).toList();
  }
}

final todaysRouteApiServiceProvider = Provider<TodaysRouteApiService>((ref) {
  return TodaysRouteApiService();
});

// ============================================================================
// Models
// ============================================================================

/// One customer/loan stop on the route. Village grouping and `visitOrder`
/// come from `route_locations` (location_id, visit_order) — read-only here;
/// AG-003 never reorders or edits these client-side.
class RouteStop {
  final String loanId;
  final String customerId;
  final String customerName;
  final String village;
  final int visitOrder;
  final String loanNumber;
  final int todaysDue; // whole rupees (M8)
  final int outstandingBalance;
  final int lineRepaymentIndex;
  final String loanStatus; // Active | Closed | ...

  // Today's recorded outcome, if any — derives CustomerVisitStatus.
  final CollectionOutcome? collectionOutcome; // Collected | Partial, from `collections`
  final String? noCollectionReason; // from `no_collection_visits.reason`

  RouteStop({
    required this.loanId,
    required this.customerId,
    required this.customerName,
    required this.village,
    required this.visitOrder,
    required this.loanNumber,
    required this.todaysDue,
    required this.outstandingBalance,
    required this.lineRepaymentIndex,
    required this.loanStatus,
    this.collectionOutcome,
    this.noCollectionReason,
  });

  RouteStop copyWith({
    CollectionOutcome? collectionOutcome,
    String? noCollectionReason,
  }) =>
      RouteStop(
        loanId: loanId,
        customerId: customerId,
        customerName: customerName,
        village: village,
        visitOrder: visitOrder,
        loanNumber: loanNumber,
        todaysDue: todaysDue,
        outstandingBalance: outstandingBalance,
        lineRepaymentIndex: lineRepaymentIndex,
        loanStatus: loanStatus,
        collectionOutcome: collectionOutcome ?? this.collectionOutcome,
        noCollectionReason: noCollectionReason ?? this.noCollectionReason,
      );

  /// CUSTOMER STATUS — derived, not a stored field (per spec). Computed from
  /// `collections` (Collected/Partial), `no_collection_visits.reason`
  /// (House Locked/Shifted Village/Extension Requested/etc.), and
  /// `loans.status` (Closed) for the current business_date.
  CustomerVisitStatus get derivedStatus {
    if (loanStatus == 'Closed') return CustomerVisitStatus.closed;
    if (collectionOutcome == CollectionOutcome.collected) return CustomerVisitStatus.collected;
    if (collectionOutcome == CollectionOutcome.partial) return CustomerVisitStatus.partial;
    switch (noCollectionReason) {
      case 'House Locked':
        return CustomerVisitStatus.houseLocked;
      case 'Shifted Village':
        return CustomerVisitStatus.shiftedVillage;
      case 'Requested Extension':
        return CustomerVisitStatus.extensionRequested;
      case null:
        return CustomerVisitStatus.pending;
      default:
        // Phone Call Not Answered / Customer Not Home / Refused Payment / Other
        return CustomerVisitStatus.skipped;
    }
  }

  bool get isVisited => derivedStatus != CustomerVisitStatus.pending;
}

enum CollectionOutcome { collected, partial }

/// Derived CUSTOMER STATUS vocabulary, per spec: Pending, Collected, Partial,
/// Skipped, House Locked, Shifted Village, Extension Requested, Closed.
enum CustomerVisitStatus {
  pending,
  collected,
  partial,
  skipped,
  houseLocked,
  shiftedVillage,
  extensionRequested,
  closed,
}

/// The full VISIT OUTCOME picker vocabulary (spec's exact list). UI copy
/// must say "Customer Not Home" verbatim — matches the schema ENUM literally
/// (no "Customer Not Available" translation layer).
enum VisitOutcome {
  collected,
  partial,
  phoneCallNotAnswered,
  houseLocked,
  shiftedVillage,
  customerNotHome,
  requestedExtension,
  refusedPayment,
  other,
}

extension VisitOutcomeLabel on VisitOutcome {
  /// Exact no_collection_visits.reason ENUM string for non-collection
  /// outcomes (unused for collected/partial, which route to AG-002 instead).
  String get reasonEnumValue => switch (this) {
        VisitOutcome.phoneCallNotAnswered => 'Phone Call Not Answered',
        VisitOutcome.houseLocked => 'House Locked',
        VisitOutcome.shiftedVillage => 'Shifted Village',
        VisitOutcome.customerNotHome => 'Customer Not Home',
        VisitOutcome.requestedExtension => 'Requested Extension',
        VisitOutcome.refusedPayment => 'Refused Payment',
        VisitOutcome.other => 'Other',
        _ => throw StateError('Collected/Partial route into AG-002, not no_collection_visits'),
      };

  String get displayLabel => switch (this) {
        VisitOutcome.collected => 'Collected',
        VisitOutcome.partial => 'Partial',
        VisitOutcome.phoneCallNotAnswered => 'Phone Call Not Answered',
        VisitOutcome.houseLocked => 'House Locked',
        VisitOutcome.shiftedVillage => 'Shifted Village',
        VisitOutcome.customerNotHome => 'Customer Not Home',
        VisitOutcome.requestedExtension => 'Requested Extension',
        VisitOutcome.refusedPayment => 'Refused Payment',
        VisitOutcome.other => 'Other',
      };

  bool get isNoCollectionOutcome => this != VisitOutcome.collected && this != VisitOutcome.partial;
}

// Re-exported so screens using this file don't need a second import for the
// mixed-payment split type shared with AG-002's collection entry.
typedef RoutePaymentSplit = PaymentSplit;

// ============================================================================
// State
// ============================================================================

class TodaysRouteState {
  final List<RouteStop> stops;
  final bool loading;
  final String? error;

  const TodaysRouteState({
    this.stops = const [],
    this.loading = false,
    this.error,
  });

  /// ROUTE DETAILS — grouped by Village, customers ordered by visit_order
  /// within each village. Agent cannot reorder (Owner-assigned only).
  Map<String, List<RouteStop>> get byVillage {
    final map = <String, List<RouteStop>>{};
    for (final s in stops) {
      map.putIfAbsent(s.village, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.visitOrder.compareTo(b.visitOrder));
    }
    return map;
  }

  List<String> get orderedVillages {
    final villages = byVillage.keys.toList();
    // First visit_order encountered per village, ascending — reflects the
    // route's own ordering rather than an alphabetical relabeling.
    villages.sort((a, b) {
      final aOrder = byVillage[a]!.first.visitOrder;
      final bOrder = byVillage[b]!.first.visitOrder;
      return aOrder.compareTo(bOrder);
    });
    return villages;
  }

  // ROUTE SUMMARY
  int get customersAssigned => stops.length;
  int get customersCompleted => stops.where((s) => s.isVisited).length;
  int get customersPending => customersAssigned - customersCompleted;
  int get estimatedCollection => stops.fold(0, (sum, s) => sum + s.todaysDue);
  int get collectedAmount => stops
      .where((s) => s.collectionOutcome != null)
      .fold(0, (sum, s) => sum + s.todaysDue); // display estimate; exact amount lives in `collections`

  // ROUTE PROGRESS — all computed client-side from Route Summary counts.
  double get completedPercent => customersAssigned == 0 ? 0 : customersCompleted / customersAssigned;
  double get remainingPercent => 1 - completedPercent;
  double get visitPercent => completedPercent;
  double get collectionPercent {
    final collectedOrPartial =
        stops.where((s) => s.derivedStatus == CustomerVisitStatus.collected || s.derivedStatus == CustomerVisitStatus.partial).length;
    return customersAssigned == 0 ? 0 : collectedOrPartial / customersAssigned;
  }

  /// END ROUTE — all customers visited for this session's route → Route
  /// Complete (S4); otherwise stays on AG-003 (S1/S2).
  bool get isRouteComplete => stops.isNotEmpty && customersPending == 0;

  TodaysRouteState copyWith({
    List<RouteStop>? stops,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return TodaysRouteState(
      stops: stops ?? this.stops,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TodaysRouteNotifier extends Notifier<TodaysRouteState> {
  @override
  TodaysRouteState build() => const TodaysRouteState();

  Future<void> load({required String businessId, required String agentMembershipId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(todaysRouteApiServiceProvider);
      final stops = await api.fetchRoute(businessId: businessId, agentMembershipId: agentMembershipId);
      state = state.copyWith(stops: stops, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Called after AG-002's `CollectionEntryScreen` hands back a successful
  /// Collected/Partial result, so AG-003's own list reflects the outcome
  /// without a full reload. Does not itself write `collections` — that
  /// write already happened inside AG-002/`collectionModeProvider`.
  void markCollected({required String loanId, required bool partial}) {
    final updated = state.stops
        .map((s) => s.loanId == loanId
            ? s.copyWith(collectionOutcome: partial ? CollectionOutcome.partial : CollectionOutcome.collected)
            : s)
        .toList();
    state = state.copyWith(stops: updated);
  }

  /// Called after `collectionModeProvider.recordNoCollectionVisit` succeeds
  /// (the actual `POST /loans/{loan_id}/no-collection-visits` write lives
  /// there, shared with AG-002 — not duplicated here) so this screen's list
  /// reflects the outcome.
  void markNoCollectionVisit({required String loanId, required String reasonEnumValue}) {
    final updated = state.stops
        .map((s) => s.loanId == loanId ? s.copyWith(noCollectionReason: reasonEnumValue) : s)
        .toList();
    state = state.copyWith(stops: updated);
  }
}

final todaysRouteProvider = NotifierProvider<TodaysRouteNotifier, TodaysRouteState>(
  TodaysRouteNotifier.new,
);

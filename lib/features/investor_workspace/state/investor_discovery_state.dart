import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// IW-002 Find A Business / Request To Invest — real Supabase wiring.
/// Self-service, no-money-moves-in-app model: this only ever creates a
/// `membership_requests` row. No capacity/waitlist branch — Investor
/// capacity is explicitly unlimited in V1 (Owner decision), so Approved/
/// Rejected are the only two outcomes (both happen later, Owner-side —
/// see submitRequest's own note on why the immediate return is always
/// 'Pending').
class InvestorDiscoveryApiService {
  final Ref ref;
  InvestorDiscoveryApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// GET /businesses/discover?search=&location_id= (§2.9 Business
  /// Discovery, API Spec Part 1). BR-233: "Public-ish, membership-gated
  /// fields... returns only mlbi, name, general_operating_area per
  /// result. No owner name, terms, or financials exposed pre-membership."
  ///
  /// Backed by `app.discover_businesses` (migration 0019), a SECURITY
  /// DEFINER RPC added to close the previously-flagged gap: `businesses`
  /// RLS (0013) only grants SELECT to the Owner or an Active member, so
  /// this RPC exposes only the BR-233-approved public fields plus the
  /// caller's own existing membership/request status (never another
  /// person's data), which is what drives DiscoveryPhase below.
  Future<List<DiscoveredBusiness>> searchBusinesses({required String query}) async {
    final rows = await _db.schema('app').rpc('discover_businesses', params: {
      'p_search': query,
      'p_role': 'Investor',
    });
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return DiscoveredBusiness(
        businessId: r['business_id'] as String,
        businessName: r['business_name'] as String? ?? '',
        mlbi: r['mlbi'] as String? ?? '',
        logoUrl: r['logo_url'] as String?,
        operatingAreas: const [], // no dedicated column in schema; not returned by the RPC
        acceptingNewInvestors: r['accepting_new_investors'] as bool? ?? false,
      );
    }).toList();
  }

  /// POST /businesses/{business_id}/membership-requests (§2.6) with
  /// { requested_role: "Investor", proposed_investment_amount?, remarks? }.
  /// Implemented as a direct INSERT into `membership_requests` — no RPC
  /// needed here, unlike searchBusinesses above: `membership_requests_
  /// self_insert` (0013_rls_module1_tenancy.sql) already permits any
  /// authenticated person to insert their own row
  /// (`WITH CHECK (person_id = app.current_person_id())`), and
  /// `membership_requests_self_select` lets us read it straight back.
  ///
  /// The 24-hour cooldown-after-Rejected rule (BR pattern, §2.6: "a POST
  /// retry before that returns 409 CONFLICT") is NOT enforced by any DB
  /// constraint (no UNIQUE on person_id+business_id+role exists in
  /// 0002_module1_tenancy.sql) — it's application-layer only per the API
  /// spec. Enforced here client-side by checking the most recent existing
  /// request for this (person, business, Investor) before inserting.
  ///
  /// The returned status is always 'Pending' immediately after this call
  /// — Approved/Rejected are later, asynchronous Owner-side actions
  /// (§2.6 PATCH /membership-requests/{request_id}), never a synchronous
  /// result of this insert. This matches the screen's own DiscoveryPhase
  /// handling (submitRequest's 'Pending' branch leads to
  /// DiscoveryPhase.requestPending).
  Future<MembershipRequestResult> submitRequest({
    required String businessId,
    double? proposedInvestmentAmount,
    String? remarks,
  }) async {
    final personIdStr = ref.read(authFlowProvider).personId;
    if (personIdStr == null) {
      throw StateError('No logged-in person_id available — cannot submit a membership request.');
    }
    final personId = int.parse(personIdStr);

    // Cooldown check (app-layer, per §2.6 — see method doc above).
    final existing = await _db
        .from('membership_requests')
        .select('cooldown_until, status')
        .eq('person_id', personId)
        .eq('business_id', businessId)
        .eq('requested_role', 'Investor')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null &&
        existing['status'] == 'Rejected' &&
        existing['cooldown_until'] != null &&
        DateTime.parse(existing['cooldown_until'] as String).isAfter(DateTime.now())) {
      throw StateError(
        'You may reapply to this business after ${DateTime.parse(existing['cooldown_until'] as String).toLocal()}.',
      );
    }

    final row = await _db
        .from('membership_requests')
        .insert({
          'person_id': personId,
          'business_id': businessId,
          'requested_role': 'Investor',
          'proposed_investment_amount': proposedInvestmentAmount,
          'remarks': remarks,
          'status': 'Pending',
        })
        .select('request_id, status, cooldown_until')
        .single();

    return MembershipRequestResult(
      requestId: row['request_id'] as String,
      status: row['status'] as String,
      cooldownUntil: row['cooldown_until'] != null ? DateTime.parse(row['cooldown_until'] as String) : null,
    );
  }
}

final investorDiscoveryApiServiceProvider = Provider<InvestorDiscoveryApiService>((ref) {
  return InvestorDiscoveryApiService(ref: ref);
});

class DiscoveredBusiness {
  final String businessId;
  final String businessName;
  final String mlbi;
  final String? logoUrl;
  final List<String> operatingAreas;
  final bool acceptingNewInvestors;

  DiscoveredBusiness({
    required this.businessId,
    required this.businessName,
    required this.mlbi,
    this.logoUrl,
    this.operatingAreas = const [],
    required this.acceptingNewInvestors,
  });
}

/// Result of a submitted membership request. Approved/Rejected/Pending
/// status drives which S3/S4/S5 phase the screen shows next.
class MembershipRequestResult {
  final String requestId;
  final String status; // Pending | Approved | Rejected
  final DateTime? cooldownUntil; // set only on Rejected (24h cooldown)

  MembershipRequestResult({required this.requestId, required this.status, this.cooldownUntil});
}

enum DiscoveryPhase { search, results, requestPending, approved, rejected }

class InvestorDiscoveryState {
  final DiscoveryPhase phase;
  final String query;
  final List<DiscoveredBusiness> results;
  final bool loading;
  final DiscoveredBusiness? selectedBusiness;
  final MembershipRequestResult? lastRequest;
  final String? error;

  const InvestorDiscoveryState({
    this.phase = DiscoveryPhase.search,
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.selectedBusiness,
    this.lastRequest,
    this.error,
  });

  InvestorDiscoveryState copyWith({
    DiscoveryPhase? phase,
    String? query,
    List<DiscoveredBusiness>? results,
    bool? loading,
    DiscoveredBusiness? selectedBusiness,
    bool clearSelectedBusiness = false,
    MembershipRequestResult? lastRequest,
    String? error,
    bool clearError = false,
  }) {
    return InvestorDiscoveryState(
      phase: phase ?? this.phase,
      query: query ?? this.query,
      results: results ?? this.results,
      loading: loading ?? this.loading,
      selectedBusiness: clearSelectedBusiness ? null : (selectedBusiness ?? this.selectedBusiness),
      lastRequest: lastRequest ?? this.lastRequest,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InvestorDiscoveryNotifier extends Notifier<InvestorDiscoveryState> {
  @override
  InvestorDiscoveryState build() => const InvestorDiscoveryState();

  void setQuery(String q) => state = state.copyWith(query: q);

  Future<void> search() async {
    if (state.query.trim().isEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(investorDiscoveryApiServiceProvider);
      final results = await api.searchBusinesses(query: state.query.trim());
      state = state.copyWith(results: results, loading: false, phase: DiscoveryPhase.results);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void selectBusiness(DiscoveredBusiness business) {
    state = state.copyWith(selectedBusiness: business);
  }

  Future<bool> submitRequest({double? proposedInvestmentAmount, String? remarks}) async {
    final business = state.selectedBusiness;
    if (business == null) return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(investorDiscoveryApiServiceProvider);
      final result = await api.submitRequest(
        businessId: business.businessId,
        proposedInvestmentAmount: proposedInvestmentAmount,
        remarks: remarks,
      );
      final phase = switch (result.status) {
        'Approved' => DiscoveryPhase.approved,
        'Rejected' => DiscoveryPhase.rejected,
        _ => DiscoveryPhase.requestPending,
      };
      state = state.copyWith(lastRequest: result, loading: false, phase: phase);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  void reset() => state = const InvestorDiscoveryState();
}

final investorDiscoveryProvider = NotifierProvider<InvestorDiscoveryNotifier, InvestorDiscoveryState>(
  InvestorDiscoveryNotifier.new,
);

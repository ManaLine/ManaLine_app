import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/mana_time.dart';

/// CW-002 Find A Business / Request To Join — real Supabase wiring. Same
/// shared discovery/membership-request endpoints already confirmed at
/// IW-002 (04_API_Specification_v1 Part 1 §2.9/§2.6) — this mirrors that
/// file's implementation almost exactly, swapping
/// `requested_role: "Customer"` for `"Investor"` and dropping the
/// Investor-only `proposed_investment_amount` field. Self-service,
/// no-money-moves-in-app model: this only ever creates a
/// `membership_requests` row.
class CustomerDiscoveryApiService {
  final Ref ref;
  CustomerDiscoveryApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// GET /businesses/discover?search=&location_id= (§2.9 Business
  /// Discovery). Business Rule: a Business set to "Not Accepting New
  /// Customers" is hidden from name-search results, but MLBI-exact
  /// search can still surface it if the Owner allows — that server-side
  /// search logic is expected to live inside the RPC below; this client
  /// just renders whatever comes back (DiscoveredBusiness.
  /// acceptingNewCustomers is display-only, never filtered client-side —
  /// matches the screen's own onTap behavior, which stays enabled
  /// regardless).
  ///
  /// Backed by `app.discover_businesses` (migration 0019), a SECURITY
  /// DEFINER RPC added to close the previously-flagged gap: `businesses`
  /// RLS (0013) has no public/anon read policy. Shares the same RPC as
  /// the Investor side, called with p_role='Customer' so the accepting-
  /// flag filter and caller-status lookup use the right role.
  Future<List<DiscoveredBusiness>> searchBusinesses({required String query}) async {
    final rows = await _db.schema('app').rpc('discover_businesses', params: {
      'p_search': query,
      'p_role': 'Customer',
    });
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return DiscoveredBusiness(
        businessId: r['business_id'] as String,
        businessName: r['business_name'] as String? ?? '',
        mlbi: r['mlbi'] as String? ?? '',
        logoUrl: r['logo_url'] as String?,
        operatingAreas: const [], // no dedicated column in schema; not returned by the RPC
        acceptingNewCustomers: r['accepting_new_customers'] as bool? ?? false,
      );
    }).toList();
  }

  /// POST /businesses/{business_id}/membership-requests (§2.6) with
  /// { requested_role: "Customer", remarks? }. No
  /// proposed_investment_amount — that field is Investor-only per
  /// membership_requests §1.9 (0002_module1_tenancy.sql: the column
  /// exists on the shared table but is only ever populated on the
  /// Investor path).
  ///
  /// Direct INSERT, no RPC needed — `membership_requests_self_insert`
  /// (0013_rls_module1_tenancy.sql) already permits this
  /// (`WITH CHECK (person_id = app.current_person_id())`), and
  /// `membership_requests_self_select` lets us read the row straight
  /// back. Same 24-hour-cooldown-after-Rejected app-layer check as the
  /// Investor side (no DB constraint backs it — see that file's identical
  /// note). Returned status is always 'Pending' immediately after
  /// insert; Approved/Rejected only ever happen later, Owner-side.
  Future<MembershipRequestResult> submitRequest({
    required String businessId,
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
        .eq('requested_role', 'Customer')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null &&
        existing['status'] == 'Rejected' &&
        existing['cooldown_until'] != null &&
        DateTime.parse(existing['cooldown_until'] as String).isAfter(manaNowIst())) {
      throw StateError(
        'You may reapply to this business after ${DateTime.parse(existing['cooldown_until'] as String).toLocal()}.',
      );
    }

    final row = await _db
        .from('membership_requests')
        .insert({
          'person_id': personId,
          'business_id': businessId,
          'requested_role': 'Customer',
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

final customerDiscoveryApiServiceProvider = Provider<CustomerDiscoveryApiService>((ref) {
  return CustomerDiscoveryApiService(ref: ref);
});

class DiscoveredBusiness {
  final String businessId;
  final String businessName;
  final String mlbi;
  final String? logoUrl;
  final List<String> operatingAreas; // villages covered, per SEARCH RESULT
  // businesses.accepting_new_customers — modeled as its own field (not
  // used to filter results client-side) per CW-002's own rule: a
  // Business can still appear here (via MLBI-exact search) while this is
  // false, if the Owner allowed it. Display-only badge; Request To Join
  // stays enabled regardless, since surfacing in results already implies
  // eligibility — the hide/allow decision already happened server-side.
  final bool acceptingNewCustomers;

  DiscoveredBusiness({
    required this.businessId,
    required this.businessName,
    required this.mlbi,
    this.logoUrl,
    this.operatingAreas = const [],
    required this.acceptingNewCustomers,
  });
}

/// Result of a submitted membership request. Approved/Rejected/Pending
/// status drives which S3/S4/S5 phase the screen shows next.
class MembershipRequestResult {
  final String requestId;
  final String status; // Pending | Approved | Rejected
  final DateTime? cooldownUntil; // set only on Rejected (24h cooldown, membership_requests.cooldown_until)

  MembershipRequestResult({required this.requestId, required this.status, this.cooldownUntil});
}

enum DiscoveryPhase { search, results, requestPending, approved, rejected }

class CustomerDiscoveryState {
  final DiscoveryPhase phase;
  final String query;
  final List<DiscoveredBusiness> results;
  final bool loading;
  final DiscoveredBusiness? selectedBusiness;
  final MembershipRequestResult? lastRequest;
  final String? error;

  const CustomerDiscoveryState({
    this.phase = DiscoveryPhase.search,
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.selectedBusiness,
    this.lastRequest,
    this.error,
  });

  CustomerDiscoveryState copyWith({
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
    return CustomerDiscoveryState(
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

class CustomerDiscoveryNotifier extends Notifier<CustomerDiscoveryState> {
  @override
  CustomerDiscoveryState build() => const CustomerDiscoveryState();

  void setQuery(String q) => state = state.copyWith(query: q);

  Future<void> search() async {
    if (state.query.trim().isEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(customerDiscoveryApiServiceProvider);
      final results = await api.searchBusinesses(query: state.query.trim());
      state = state.copyWith(results: results, loading: false, phase: DiscoveryPhase.results);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void selectBusiness(DiscoveredBusiness business) {
    state = state.copyWith(selectedBusiness: business);
  }

  Future<bool> submitRequest({String? remarks}) async {
    final business = state.selectedBusiness;
    if (business == null) return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(customerDiscoveryApiServiceProvider);
      final result = await api.submitRequest(
        businessId: business.businessId,
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

  void reset() => state = const CustomerDiscoveryState();
}

final customerDiscoveryProvider = NotifierProvider<CustomerDiscoveryNotifier, CustomerDiscoveryState>(
  CustomerDiscoveryNotifier.new,
);

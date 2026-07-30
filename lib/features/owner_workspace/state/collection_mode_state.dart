import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// OW-006 Collection Mode — real Supabase wiring over Module 7
/// (04_API_Specification_v1 Part 3 §8). Shared verbatim with AG-002 (Agent
/// Collection Mode) per spec's own API BINDING — this file is imported
/// directly by ag_002_collection_mode.dart; every method signature below is
/// UNCHANGED from the stub so that screen keeps compiling untouched.
///
/// INTEGRATION FLAG (read before relying on this): `Supabase.instance.client`
/// assumes `Supabase.initialize(...)` has already run in main.dart. As
/// delivered to this session, main.dart does not call it yet — that's the
/// Auth chat's file, not this one's, so it isn't touched here, but until it
/// lands every call below will throw at `Supabase.instance` access, not at
/// the query itself. Flagged for master chat per the briefing.
///
/// IDENTITY FLAG: `authFlowProvider.personId` is typed `String?` and
/// `persons.person_id` is `BIGINT`. This file parses it with `int.parse`
/// (BIGINT fits in Dart's 64-bit `int` on every platform this app targets
/// except web's JS-number `int`, which loses precision above 2^53 — flagged
/// as a real, if currently unlikely-to-bite, risk given person_id is an
/// auto-increment starting at 1).
class CollectionApiService {
  final Ref ref;
  CollectionApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// Not part of the original stub's public surface — internal helper only.
  /// Resolves the ACTIVE business_members.membership_id for the current
  /// logged-in person within [businessId], preferring an Agent-role row
  /// (the common caller of Collection Mode) and falling back to Owner
  /// (BR-199 unrestricted access — an Owner can also record collections
  /// per rls_role_matrix.md's "O: full" on `collections`).
  Future<String> _currentMembershipId(String businessId) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      throw StateError('No logged-in person_id available — cannot resolve business_members.membership_id.');
    }
    final rows = await _db
        .from('business_members')
        .select('membership_id, role')
        .eq('person_id', int.parse(personId))
        .eq('business_id', businessId)
        .eq('membership_status', 'Active')
        .inFilter('role', ['Agent', 'Owner']);
    if (rows.isEmpty) {
      throw StateError('Current person has no Active Agent/Owner membership in business $businessId.');
    }
    final agentRow = rows.firstWhere((r) => r['role'] == 'Agent', orElse: () => rows.first);
    return agentRow['membership_id'] as String;
  }

  /// GET-equivalent: today's collection due list for [businessId]. RLS
  /// (0016_rls_module7/0015_rls_module6) already scopes this correctly per
  /// caller — an Agent sees only their assigned customers' loans, an Owner
  /// sees the whole business; no extra role branching needed here, per the
  /// briefing's "RLS is a feature, not a bug to work around."
  ///
  /// KNOWN SIMPLIFICATION (flagged, not silently cut): the locked sort
  /// (Penalty → Grace Period → Today's Due → Village → Name) is applied
  /// client-side in `_applyLockedSort` using `penaltyEligible`/`gracePeriod`
  /// booleans derived below from `loan_status` alone. A precise "is an
  /// installment due TODAY" computation requires joining `loan_schedule`
  /// on `due_date = business's current business_date` (from
  /// `account_periods`), which this single query does not attempt — every
  /// loan in Active/Grace Period/Penalty status for the business is
  /// returned instead, and `installmentDue` is the loan's flat
  /// `installment_amount` rather than a specific schedule row's amount.
  /// Recommend a Postgres VIEW (e.g. `v_collection_due_today`) as a
  /// follow-up so this logic has one server-side source of truth instead of
  /// being approximated per-client — this is exactly the kind of
  /// multi-table derived query the briefing warns against reimplementing
  /// ad hoc in Dart.
  Future<List<CollectionDueRow>> fetchDueList({required String businessId}) async {
    final rows = await _db
        .from('loans')
        .select('''
          loan_id, loan_number, installment_amount, remaining_balance, loan_status,
          customers!inner(
            customer_id,
            persons!inner(full_name)
          ),
          collection_agent_membership_id,
          business_members!loans_collection_agent_membership_id_fkey(
            persons!business_members_person_id_fkey(full_name)
          )
        ''')
        .eq('business_id', businessId)
        .inFilter('loan_status', ['Active', 'Grace Period', 'Penalty']);

    return (rows as List).map((r) {
      final customer = r['customers'] as Map<String, dynamic>;
      final customerPerson = customer['persons'] as Map<String, dynamic>;
      final agentMember = r['business_members'] as Map<String, dynamic>?;
      final agentPerson = agentMember?['persons'] as Map<String, dynamic>?;
      final status = r['loan_status'] as String;
      return CollectionDueRow(
        loanId: r['loan_id'] as String,
        customerName: (customerPerson['full_name'] as String?) ?? '',
        // Village is intentionally omitted here (see KNOWN SIMPLIFICATION
        // above) rather than guessed — no person_addresses join is
        // attempted so this never silently shows a stale/wrong village.
        village: '',
        loanNumber: r['loan_number'] as String,
        installmentDue: (r['installment_amount'] as num).toDouble(),
        outstandingBalance: (r['remaining_balance'] as num).toDouble(),
        lineRepaymentIndex: 0, // requires loan_schedule join — see KNOWN SIMPLIFICATION
        collectionStatus: 'Pending', // per-installment status also requires loan_schedule; approximated
        collectionAgent: (agentPerson?['full_name'] as String?) ?? '',
        penaltyEligible: status == 'Penalty',
        gracePeriod: status == 'Grace Period',
      );
    }).toList();
  }

  /// POST-equivalent: records a Collection, its payment split rows, and
  /// deducts from the loan's remaining_balance — all three MUST happen
  /// atomically (a collection recorded without its splits, or without the
  /// balance actually moving, is a data-integrity bug a plain multi-step
  /// Postgrest call cannot safely guarantee under a dropped connection
  /// between steps). Implemented as a single RPC call rather than 3
  /// sequential `.insert()`s for that reason.
  ///
  /// BLOCKED ON EDGE FUNCTION / RPC: `record_collection` does not exist yet
  /// in the schema (grep of 0001-0018 confirms no CREATE FUNCTION besides
  /// the `app.*` RLS helpers). Expected signature:
  ///   supabase.rpc('record_collection', params: {
  ///     'p_loan_id': loanId,
  ///     'p_collected_amount': collectedAmount,
  ///     'p_payer_type': payerType,
  ///     'p_guarantor_id': guarantorId,
  ///     'p_collected_by_membership_id': <resolved via _currentMembershipId>,
  ///     'p_payment_splits': paymentSplits.map((s) => {'payment_mode': s.paymentMode, 'amount': s.amount}).toList(),
  ///     'p_excess_disposition': excessDisposition,
  ///     'p_remarks': remarks,
  ///   })
  /// Expected to return a row shaped like `collections` plus the computed
  /// `result_type`/`difference_amount` (Full/Partial/Excess, per
  /// installment_amount vs collectedAmount — BR-023/025 split-payment
  /// logic) so this client never recomputes that classification itself.
  Future<CollectionResult> recordCollection({
    required String loanId,
    required double collectedAmount,
    required String payerType, // Customer | Guarantor
    String? guarantorId,
    required List<PaymentSplit> paymentSplits,
    String? excessDisposition, // Advance | Refund | Next Installment
    String? remarks,
  }) async {
    throw UnimplementedError(
      'BLOCKED on RPC "record_collection" (not yet built — see class-level doc comment for expected '
      'params/return shape). Needs to be a Postgres function/Edge Function for atomic '
      'collections + collection_payment_splits + loans.remaining_balance update, per the '
      'briefing\'s "do not reimplement multi-table financial writes as client-side Dart" instruction.',
    );
  }

  /// POST /no_collection_visits — a single-table insert with no derived
  /// financial math, safe to do directly (unlike recordCollection above).
  Future<void> recordNoCollectionVisit({required String loanId, required String reason}) async {
    final loan = await _db.from('loans').select('business_id, customer_id').eq('loan_id', loanId).single();
    final membershipId = await _currentMembershipId(loan['business_id'] as String);
    await _db.from('no_collection_visits').insert({
      'loan_id': loanId,
      'customer_id': loan['customer_id'],
      'visited_by_membership_id': membershipId,
      'reason': reason,
      'business_date': DateTime.now().toIso8601String().split('T').first,
    });
  }

  /// POST /extension_requests — single-table insert. `requested_by` is
  /// derived from whichever role the current membership resolves to
  /// (Agent vs Customer), per BR schema note: "either party inserting a
  /// row falsely attributed to the other's requested_by value" must be
  /// prevented — RLS (0015) already pins this at the policy layer, but we
  /// also set it correctly here rather than relying on RLS to silently
  /// reject a wrong value with a confusing error.
  Future<String> requestExtension({required String loanId, String? remarks}) async {
    final loan = await _db.from('loans').select('business_id').eq('loan_id', loanId).single();
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    final role = await _db
        .from('business_members')
        .select('role')
        .eq('person_id', int.parse(personId))
        .eq('business_id', loan['business_id'] as String)
        .eq('membership_status', 'Active')
        .inFilter('role', ['Agent', 'Customer']);
    final requestedBy = role.isNotEmpty ? (role.first['role'] as String) : 'Agent';
    final inserted = await _db
        .from('extension_requests')
        .insert({
          'loan_id': loanId,
          'requested_by': requestedBy,
          'status': 'Pending',
          'business_date': DateTime.now().toIso8601String().split('T').first,
        })
        .select('extension_id')
        .single();
    // NOTE: `remarks` is accepted by this method's signature (kept
    // unchanged for AG-002 compatibility) but extension_requests has no
    // remarks column in the locked schema (§6.6) — silently dropped rather
    // than guessed into some other column. Flagged as a schema/UI mismatch:
    // either the screen's remarks field should be removed, or the schema
    // needs an addendum column, master chat's call.
    return inserted['extension_id'] as String;
  }

  /// PATCH /extension_requests/{id} — Owner decision only (schema: "Owner
  /// decision"). `decided_by_person_id` set to the current person; RLS
  /// restricts the actual UPDATE to Owner-context callers regardless.
  Future<void> decideExtension({required String extensionRequestId, required bool approved}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    await _db.from('extension_requests').update({
      'status': approved ? 'Approved' : 'Rejected',
      'decided_by_person_id': int.parse(personId),
    }).eq('extension_id', extensionRequestId);
  }
}

class PaymentSplit {
  final String paymentMode; // Cash | UPI | Bank Transfer | Cheque
  final double amount;
  PaymentSplit({required this.paymentMode, required this.amount});
}

class CollectionDueRow {
  final String loanId;
  final String customerName;
  final String village;
  final String loanNumber;
  final double installmentDue;
  final double outstandingBalance;
  final int lineRepaymentIndex;
  final String collectionStatus; // Pending | Collected | Partial | Skipped | Closed
  final String collectionAgent;
  final bool penaltyEligible;
  final bool gracePeriod;

  CollectionDueRow({
    required this.loanId,
    required this.customerName,
    required this.village,
    required this.loanNumber,
    required this.installmentDue,
    required this.outstandingBalance,
    required this.lineRepaymentIndex,
    required this.collectionStatus,
    required this.collectionAgent,
    this.penaltyEligible = false,
    this.gracePeriod = false,
  });
}

class CollectionResult {
  final String receiptNumber;
  final String resultType; // Full | Partial | Excess
  final double collectedAmount;
  final double newOutstandingBalance;
  final DateTime businessDate;
  final DateTime entryTimestamp;

  CollectionResult({
    required this.receiptNumber,
    required this.resultType,
    required this.collectedAmount,
    required this.newOutstandingBalance,
    required this.businessDate,
    required this.entryTimestamp,
  });
}

final collectionApiServiceProvider = Provider<CollectionApiService>((ref) {
  return CollectionApiService(ref: ref);
});

/// Cascading sort per spec: Penalty → Grace Period → Today's Due →
/// Village → Customer Name.
List<CollectionDueRow> _applyLockedSort(List<CollectionDueRow> list) {
  final sorted = [...list];
  sorted.sort((a, b) {
    if (a.penaltyEligible != b.penaltyEligible) return a.penaltyEligible ? -1 : 1;
    if (a.gracePeriod != b.gracePeriod) return a.gracePeriod ? -1 : 1;
    final byDue = b.installmentDue.compareTo(a.installmentDue);
    if (byDue != 0) return byDue;
    final byVillage = a.village.compareTo(b.village);
    if (byVillage != 0) return byVillage;
    return a.customerName.compareTo(b.customerName);
  });
  return sorted;
}

class CollectionModeState {
  final List<CollectionDueRow> dueList;
  final bool loading;
  final String? error;
  final double liveCollectionAmount;

  const CollectionModeState({
    this.dueList = const [],
    this.loading = false,
    this.error,
    this.liveCollectionAmount = 0,
  });

  List<CollectionDueRow> get sorted => _applyLockedSort(dueList);
  int get totalDue => dueList.length;
  int get collected => dueList.where((r) => r.collectionStatus == 'Collected').length;
  int get pending => dueList.where((r) => r.collectionStatus == 'Pending').length;
  int get skipped => dueList.where((r) => r.collectionStatus == 'Skipped').length;
  int get penaltyCount => dueList.where((r) => r.penaltyEligible).length;
  int get graceCount => dueList.where((r) => r.gracePeriod).length;

  CollectionModeState copyWith({
    List<CollectionDueRow>? dueList,
    bool? loading,
    String? error,
    bool clearError = false,
    double? liveCollectionAmount,
  }) {
    return CollectionModeState(
      dueList: dueList ?? this.dueList,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      liveCollectionAmount: liveCollectionAmount ?? this.liveCollectionAmount,
    );
  }
}

class CollectionModeNotifier extends Notifier<CollectionModeState> {
  @override
  CollectionModeState build() => const CollectionModeState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(collectionApiServiceProvider);
      final list = await api.fetchDueList(businessId: businessId);
      state = state.copyWith(dueList: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<CollectionResult?> recordCollection({
    required String loanId,
    required double collectedAmount,
    required String payerType,
    String? guarantorId,
    required List<PaymentSplit> paymentSplits,
    String? excessDisposition,
    String? remarks,
  }) async {
    try {
      final api = ref.read(collectionApiServiceProvider);
      final result = await api.recordCollection(
        loanId: loanId,
        collectedAmount: collectedAmount,
        payerType: payerType,
        guarantorId: guarantorId,
        paymentSplits: paymentSplits,
        excessDisposition: excessDisposition,
        remarks: remarks,
      );
      state = state.copyWith(liveCollectionAmount: state.liveCollectionAmount + collectedAmount);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> recordNoCollectionVisit({required String loanId, required String reason}) async {
    try {
      await ref.read(collectionApiServiceProvider).recordNoCollectionVisit(loanId: loanId, reason: reason);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> requestAndDecideExtension({required String loanId, required bool approve}) async {
    try {
      final api = ref.read(collectionApiServiceProvider);
      final requestId = await api.requestExtension(loanId: loanId);
      await api.decideExtension(extensionRequestId: requestId, approved: approve);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final collectionModeProvider = NotifierProvider<CollectionModeNotifier, CollectionModeState>(
  CollectionModeNotifier.new,
);

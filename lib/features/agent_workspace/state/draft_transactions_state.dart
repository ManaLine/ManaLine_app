import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AG-005 Draft Transactions — real Supabase wiring over
/// `collection_drafts`. Note: this table has NO business_id column of its
/// own — it's reached only via created_by_membership_id ->
/// business_members.business_id, so fetchOwnDrafts joins through that
/// rather than filtering business_id directly (which doesn't exist here).
class DraftTransactionsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<DraftTransaction>> fetchOwnDrafts({
    required String businessId,
    required String membershipId,
  }) async {
    final rows = await _db
        .from('collection_drafts')
        .select('draft_id, draft_type, status, payload_json, loan_id, created_at, updated_at, '
            'business_members!inner(business_id)')
        .eq('created_by_membership_id', membershipId)
        .eq('business_members.business_id', businessId)
        .eq('status', 'Draft')
        .order('updated_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final payload = (r['payload_json'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      return DraftTransaction(
        draftId: r['draft_id'] as String,
        draftType: DraftTypeX.fromSchemaValue(r['draft_type'] as String),
        status: _statusFromString(r['status'] as String),
        customerName: payload['customer_name'] as String?,
        loanNumber: payload['loan_number'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        payloadJson: payload,
        loanId: r['loan_id'] as String?,
      );
    }).toList();
  }

  DraftStatus _statusFromString(String s) => switch (s) {
        'Draft' => DraftStatus.draft,
        'Submitted' => DraftStatus.submitted,
        'Discarded' => DraftStatus.discarded,
        _ => DraftStatus.draft,
      };

  /// BLOCKED ON RPC: submitting a draft must, in one transaction: validate
  /// payload_json against the target table's real required fields, INSERT
  /// the real record on whichever of collections/loans/customer_remarks/
  /// customer_documents draft_type points to, then remove/close the draft
  /// row — same atomicity class as record_collection/apply_loan_penalty
  /// flagged elsewhere this session. A plain multi-step Postgrest sequence
  /// here specifically also can't safely branch on draft_type client-side
  /// without risking a draft that's half-submitted (target record created,
  /// draft row not deleted/closed, or vice versa) if the connection drops
  /// mid-sequence.
  ///
  /// UNCHANGED from prior flag, but now doubly justified: even the
  /// "delete the draft row at the end" half of this operation cannot be
  /// done as a plain client DELETE regardless (see discardDraft's own
  /// note below on the live RLS having no DELETE policy for any role on
  /// this table) — so the whole submit+delete-or-close sequence needs to
  /// happen inside a SECURITY DEFINER function that can bypass RLS for
  /// its own internal bookkeeping, not assembled from client calls.
  // FIXED (this pass): app.submit_draft RPC now exists (migration 0025,
  // all 4 draft_types), returning JSON with a type-specific id key
  // (loan_id/collection_id/remark_id/document_id) plus draft_type. Extract
  // whichever key is present rather than assuming one — the DraftSubmitResult
  // shape here is deliberately type-agnostic (just resultingRecordId).
  Future<DraftSubmitResult> submitDraft({required String draftId}) async {
    final result = await _db.rpc('submit_draft', params: {'p_draft_id': draftId}) as Map<String, dynamic>;
    final id = (result['loan_id'] ?? result['collection_id'] ?? result['remark_id'] ?? result['document_id']) as String;
    return DraftSubmitResult(resultingRecordId: id);
  }

  /// SCHEMA/RLS MISMATCH FIXED THIS SESSION: AG-005's own spec doc
  /// ("Draft Deleted... literal row delete... drafts are the one record
  /// type in this schema where DELETE /drafts/{draft_id} is genuinely
  /// used") and this method's ORIGINAL body both assumed a real hard
  /// `DELETE`. The live, enforced RLS (0016_rls_module7_collection_domain
  /// .sql) explicitly states otherwise in its own comment: "no DELETE
  /// policy is offered to any role for this or any other table" — the
  /// only Agent-facing write policy beyond INSERT is
  /// `collection_drafts_agent_update_own`, gated on
  /// `can_edit_own_drafts` OR `can_cancel_own_drafts`, and it is an
  /// UPDATE policy, not a DELETE one. Owner has `FOR ALL` (which does
  /// include DELETE) but an Agent discarding their OWN draft never goes
  /// through the Owner policy.
  ///
  /// Practical effect of the ORIGINAL code: `.delete()` as an
  /// authenticated Agent would match zero rows under RLS and return
  /// successfully with no rows affected — Postgrest does not error on a
  /// 0-row delete — so the Discard button would appear to work while
  /// silently doing nothing. Fixed here to do what the live policy
  /// actually authorizes: `status: 'Discarded'`, matching the §7.4 API
  /// spec's own alternative ("or equivalently PATCH /drafts/{draft_id}
  /// with status='Discarded' to keep a soft trail — both are supported").
  /// `updated_at` is left to the row's own default/trigger if one exists;
  /// no trigger for `updated_at` auto-touch is defined in the schema
  /// (0008), so it's set explicitly here to keep `fetchOwnDrafts`'
  /// ordering meaningful.
  Future<void> discardDraft({required String draftId}) async {
    await _db.from('collection_drafts').update({
      'status': 'Discarded',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('draft_id', draftId);
  }
}

final draftTransactionsApiServiceProvider = Provider<DraftTransactionsApiService>((ref) {
  return DraftTransactionsApiService();
});

// ============================================================================
// Models
// ============================================================================

enum DraftType { collection, loanDistribution, customerRemark, documentUpload }

extension DraftTypeX on DraftType {
  String get schemaValue => switch (this) {
        DraftType.collection => 'Collection',
        DraftType.loanDistribution => 'Loan Distribution',
        DraftType.customerRemark => 'Customer Remark',
        DraftType.documentUpload => 'Document Upload',
      };

  static DraftType fromSchemaValue(String v) => switch (v) {
        'Collection' => DraftType.collection,
        'Loan Distribution' => DraftType.loanDistribution,
        'Customer Remark' => DraftType.customerRemark,
        'Document Upload' => DraftType.documentUpload,
        _ => throw ArgumentError('Unknown draft_type: $v'),
      };
}

enum DraftStatus { draft, submitted, discarded }

class DraftTransaction {
  final String draftId;
  final DraftType draftType;
  final DraftStatus status;
  final String? customerName;
  final String? loanNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> payloadJson;
  final String? loanId;

  DraftTransaction({
    required this.draftId,
    required this.draftType,
    required this.status,
    this.customerName,
    this.loanNumber,
    required this.createdAt,
    required this.updatedAt,
    this.payloadJson = const {},
    this.loanId,
  });
}

class DraftSubmitResult {
  final String resultingRecordId;
  DraftSubmitResult({required this.resultingRecordId});
}

// ============================================================================
// State
// ============================================================================

class DraftTransactionsState {
  final List<DraftTransaction> drafts;
  final bool loading;
  final String? error;

  const DraftTransactionsState({
    this.drafts = const [],
    this.loading = false,
    this.error,
  });

  List<DraftTransaction> get openDrafts => drafts.where((d) => d.status == DraftStatus.draft).toList();

  DraftTransactionsState copyWith({
    List<DraftTransaction>? drafts,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return DraftTransactionsState(
      drafts: drafts ?? this.drafts,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DraftTransactionsNotifier extends Notifier<DraftTransactionsState> {
  @override
  DraftTransactionsState build() => const DraftTransactionsState();

  Future<void> load({required String businessId, required String membershipId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(draftTransactionsApiServiceProvider);
      final drafts = await api.fetchOwnDrafts(businessId: businessId, membershipId: membershipId);
      state = state.copyWith(drafts: drafts, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<DraftSubmitResult?> submit({required String businessId, required String membershipId, required String draftId}) async {
    try {
      final api = ref.read(draftTransactionsApiServiceProvider);
      final result = await api.submitDraft(draftId: draftId);
      await load(businessId: businessId, membershipId: membershipId);
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> discard({required String businessId, required String membershipId, required String draftId}) async {
    try {
      final api = ref.read(draftTransactionsApiServiceProvider);
      await api.discardDraft(draftId: draftId);
      await load(businessId: businessId, membershipId: membershipId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final draftTransactionsProvider = NotifierProvider<DraftTransactionsNotifier, DraftTransactionsState>(
  DraftTransactionsNotifier.new,
);

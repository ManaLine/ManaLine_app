import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SP-001 — Duplicate-Aadhaar Dispute Resolution.
///
/// SCOPE NOTE (unchanged from stub): SP-001's own spec confirms this is
/// "entirely separate internal tool/dashboard, outside the Owner/Agent/
/// Investor/Customer app; no MLID login, no app-side integration," and
/// that a dedicated Support-tool UI/access-model (who logs in, what
/// permissions) is explicitly RESOLVED as intentional future work, not a
/// gap for this chat to fill. This state file therefore has no auth/
/// session concept of its own — see the screen file's stub gate.
///
/// AUTH MODEL (no service_role anywhere): every RPC below is gated by
/// `app.is_platform_admin()` (see
/// 0028_module19_sp001_platform_admin_and_rpcs.sql) against a
/// `platform_admins` table keyed by person_id — the same table-driven
/// pattern every other permission check in this codebase already uses
/// (agent_permissions, business_members roles, etc.). Support staff sign
/// in with a genuine Supabase session (a JWT carrying the `person_id`
/// claim, same mechanism as `app.current_person_id()` everywhere else in
/// this codebase) but hold no business_members role at all — their SP-001
/// access comes purely from having a row in `platform_admins`. The
/// service_role key is never used or assumed here. Granting platform-admin
/// status has no client-facing path (the table has zero RLS policies, by
/// design) — see the migration's own comment for how the first row is
/// expected to be added.
class AadhaarDisputeApiService {
  AadhaarDisputeApiService();

  SupabaseClient get _db => Supabase.instance.client;

  // --- Step 1: Case Intake — lookup existing account by MLID/Aadhaar ------

  // RPC: support_lookup_person(p_search). SPEC GAP (carried over from the
  // original stub's own comment): SP-001 doesn't name a dedicated lookup
  // endpoint — it describes the workflow, not the Support-tool's API
  // surface. Modeled as an mlid-exact-or-last8-suffix match; see the
  // migration's comment for the reasoning and the flag for backend
  // confirmation of a different matching strategy.
  Future<DisputeCaseLookup> lookupExistingAccount({
    String? mlid,
    String? aadhaarNumber,
  }) async {
    final search = (mlid?.trim().isNotEmpty ?? false) ? mlid!.trim() : (aadhaarNumber ?? '').trim();
    final rows = await _db.rpc('support_lookup_person', params: {'p_search': search}) as List;
    if (rows.isEmpty) {
      throw StateError('No account found for "$search".');
    }
    final row = rows.first as Map<String, dynamic>;
    return DisputeCaseLookup(
      personId: (row['person_id'] as num).toString(),
      currentMlid: row['mlid'] as String,
      fullName: row['full_name'] as String? ?? '',
    );
  }

  // RPC: support_upload_identity_document(p_person_id, p_document_type,
  // p_file_url) — DATA MODEL TOUCHED names `identity_documents`
  // (both parties' proof). document_type = 'Aadhaar' per
  // identity_document_type_enum ('Aadhaar', 'Photo', 'Address Proof',
  // 'Other') — both parties are submitting proof of their real Aadhaar.
  //
  // SIGNATURE CHANGE, FLAGGED: added an optional `personId` parameter not
  // present in the original stub. Reason: identity_documents.person_id is
  // NOT NULL, so persisting a row requires a real person_id — the original
  // stub's signature (personLabel + documentUrl only) had no way to supply
  // one. Backward-compatible: omitting personId (the second_person path)
  // behaves exactly as before.
  //
  // SCHEMA CONFLICT (unresolved, flagged — see migration comment for full
  // detail): the second person has NO person_id at Step 1 (registration
  // only happens at Step 6, out of SP-001's own scope). This method can
  // only persist to identity_documents for personLabel == 'original_holder'
  // (a real, existing person_id). For personLabel == 'second_person' there
  // is currently no schema-correct place to store the file at all; it
  // stays local-only in case state (see notifier) until that gap is
  // resolved by master chat.
  Future<String> uploadProofDocument({
    required String personLabel, // 'second_person' | 'original_holder'
    required String documentUrl,
    String? personId, // FLAGGED ADDITION — required when personLabel == 'original_holder'
  }) async {
    if (personLabel == 'original_holder') {
      if (personId == null) {
        throw ArgumentError('personId is required to persist the original holder\'s proof document.');
      }
      await _db.rpc('support_upload_identity_document', params: {
        'p_person_id': int.parse(personId),
        'p_document_type': 'Aadhaar',
        'p_file_url': documentUrl,
      });
    }
    // second_person: local-only per the SCHEMA CONFLICT note above.
    return documentUrl;
  }

  // --- Step 3: On second-person Verified — suspend original account -------

  // RPC: support_suspension_impact(p_person_id) — read-only enumeration of
  // businesses owned + other-role memberships, shown to Support staff
  // BEFORE they confirm anything (screen's suspensionConfirm step).
  Future<SuspensionImpactSummary> fetchSuspensionImpact({required String personId}) async {
    final rows = await _db.rpc('support_suspension_impact', params: {
      'p_person_id': int.parse(personId),
    }) as List;
    return SuspensionImpactSummary(
      rows: rows.cast<Map<String, dynamic>>().map((r) {
        return SuspensionImpactRow(
          id: r['id'] as String,
          label: r['label'] as String? ?? '',
          role: r['role'] as String? ?? '',
          isOwnerBusiness: r['is_owner_business'] as bool,
        );
      }).toList(),
    );
  }

  // RPC: support_suspend_business(p_business_id) — PATCH-equivalent,
  // business_status -> 'Suspended', for a business the disputed person owns.
  Future<void> suspendBusiness({required String businessId}) async {
    await _db.rpc('support_suspend_business', params: {'p_business_id': businessId});
  }

  // RPC: support_suspend_membership(p_membership_id) — membership_status ->
  // 'Suspended', for an Agent/Investor/Customer membership held elsewhere
  // (never the business itself — BR-202/203 multi-tenancy, that business
  // has its own separate Owner).
  Future<void> suspendMembership({required String membershipId}) async {
    await _db.rpc('support_suspend_membership', params: {'p_membership_id': membershipId});
  }

  // --- Step 4: Original Holder Re-Verification ----------------------------

  // Reuses uploadProofDocument above (personLabel: 'original_holder',
  // personId: the disputed account's own person_id).

  // --- Step 5: Single Resolution Action ------------------------------------

  // RPC: support_unsuspend_business(p_business_id) -> 'Active'.
  Future<void> unsuspendBusiness({required String businessId}) async {
    await _db.rpc('support_unsuspend_business', params: {'p_business_id': businessId});
  }

  // RPC: support_unsuspend_membership(p_membership_id) -> 'Active'.
  Future<void> unsuspendMembership({required String membershipId}) async {
    await _db.rpc('support_unsuspend_membership', params: {'p_membership_id': membershipId});
  }

  // RPC: support_upgrade_mlid_dispute(p_person_id, p_corrected_aadhaar,
  // p_reason) — 04_API_Specification_v1_Part1.md §1.1 upgrade-mlid,
  // "Aadhaar Correction — Dispute Resolution" variant. person_id never
  // changes; writes person_id_history atomically inside the RPC.
  //
  // OTP RE-VERIFICATION — FLAGGED, NOT IMPLEMENTED: the general
  // upgrade-mlid endpoint "Triggers OTP re-verification (purpose=
  // Registration)" per the API spec. No otp_verifications-writing RPC
  // exists anywhere in this codebase to reuse (checked: 0012's own RLS
  // comment says OTP issuance/verification "must go through a server-side
  // function," but no such function exists in any reviewed migration; no
  // LR-005/AuthApiService file was available to this chat to confirm a
  // pattern one way or the other). Separately: SP-001's own flow already
  // gates progression on manual human verification (Steps 2 and 4b,
  // ManualVerificationDecision.verified) at exactly the points an OTP step
  // would otherwise gate — whether that's meant to substitute for OTP here
  // or happen alongside it is not stated by either spec document. Not
  // silently resolved either way; flagged for master chat.
  Future<MlidUpgradeResult> upgradeMlid({
    required String personId,
    required String correctedAadhaar,
    required String reason, // always "Aadhaar Correction — Dispute Resolution" for this flow
  }) async {
    final rows = await _db.rpc('support_upgrade_mlid_dispute', params: {
      'p_person_id': int.parse(personId),
      'p_corrected_aadhaar': correctedAadhaar,
      'p_reason': reason,
    }) as List;
    final row = rows.first as Map<String, dynamic>;
    return MlidUpgradeResult(
      personId: (row['person_id'] as num).toString(),
      newMlid: row['new_mlid'] as String,
    );
  }

  // RPC: support_fetch_latest_id_history(p_person_id) — read-back of the
  // row upgradeMlid just wrote, for the read-only "MLID Correction Record"
  // display. Routed through a gated RPC rather than a raw table SELECT: a
  // platform admin holds no business_members row anywhere (by design), so
  // neither of person_id_history's existing RLS policies (self-select /
  // owner-of-shared-business-select, 0012) would ever match this caller —
  // a raw SELECT would silently return zero rows instead of the intended
  // "not authorized" signal.
  Future<PersonIdHistoryEntry> fetchLatestIdHistoryEntry({required String personId}) async {
    final rows = await _db.rpc('support_fetch_latest_id_history', params: {
      'p_person_id': int.parse(personId),
    }) as List;
    if (rows.isEmpty) {
      throw StateError('No person_id_history entry found for person $personId.');
    }
    final row = rows.first as Map<String, dynamic>;
    return PersonIdHistoryEntry(
      oldMlid: row['old_mlid'] as String,
      newMlid: row['new_mlid'] as String,
      reason: row['reason'] as String? ?? '',
      recordedAt: DateTime.parse(row['changed_at'] as String),
    );
  }
}

final aadhaarDisputeApiServiceProvider = Provider<AadhaarDisputeApiService>((ref) {
  return AadhaarDisputeApiService();
});

// ============================================================================
// Result / model types (unchanged from stub)
// ============================================================================

class DisputeCaseLookup {
  final String personId;
  final String currentMlid;
  final String fullName; // shown only to the Support operator, never the registrant
  DisputeCaseLookup({required this.personId, required this.currentMlid, required this.fullName});
}

/// One row of the pre-confirm suspension summary (Step 3) — either a
/// business the person Owns (whole business suspended) or a membership
/// held elsewhere (only that membership suspended).
class SuspensionImpactRow {
  final String id; // business_id if isOwnerBusiness, else membership_id
  final String label; // business name
  final String role; // 'Owner' | 'Agent' | 'Investor' | 'Customer'
  final bool isOwnerBusiness;
  SuspensionImpactRow({
    required this.id,
    required this.label,
    required this.role,
    required this.isOwnerBusiness,
  });
}

class SuspensionImpactSummary {
  final List<SuspensionImpactRow> rows;
  SuspensionImpactSummary({required this.rows});
}

class MlidUpgradeResult {
  final String personId;
  final String newMlid;
  MlidUpgradeResult({required this.personId, required this.newMlid});
}

class PersonIdHistoryEntry {
  final String oldMlid;
  final String newMlid;
  final String reason;
  final DateTime recordedAt;
  PersonIdHistoryEntry({
    required this.oldMlid,
    required this.newMlid,
    required this.reason,
    required this.recordedAt,
  });
}

// ============================================================================
// Case flow state — one dispute case at a time, linear step-based
// (Support staff operates this manually per the spec's PRIMARY USER note).
// State shape and all public notifier method names/signatures are UNCHANGED
// from the original stub — only the internal bodies now call real RPCs, and
// the per-row suspend/unsuspend loop over `impact.rows` (calling
// suspendBusiness/suspendMembership or unsuspendBusiness/
// unsuspendMembership per row) is preserved exactly as originally
// structured, matching the restored per-row method signatures.
// ============================================================================

enum DisputeStep {
  caseIntake, // Step 1
  secondPersonVerification, // Step 2
  suspensionConfirm, // Step 3
  originalHolderIntake, // Step 4a
  originalHolderVerification, // Step 4b
  resolution, // Step 5
  caseClosed, // Step 6
}

enum ManualVerificationDecision { pending, verified, notVerified }

class AadhaarDisputeCaseState {
  final DisputeStep step;

  // Step 1 — Case Intake
  final String searchMlidOrAadhaarInput;
  final bool looking;
  final DisputeCaseLookup? existingAccount;
  final String? secondPersonProofDocumentUrl;

  // Step 2 — Manual Verification of second person
  final ManualVerificationDecision secondPersonDecision;

  // Step 3 — Suspension
  final SuspensionImpactSummary? suspensionImpact;
  final bool loadingSuspensionImpact;
  final bool suspending;

  // Step 4 — Original Holder Re-Verification
  final String? originalHolderCorrectedAadhaar;
  final String? originalHolderProofDocumentUrl;
  final ManualVerificationDecision originalHolderDecision;

  // Step 5 — Resolution
  final bool resolving;
  final MlidUpgradeResult? upgradeResult;
  final PersonIdHistoryEntry? idHistoryEntry;

  final String? error;

  const AadhaarDisputeCaseState({
    this.step = DisputeStep.caseIntake,
    this.searchMlidOrAadhaarInput = '',
    this.looking = false,
    this.existingAccount,
    this.secondPersonProofDocumentUrl,
    this.secondPersonDecision = ManualVerificationDecision.pending,
    this.suspensionImpact,
    this.loadingSuspensionImpact = false,
    this.suspending = false,
    this.originalHolderCorrectedAadhaar,
    this.originalHolderProofDocumentUrl,
    this.originalHolderDecision = ManualVerificationDecision.pending,
    this.resolving = false,
    this.upgradeResult,
    this.idHistoryEntry,
    this.error,
  });

  // Gate: Step 1 → Step 2 requires a looked-up account + uploaded proof.
  bool get canProceedFromIntake => existingAccount != null && secondPersonProofDocumentUrl != null;

  // Gate: Step 2 → Step 3 requires an explicit Verified decision.
  bool get canProceedFromSecondPersonVerification =>
      secondPersonDecision == ManualVerificationDecision.verified;

  // Gate: Step 4b → Step 5 requires an explicit Verified decision on the
  // original holder's re-submission.
  bool get canProceedToResolution => originalHolderDecision == ManualVerificationDecision.verified;

  AadhaarDisputeCaseState copyWith({
    DisputeStep? step,
    String? searchMlidOrAadhaarInput,
    bool? looking,
    DisputeCaseLookup? existingAccount,
    String? secondPersonProofDocumentUrl,
    ManualVerificationDecision? secondPersonDecision,
    SuspensionImpactSummary? suspensionImpact,
    bool? loadingSuspensionImpact,
    bool? suspending,
    String? originalHolderCorrectedAadhaar,
    String? originalHolderProofDocumentUrl,
    ManualVerificationDecision? originalHolderDecision,
    bool? resolving,
    MlidUpgradeResult? upgradeResult,
    PersonIdHistoryEntry? idHistoryEntry,
    String? error,
    bool clearError = false,
  }) {
    return AadhaarDisputeCaseState(
      step: step ?? this.step,
      searchMlidOrAadhaarInput: searchMlidOrAadhaarInput ?? this.searchMlidOrAadhaarInput,
      looking: looking ?? this.looking,
      existingAccount: existingAccount ?? this.existingAccount,
      secondPersonProofDocumentUrl: secondPersonProofDocumentUrl ?? this.secondPersonProofDocumentUrl,
      secondPersonDecision: secondPersonDecision ?? this.secondPersonDecision,
      suspensionImpact: suspensionImpact ?? this.suspensionImpact,
      loadingSuspensionImpact: loadingSuspensionImpact ?? this.loadingSuspensionImpact,
      suspending: suspending ?? this.suspending,
      originalHolderCorrectedAadhaar: originalHolderCorrectedAadhaar ?? this.originalHolderCorrectedAadhaar,
      originalHolderProofDocumentUrl: originalHolderProofDocumentUrl ?? this.originalHolderProofDocumentUrl,
      originalHolderDecision: originalHolderDecision ?? this.originalHolderDecision,
      resolving: resolving ?? this.resolving,
      upgradeResult: upgradeResult ?? this.upgradeResult,
      idHistoryEntry: idHistoryEntry ?? this.idHistoryEntry,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AadhaarDisputeCaseNotifier extends Notifier<AadhaarDisputeCaseState> {
  @override
  AadhaarDisputeCaseState build() => const AadhaarDisputeCaseState();

  void setSearchInput(String value) => state = state.copyWith(searchMlidOrAadhaarInput: value);

  // Step 1a — search by MLID or Aadhaar.
  Future<void> lookupExistingAccount() async {
    if (state.searchMlidOrAadhaarInput.trim().isEmpty) return;
    state = state.copyWith(looking: true, clearError: true);
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);
      final result = await api.lookupExistingAccount(
        mlid: state.searchMlidOrAadhaarInput,
        aadhaarNumber: state.searchMlidOrAadhaarInput,
      );
      state = state.copyWith(existingAccount: result, looking: false);
    } catch (e) {
      state = state.copyWith(looking: false, error: e.toString());
    }
  }

  // Step 1b — attach second person's submitted proof.
  Future<void> uploadSecondPersonProof(String documentUrl) async {
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);
      await api.uploadProofDocument(personLabel: 'second_person', documentUrl: documentUrl);
      state = state.copyWith(secondPersonProofDocumentUrl: documentUrl);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void goToSecondPersonVerification() {
    if (!state.canProceedFromIntake) return;
    state = state.copyWith(step: DisputeStep.secondPersonVerification);
  }

  // Step 2 — manual human decision, no auto-verification logic.
  void setSecondPersonDecision(ManualVerificationDecision decision) {
    state = state.copyWith(secondPersonDecision: decision);
  }

  // Step 2 → 3 — load the suspension-impact summary for operator review
  // before any suspension actually fires (explicit confirm required).
  Future<void> proceedToSuspensionSummary() async {
    if (!state.canProceedFromSecondPersonVerification) return;
    final personId = state.existingAccount?.personId;
    if (personId == null) return;
    state = state.copyWith(
      step: DisputeStep.suspensionConfirm,
      loadingSuspensionImpact: true,
      clearError: true,
    );
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);
      final impact = await api.fetchSuspensionImpact(personId: personId);
      state = state.copyWith(suspensionImpact: impact, loadingSuspensionImpact: false);
    } catch (e) {
      state = state.copyWith(loadingSuspensionImpact: false, error: e.toString());
    }
  }

  // Step 3 — explicit confirm: fires all suspensions, then advances to
  // Step 4 (original holder re-verification intake). Per-row loop over the
  // impact summary, branching business vs membership exactly as SP-001
  // FLOW 3a describes (whole business for Owner rows, membership-only for
  // everything else) — restored to match the original stub's structure and
  // the finalized per-row RPC signatures.
  Future<void> confirmSuspension() async {
    final impact = state.suspensionImpact;
    if (impact == null) return;
    state = state.copyWith(suspending: true, clearError: true);
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);
      for (final row in impact.rows) {
        if (row.isOwnerBusiness) {
          await api.suspendBusiness(businessId: row.id);
        } else {
          await api.suspendMembership(membershipId: row.id);
        }
      }
      state = state.copyWith(suspending: false, step: DisputeStep.originalHolderIntake);
    } catch (e) {
      state = state.copyWith(suspending: false, error: e.toString());
    }
  }

  // Step 4a — original holder's corrected Aadhaar + proof. Passes the
  // disputed account's own person_id through to uploadProofDocument (see
  // that method's FLAGGED signature-change note) — this is new internal
  // wiring, not a change to submitOriginalHolderResubmission's own public
  // signature, which is unchanged from the original stub.
  Future<void> submitOriginalHolderResubmission({
    required String correctedAadhaar,
    required String documentUrl,
  }) async {
    final personId = state.existingAccount?.personId;
    if (personId == null) return;
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);
      await api.uploadProofDocument(
        personLabel: 'original_holder',
        documentUrl: documentUrl,
        personId: personId,
      );
      state = state.copyWith(
        originalHolderCorrectedAadhaar: correctedAadhaar,
        originalHolderProofDocumentUrl: documentUrl,
        step: DisputeStep.originalHolderVerification,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Step 4b — manual human decision on the original holder's resubmission.
  void setOriginalHolderDecision(ManualVerificationDecision decision) {
    state = state.copyWith(originalHolderDecision: decision);
  }

  // Step 5 — single Support action: unblock + unsuspend + upgrade-mlid,
  // then read back the person_id_history entry. person_id itself never
  // changes, so no reattachment of loans/investments/memberships is
  // needed here — that's model-level, automatic. Per-row unsuspend loop,
  // mirroring confirmSuspension's structure exactly (same impact rows,
  // reverse direction).
  Future<void> resolveCase() async {
    if (!state.canProceedToResolution) return;
    final personId = state.existingAccount?.personId;
    final correctedAadhaar = state.originalHolderCorrectedAadhaar;
    final impact = state.suspensionImpact;
    if (personId == null || correctedAadhaar == null || impact == null) return;

    state = state.copyWith(resolving: true, clearError: true);
    try {
      final api = ref.read(aadhaarDisputeApiServiceProvider);

      for (final row in impact.rows) {
        if (row.isOwnerBusiness) {
          await api.unsuspendBusiness(businessId: row.id);
        } else {
          await api.unsuspendMembership(membershipId: row.id);
        }
      }

      final upgrade = await api.upgradeMlid(
        personId: personId,
        correctedAadhaar: correctedAadhaar,
        reason: 'Aadhaar Correction — Dispute Resolution',
      );

      final historyEntry = await api.fetchLatestIdHistoryEntry(personId: personId);

      state = state.copyWith(
        resolving: false,
        upgradeResult: upgrade,
        idHistoryEntry: historyEntry,
        step: DisputeStep.caseClosed,
      );
    } catch (e) {
      state = state.copyWith(resolving: false, error: e.toString());
    }
  }

  // Reset for a fresh case — no "undo"/"revert MLID" action exists per the
  // spec (old MLID retired permanently); this only clears local UI state
  // to start a new, unrelated case.
  void startNewCase() => state = const AadhaarDisputeCaseState();
}

final aadhaarDisputeCaseProvider =
    NotifierProvider<AadhaarDisputeCaseNotifier, AadhaarDisputeCaseState>(
  AadhaarDisputeCaseNotifier.new,
);

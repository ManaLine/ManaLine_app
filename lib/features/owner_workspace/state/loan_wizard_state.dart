import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_state.dart' show CustomerSummary;
import '../../../shared/live_photo_upload.dart';

/// OW-005 New Loan Workflow — real Supabase wiring. No dedicated
/// eligibility-check endpoint; validation is inline inside the create call,
/// returning a structured failure with reasons on hard-stop (per spec's own
/// API BINDING). Shared verbatim with AG-007 (Agent Loan Distribution) —
/// this file is imported directly by ag_007_loan_distribution.dart; method
/// signatures below are UNCHANGED from the stub.
///
/// See the same INTEGRATION FLAG / IDENTITY FLAG notes as
/// collection_mode_state.dart (Supabase.initialize timing, personId
/// String->BIGINT parsing) — not repeated verbatim here to avoid drift; see
/// that file's doc comment for the exact wording if needed for the
/// integration note.
class LoanApiService {
  final Ref ref;
  LoanApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// Calls `create_loan_with_bf_check`, a SECURITY DEFINER RPC (not yet
  /// deployed as of migration 0019 — grep of 0001-0019 confirms no
  /// CREATE FUNCTION besides the `app.*` RLS helpers, `app.discover_businesses`,
  /// and `app.get_investment_statement`). This single call needs to
  /// atomically:
  ///   1. Run BF Cash Validation (Merged Addendum item 4 — "BF floor at ₹0
  ///      — any transaction that would push BF below ₹0 is blocked" against
  ///      `agent_bf_assignments.agent_bf_current` for
  ///      `collectionAgentMembershipId`'s current session; on insufficient
  ///      BF, the loan auto-saves as a `collection_drafts` row
  ///      (draft_type='Loan Distribution') instead of failing outright —
  ///      per the addendum's own specified fallback behavior, not a plain
  ///      error).
  ///   2. Insert the `loans` row (amount_given is a GENERATED column, never
  ///      sent).
  ///   3. Materialize the full `loan_schedule` (durationValue installments,
  ///      per repaymentType cadence — schema §6.2/Open Item 1: "fully
  ///      materialized at loan creation, not lazy").
  ///   4. Insert a `guarantors` row if guarantor fields are present.
  ///   5. Deduct `amount_given` from the Agent's `agent_bf_current` for
  ///      this session.
  /// All five of the above must succeed or none must — exactly the
  /// multi-table financial write the briefing says must be a Postgres
  /// function/Edge Function, not sequential client-side `.insert()` calls.
  ///
  /// Return shape from the RPC is expected as either the created loan's
  /// `{loan_id, loan_number}` or a structured failure
  /// `{passed: false, failure_reason: '...'}` — e.g. "BF Cash Low — Add
  /// funds to continue" per the addendum's exact copy — so this client
  /// never re-derives that message itself; it only surfaces whatever the
  /// RPC returns.
  ///
  /// SCHEMA GAP (non-breaking fix applied): `loans.live_photo_url` and
  /// `loans.grace_period_days` are both NOT NULL (schema §6.1,
  /// BR-036/081/206), but neither `LoanWizardState` nor this method's
  /// original parameter list collected them anywhere in Steps 1-4. Added
  /// below as trailing OPTIONAL named params (`livePhotoUrl`,
  /// `gracePeriodDays`) rather than required ones, since this method's
  /// signature is shared verbatim with `ag_007_loan_distribution.dart`
  /// (outside this chat's file scope) — adding them as optional keeps
  /// that caller compiling unchanged. If the RPC is deployed with these
  /// columns still NOT NULL and a caller doesn't supply them, the RPC call
  /// fails server-side with a Postgres NOT NULL violation, surfaced here
  /// as `EligibilityResult.failureReason` — not silently defaulted to a
  /// placeholder photo URL. Whichever chat next touches the OW-005/AG-007
  /// screen UI should add the missing capture step and start passing
  /// these two.
  Future<EligibilityResult> checkEligibilityAndCreate({
    required String businessId,
    required String customerId,
    required double repaymentAmount,
    required double interest,
    required double processingFee,
    required String repaymentType,
    required int durationValue,
    required double installmentAmount,
    required String effectiveDate,
    required String collectionAgentMembershipId,
    String? guarantorName,
    String? guarantorRelationship,
    String? guarantorPhone,
    String? guarantorAddress,
    String? guarantorRemarks,
    String? livePhotoUrl,
    int? gracePeriodDays,
  }) async {
    try {
      final response = await _db.rpc('create_loan_with_bf_check', params: {
        'p_business_id': businessId,
        'p_customer_id': customerId,
        'p_repayment_amount': repaymentAmount,
        'p_interest_amount': interest,
        'p_processing_fee': processingFee,
        'p_repayment_type': repaymentType,
        'p_duration_value': durationValue,
        'p_installment_amount': installmentAmount,
        'p_effective_date': effectiveDate,
        'p_collection_agent_membership_id': collectionAgentMembershipId,
        'p_live_photo_url': livePhotoUrl,
        'p_grace_period_days': gracePeriodDays,
        'p_guarantor_name': guarantorName,
        'p_guarantor_relationship': guarantorRelationship,
        'p_guarantor_phone': guarantorPhone,
        'p_guarantor_address': guarantorAddress,
        'p_guarantor_remarks': guarantorRemarks,
      });

      final map = response as Map<String, dynamic>;
      if (map['passed'] == false) {
        return EligibilityResult(passed: false, failureReason: map['failure_reason'] as String?);
      }
      return EligibilityResult(
        passed: true,
        loanId: map['loan_id'] as String?,
        loanNumber: map['loan_number'] as String?,
      );
    } on PostgrestException catch (e) {
      // Covers both "function does not exist" (RPC not deployed yet) and
      // any server-side RAISE EXCEPTION (e.g. a NOT NULL violation from
      // the live_photo_url/grace_period_days gap above) — both surface as
      // a failed EligibilityResult rather than an uncaught throw, matching
      // Step 2's existing hard-stop UI pattern (S2 Eligibility Failed).
      return EligibilityResult(passed: false, failureReason: e.message);
    }
  }

  /// Guarantor insert — deliberately NOT part of create_loan_with_bf_check
  /// (guarantors.loan_id needs a real loan_id first). guarantors RLS (0014,
  /// guarantors_owner_all / guarantors_agent_all_assigned) permits a direct
  /// Owner/Agent insert once the loan row already exists with the right
  /// business_id/customer_id — confirmed against the real policy bodies,
  /// not assumed. Called from confirm() below, right after a successful
  /// checkEligibilityAndCreate.
  Future<void> insertGuarantor({
    required String loanId,
    required String name,
    required String relationship,
    required String phone,
    required String address,
    String? remarks,
  }) async {
    await _db.from('guarantors').insert({
      'loan_id': loanId,
      'guarantor_name': name,
      'relationship': relationship,
      'phone': phone,
      'address': address,
      'remarks': remarks,
    });
  }
}

class EligibilityResult {
  final bool passed;
  final String? failureReason;
  final String? loanId;
  final String? loanNumber;

  EligibilityResult({required this.passed, this.failureReason, this.loanId, this.loanNumber});
}

final loanApiServiceProvider = Provider<LoanApiService>((ref) {
  return LoanApiService(ref: ref);
});

enum LoanWizardStep { customerSelection, eligibility, loanDetails, guarantor, livePhoto, confirm }

class LoanWizardState {
  final LoanWizardStep step;
  final CustomerSummary? customer;
  final bool eligibilityPassed;
  final String? eligibilityFailureReason;

  // Step 3 — Loan Details
  final double? repaymentAmount;
  final double? interest;
  final double? processingFee;
  final String repaymentType; // e.g. Weekly | Monthly
  final int? durationValue;
  final double? installmentAmount;
  final String effectiveDate;
  final String? collectionAgentId;
  final String? collectionAgentName;

  // Step 4 — Guarantor (conditional)
  final bool needsGuarantor;
  final String? guarantorName;
  final String? guarantorRelationship;
  final String? guarantorPhone;
  final String? guarantorAddress;
  final String? guarantorRemarks;

  // Step 4.5 — Live Photo (BR-036/081, mandatory, camera-only, no gallery)
  // and Grace Period (loans.grace_period_days is NOT NULL — internal only,
  // never shown to customer, per BR-206 — but must be collected somewhere).
  final Uint8List? livePhotoBytes;
  final int gracePeriodDays;

  final bool submitting;
  final String? error;
  final String? createdLoanNumber;

  const LoanWizardState({
    this.step = LoanWizardStep.customerSelection,
    this.customer,
    this.eligibilityPassed = false,
    this.eligibilityFailureReason,
    this.repaymentAmount,
    this.interest,
    this.processingFee,
    this.repaymentType = 'Weekly',
    this.durationValue,
    this.installmentAmount,
    this.effectiveDate = '',
    this.collectionAgentId,
    this.collectionAgentName,
    this.needsGuarantor = false,
    this.guarantorName,
    this.guarantorRelationship,
    this.guarantorPhone,
    this.guarantorAddress,
    this.guarantorRemarks,
    this.livePhotoBytes,
    this.gracePeriodDays = 0, // TODO: pre-fill from loan_templates.default_grace_period_days once Step 3 offers template selection — currently always starts at 0, owner overrides per BR-007/381
    this.submitting = false,
    this.error,
    this.createdLoanNumber,
  });

  // Amount Given = Repayment Amount − Interest − Processing Fee — system
  // derived, never editable (BR-004 locked formula).
  double get amountGiven => (repaymentAmount ?? 0) - (interest ?? 0) - (processingFee ?? 0);

  bool get step3Complete =>
      repaymentAmount != null &&
      repaymentAmount! > 0 &&
      durationValue != null &&
      durationValue! > 0 &&
      installmentAmount != null &&
      installmentAmount! > 0 &&
      effectiveDate.isNotEmpty &&
      collectionAgentId != null;

  bool get step4Complete => !needsGuarantor || (guarantorName != null && guarantorName!.trim().isNotEmpty);

  bool get livePhotoStepComplete => livePhotoBytes != null;

  LoanWizardState copyWith({
    LoanWizardStep? step,
    CustomerSummary? customer,
    bool? eligibilityPassed,
    String? eligibilityFailureReason,
    bool clearEligibilityFailure = false,
    double? repaymentAmount,
    double? interest,
    double? processingFee,
    String? repaymentType,
    int? durationValue,
    double? installmentAmount,
    String? effectiveDate,
    String? collectionAgentId,
    String? collectionAgentName,
    bool? needsGuarantor,
    String? guarantorName,
    String? guarantorRelationship,
    String? guarantorPhone,
    String? guarantorAddress,
    String? guarantorRemarks,
    Uint8List? livePhotoBytes,
    int? gracePeriodDays,
    bool? submitting,
    String? error,
    bool clearError = false,
    String? createdLoanNumber,
  }) {
    return LoanWizardState(
      step: step ?? this.step,
      customer: customer ?? this.customer,
      eligibilityPassed: eligibilityPassed ?? this.eligibilityPassed,
      eligibilityFailureReason:
          clearEligibilityFailure ? null : (eligibilityFailureReason ?? this.eligibilityFailureReason),
      repaymentAmount: repaymentAmount ?? this.repaymentAmount,
      interest: interest ?? this.interest,
      processingFee: processingFee ?? this.processingFee,
      repaymentType: repaymentType ?? this.repaymentType,
      durationValue: durationValue ?? this.durationValue,
      installmentAmount: installmentAmount ?? this.installmentAmount,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      collectionAgentId: collectionAgentId ?? this.collectionAgentId,
      collectionAgentName: collectionAgentName ?? this.collectionAgentName,
      needsGuarantor: needsGuarantor ?? this.needsGuarantor,
      guarantorName: guarantorName ?? this.guarantorName,
      guarantorRelationship: guarantorRelationship ?? this.guarantorRelationship,
      guarantorPhone: guarantorPhone ?? this.guarantorPhone,
      guarantorAddress: guarantorAddress ?? this.guarantorAddress,
      guarantorRemarks: guarantorRemarks ?? this.guarantorRemarks,
      livePhotoBytes: livePhotoBytes ?? this.livePhotoBytes,
      gracePeriodDays: gracePeriodDays ?? this.gracePeriodDays,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      createdLoanNumber: createdLoanNumber ?? this.createdLoanNumber,
    );
  }
}

/// NO draft persistence in V1 for this wizard (per spec, distinct from
/// OW-000) — exiting mid-flow resets progress; a fresh Notifier instance
/// per entry (via reset()) mirrors that.
class LoanWizardNotifier extends Notifier<LoanWizardState> {
  @override
  LoanWizardState build() => const LoanWizardState();

  void reset() => state = const LoanWizardState();

  void selectCustomer(CustomerSummary customer) {
    state = state.copyWith(customer: customer, step: LoanWizardStep.eligibility);
  }

  /// Step 2 — system checks are simulated pass/fail here; a real build
  /// wires this to the create call's 422 response (no separate
  /// check-then-create round trip per spec's API BINDING — this stub
  /// keeps the two-phase UI shape for now since Step 3/4 need to collect
  /// data before that single call fires).
  void markEligibilityPassed() {
    state = state.copyWith(
      eligibilityPassed: true,
      clearEligibilityFailure: true,
      step: LoanWizardStep.loanDetails,
    );
  }

  void markEligibilityFailed(String reason) {
    state = state.copyWith(eligibilityPassed: false, eligibilityFailureReason: reason);
  }

  void setLoanDetails({
    required double repaymentAmount,
    required double interest,
    required double processingFee,
    required String repaymentType,
    required int durationValue,
    required double installmentAmount,
    required String effectiveDate,
    required String collectionAgentId,
    required String collectionAgentName,
  }) {
    state = state.copyWith(
      repaymentAmount: repaymentAmount,
      interest: interest,
      processingFee: processingFee,
      repaymentType: repaymentType,
      durationValue: durationValue,
      installmentAmount: installmentAmount,
      effectiveDate: effectiveDate,
      collectionAgentId: collectionAgentId,
      collectionAgentName: collectionAgentName,
      step: LoanWizardStep.guarantor,
    );
  }

  void setGuarantor({
    required bool needsGuarantor,
    String? name,
    String? relationship,
    String? phone,
    String? address,
    String? remarks,
  }) {
    state = state.copyWith(
      needsGuarantor: needsGuarantor,
      guarantorName: needsGuarantor ? name : null,
      guarantorRelationship: needsGuarantor ? relationship : null,
      guarantorPhone: needsGuarantor ? phone : null,
      guarantorAddress: needsGuarantor ? address : null,
      guarantorRemarks: needsGuarantor ? remarks : null,
      step: LoanWizardStep.livePhoto,
    );
  }

  /// Step 4.5 — Live Photo (BR-036/081). Camera-only capture is enforced by
  /// LiveFaceCaptureScreen itself (no gallery path exists anywhere in that
  /// widget) — this method just stores the resulting bytes and advances.
  void setLivePhoto(Uint8List bytes) {
    state = state.copyWith(step: LoanWizardStep.confirm, livePhotoBytes: bytes);
  }

  void setGracePeriodDays(int days) {
    state = state.copyWith(gracePeriodDays: days);
  }

  void goToStep(LoanWizardStep step) => state = state.copyWith(step: step, clearError: true);

  /// Step 5 — single Confirm action, no separate Owner-review gate.
  /// Now also uploads livePhotoBytes to Storage first (0023 bucket) —
  /// checkEligibilityAndCreate's p_live_photo_url expects a URL, not raw
  /// bytes, and loans.live_photo_url is NOT NULL, so confirm() hard-stops
  /// before calling the RPC at all if no photo was captured, rather than
  /// letting the RPC reject it as a NOT NULL violation after an upload
  /// that then has to be reasoned about as orphaned.
  Future<String?> confirm({required String businessId}) async {
    if (state.customer == null || !state.step3Complete) return null;
    if (!state.livePhotoStepComplete) {
      state = state.copyWith(error: 'Live photo is required before a loan can be created (BR-036/081).');
      return null;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final photoUrl = await LivePhotoUpload.upload(
        bytes: state.livePhotoBytes!,
        businessId: businessId,
        pathSegment: 'loans/${state.customer!.customerId}-${DateTime.now().millisecondsSinceEpoch}',
      );

      final api = ref.read(loanApiServiceProvider);
      final result = await api.checkEligibilityAndCreate(
        businessId: businessId,
        customerId: state.customer!.customerId,
        repaymentAmount: state.repaymentAmount!,
        interest: state.interest ?? 0,
        processingFee: state.processingFee ?? 0,
        repaymentType: state.repaymentType,
        durationValue: state.durationValue!,
        installmentAmount: state.installmentAmount!,
        effectiveDate: state.effectiveDate,
        collectionAgentMembershipId: state.collectionAgentId!,
        guarantorName: state.guarantorName,
        guarantorRelationship: state.guarantorRelationship,
        guarantorPhone: state.guarantorPhone,
        guarantorAddress: state.guarantorAddress,
        guarantorRemarks: state.guarantorRemarks,
        livePhotoUrl: photoUrl,
        gracePeriodDays: state.gracePeriodDays,
      );
      if (!result.passed) {
        state = state.copyWith(submitting: false, error: result.failureReason ?? 'Loan could not be created.');
        return null;
      }

      if (state.needsGuarantor && result.loanId != null) {
        try {
          await api.insertGuarantor(
            loanId: result.loanId!,
            name: state.guarantorName!,
            relationship: state.guarantorRelationship ?? '',
            phone: state.guarantorPhone ?? '',
            address: state.guarantorAddress ?? '',
            remarks: state.guarantorRemarks,
          );
        } catch (e) {
          // The loan itself was already created successfully at this point
          // — do not roll that back or hide it from the Owner/Agent over a
          // guarantor-insert failure. Surface it as a distinct warning so
          // it isn't silently lost, but still report loan creation as a
          // success (createdLoanNumber is still set below).
          state = state.copyWith(
            error: 'Loan ${result.loanNumber} was created, but the guarantor could not be saved: $e. '
                'Add the guarantor from Loan Details once the loan appears in the list.',
          );
        }
      }

      state = state.copyWith(submitting: false, createdLoanNumber: result.loanNumber);
      return result.loanNumber;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return null;
    }
  }
}

final loanWizardProvider = NotifierProvider<LoanWizardNotifier, LoanWizardState>(
  LoanWizardNotifier.new,
);

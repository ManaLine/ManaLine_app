import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../../shared/mana_time.dart';

/// CW-003 Request New Loan — real Supabase wiring over Module 2
/// (loan_templates) and Module 6 (loan_requests). Same shared,
/// business-scoped tables as Owner/Agent screens — no
/// `/customer/`-prefixed namespace, matching the original stub's own
/// note.
///
/// Loan requests NEVER auto-approve or auto-pay: `submitRequest` below
/// only ever inserts a `status='Pending'` row. Turning a request into an
/// actual loan is a separate, Owner/Agent-side action
/// (`POST /businesses/{id}/loans`, §7.1) that happens entirely outside
/// this file's scope — no status-transition logic is built here beyond
/// the initial insert, per this chat's brief.
class LoanRequestApiService {
  final Ref ref;
  LoanRequestApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  /// GET /businesses/{business_id}/loan-templates?status=Active
  /// (Part2.md §2.1) — Step 1 Template Selection. RLS
  /// `loan_templates_customer_select_active` already restricts this to
  /// `status='Active'` templates for a business the caller is an active
  /// Customer of — the explicit `.eq('status','Active')` filter below is
  /// not redundant with that RLS check, it's the same query-shape
  /// convention used throughout this app (e.g. customer_state.dart's
  /// explicit `.eq('customer_status', status)`): RLS is the security
  /// boundary, the filter is what makes the query correct/efficient.
  Future<List<LoanTemplateSummary>> fetchActiveTemplates({required String businessId}) async {
    final rows = await _db
        .from('loan_templates')
        .select('template_id, template_name, default_amount, duration_value, repayment_frequency')
        .eq('business_id', businessId)
        .eq('status', 'Active');

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return LoanTemplateSummary(
        templateId: r['template_id'] as String,
        templateName: r['template_name'] as String,
        defaultAmount: (r['default_amount'] as num).toDouble(),
        durationValue: r['duration_value'] as int,
        repaymentFrequency: r['repayment_frequency'] as String,
      );
    }).toList();
  }

  /// POST /businesses/{business_id}/loan-requests (Part3.md §7.6).
  ///
  /// SIGNATURE GAP (flagged, resolved without changing the signature):
  /// `loan_requests.customer_id` is `NOT NULL` and is exactly what
  /// `loan_requests_customer_insert_own`'s `WITH CHECK
  /// (app.is_own_customer_row(customer_id))` evaluates against — but this
  /// method's existing signature only takes `businessId`, not a
  /// `customerId`. The real API endpoint can derive the caller's
  /// customer_id server-side from the JWT; a direct Postgrest insert
  /// cannot. Resolved the same way as online_payment_state.dart's
  /// analogous gap: derive it internally, here via the current person's
  /// `customers` row for this business (same join shape customer_
  /// state.dart already uses: `customers.membership_id ->
  /// business_members(business_id, person_id)`), rather than adding a
  /// parameter or guessing a value.
  ///
  /// The 24h-cooldown-after-Rejected re-submission block (§7.6: "A
  /// repeat POST... before cooldown_until returns 409 CONFLICT") has no
  /// DB constraint backing it (no UNIQUE on customer_id+business_id
  /// exists in 0007_module6_loan_domain.sql) — it's application-layer,
  /// same as the equivalent membership_requests cooldown handled
  /// elsewhere in this app. Not re-implemented here since
  /// `applyCooldownIfActive` (below, unchanged) already gates entry to
  /// this flow before `submit()` is ever called — duplicating the check
  /// again at insert time would be redundant with that, not a gap.
  Future<LoanRequestResult> submitRequest({
    required String businessId,
    String? templateId,
    required double requestedAmount,
    String? purposeRemark,
    String? preferredFrequency,
  }) async {
    final personIdStr = ref.read(authFlowProvider).personId;
    if (personIdStr == null) {
      throw StateError('No logged-in person_id available — cannot submit a loan request.');
    }
    final personId = int.parse(personIdStr);

    final customerRow = await _db
        .from('customers')
        .select('customer_id, business_members!customers_membership_id_fkey!inner(business_id, person_id, membership_status)')
        .eq('business_members.business_id', businessId)
        .eq('business_members.person_id', personId)
        .eq('business_members.membership_status', 'Active')
        .single();
    final customerId = customerRow['customer_id'] as String;

    final row = await _db
        .from('loan_requests')
        .insert({
          'customer_id': customerId,
          'template_id': templateId,
          'requested_amount': requestedAmount,
          'purpose_remark': purposeRemark,
          'preferred_frequency': preferredFrequency,
          'status': 'Pending',
        })
        .select('request_id, status, requested_amount, purpose_remark, preferred_frequency, '
            'resulting_loan_id, rejection_reason, cooldown_until, created_at')
        .single();

    return _resultFromRow(row);
  }

  /// GET /customers/{customer_id}/loan-requests — used to recover
  /// Pending/Approved/Rejected state (e.g. cooldown_until) if the
  /// Customer re-enters CW-003 mid-flow. RLS
  /// `loan_requests_customer_select_own` already scopes this to the
  /// caller's own requests.
  Future<List<LoanRequestResult>> fetchOwnRequests({required String customerId}) async {
    final rows = await _db
        .from('loan_requests')
        .select('request_id, status, requested_amount, purpose_remark, preferred_frequency, '
            'resulting_loan_id, rejection_reason, cooldown_until, created_at')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map(_resultFromRow).toList();
  }

  LoanRequestResult _resultFromRow(Map<String, dynamic> row) {
    return LoanRequestResult(
      requestId: row['request_id'] as String,
      status: row['status'] as String,
      requestedAmount: (row['requested_amount'] as num).toDouble(),
      purposeRemark: row['purpose_remark'] as String?,
      preferredFrequency: row['preferred_frequency'] as String?,
      resultingLoanId: row['resulting_loan_id'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
      cooldownUntil: row['cooldown_until'] != null ? DateTime.parse(row['cooldown_until'] as String) : null,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

final loanRequestApiServiceProvider = Provider<LoanRequestApiService>((ref) {
  return LoanRequestApiService(ref: ref);
});

// ============================================================================
// Models
// ============================================================================

/// Read-only projection of `loan_templates`, per OW-013 Templates /
/// §2.1 — only the fields CW-003 STEP 1 actually displays (Name,
/// Default Amount, Duration, Repayment Frequency).
class LoanTemplateSummary {
  final String templateId;
  final String templateName;
  final double defaultAmount;
  final int durationValue;
  final String repaymentFrequency; // Daily | Weekly | Monthly

  LoanTemplateSummary({
    required this.templateId,
    required this.templateName,
    required this.defaultAmount,
    required this.durationValue,
    required this.repaymentFrequency,
  });
}

/// `loan_requests` row (§6.5) — a Loan Request, never a loan. Becomes a
/// loan only via the existing OW-005 New Loan Workflow on Approve, at
/// which point resultingLoanId is set.
class LoanRequestResult {
  final String requestId;
  final String status; // Pending | Approved | Rejected
  final double requestedAmount;
  final String? purposeRemark;
  final String? preferredFrequency;
  final String? resultingLoanId;
  final String? rejectionReason;
  final DateTime? cooldownUntil; // set only on Rejected — 24h reapply gate
  final DateTime createdAt;

  LoanRequestResult({
    required this.requestId,
    required this.status,
    required this.requestedAmount,
    this.purposeRemark,
    this.preferredFrequency,
    this.resultingLoanId,
    this.rejectionReason,
    this.cooldownUntil,
    required this.createdAt,
  });
}

// ============================================================================
// State
// ============================================================================

enum LoanRequestPhase {
  gateCheck, // loading businesses.customer_loan_requests_allowed
  notAllowed, // gate is false — Request New Loan not offered by this Business
  cooldown, // a prior Rejected request's 24h cooldown is still active
  templateSelection, // S1 — only shown if Business offers templates
  requestDetails, // S2
  submitting,
  pendingReview, // S3
  approved, // S4
  rejected, // S5
}

class LoanRequestState {
  final LoanRequestPhase phase;
  final bool loading;
  final String? error;

  // Gate + Step 1 inputs, resolved before requestDetails is reachable.
  final bool customerLoanRequestsAllowed;
  final bool businessOffersTemplates;
  final bool businessAllowsCustomAmount;
  final List<LoanTemplateSummary> templates;
  final LoanTemplateSummary? selectedTemplate;
  final bool requestingCustomAmount;

  // Step 2 inputs
  final String requestedAmountText;
  final String purposeRemark;
  final String preferredFrequency; // only editable when requestingCustomAmount

  final LoanRequestResult? lastResult;

  const LoanRequestState({
    this.phase = LoanRequestPhase.gateCheck,
    this.loading = false,
    this.error,
    this.customerLoanRequestsAllowed = false,
    this.businessOffersTemplates = false,
    this.businessAllowsCustomAmount = false,
    this.templates = const [],
    this.selectedTemplate,
    this.requestingCustomAmount = false,
    this.requestedAmountText = '',
    this.purposeRemark = '',
    this.preferredFrequency = 'Weekly',
    this.lastResult,
  });

  bool get canSubmit {
    final amount = double.tryParse(requestedAmountText);
    return amount != null && amount > 0;
  }

  LoanRequestState copyWith({
    LoanRequestPhase? phase,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? customerLoanRequestsAllowed,
    bool? businessOffersTemplates,
    bool? businessAllowsCustomAmount,
    List<LoanTemplateSummary>? templates,
    LoanTemplateSummary? selectedTemplate,
    bool clearSelectedTemplate = false,
    bool? requestingCustomAmount,
    String? requestedAmountText,
    String? purposeRemark,
    String? preferredFrequency,
    LoanRequestResult? lastResult,
  }) {
    return LoanRequestState(
      phase: phase ?? this.phase,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      customerLoanRequestsAllowed: customerLoanRequestsAllowed ?? this.customerLoanRequestsAllowed,
      businessOffersTemplates: businessOffersTemplates ?? this.businessOffersTemplates,
      businessAllowsCustomAmount: businessAllowsCustomAmount ?? this.businessAllowsCustomAmount,
      templates: templates ?? this.templates,
      selectedTemplate: clearSelectedTemplate ? null : (selectedTemplate ?? this.selectedTemplate),
      requestingCustomAmount: requestingCustomAmount ?? this.requestingCustomAmount,
      requestedAmountText: requestedAmountText ?? this.requestedAmountText,
      purposeRemark: purposeRemark ?? this.purposeRemark,
      preferredFrequency: preferredFrequency ?? this.preferredFrequency,
      lastResult: lastResult ?? this.lastResult,
    );
  }
}

class LoanRequestNotifier extends Notifier<LoanRequestState> {
  @override
  LoanRequestState build() => const LoanRequestState();

  /// S1 entry — checks businesses.customer_loan_requests_allowed and,
  /// if true, whether the Business offers templates (drives whether
  /// Step 1 is shown at all, per CW-003's own conditional-Step-1 rule).
  /// SPEC GAP: no dedicated "get business loan-request settings"
  /// endpoint is named in CW-003's own API BINDING; this stub assumes
  /// that gate/flags payload rides along with fetchActiveTemplates in
  /// the real wiring (an empty-templates response still needs to
  /// distinguish "gate closed" from "gate open, zero templates, custom
  /// allowed") — flagged for master chat / API spec clarification
  /// rather than inventing a new endpoint here.
  Future<void> loadGateAndTemplates({
    required String businessId,
    required bool customerLoanRequestsAllowed,
    required bool businessAllowsCustomAmount,
  }) async {
    state = state.copyWith(loading: true, clearError: true, phase: LoanRequestPhase.gateCheck);

    if (!customerLoanRequestsAllowed) {
      state = state.copyWith(
        loading: false,
        customerLoanRequestsAllowed: false,
        phase: LoanRequestPhase.notAllowed,
      );
      return;
    }

    try {
      final api = ref.read(loanRequestApiServiceProvider);
      final templates = await api.fetchActiveTemplates(businessId: businessId);
      final offersTemplates = templates.isNotEmpty;
      state = state.copyWith(
        loading: false,
        customerLoanRequestsAllowed: true,
        businessAllowsCustomAmount: businessAllowsCustomAmount,
        businessOffersTemplates: offersTemplates,
        templates: templates,
        // Step 1 only shown if templates exist — otherwise go straight
        // to Step 2 with Request Custom Amount (per CW-003 STEP 1).
        phase: offersTemplates ? LoanRequestPhase.templateSelection : LoanRequestPhase.requestDetails,
        requestingCustomAmount: !offersTemplates,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Re-entry check — if the Customer's most recent request to this
  /// Business was Rejected and cooldown_until hasn't passed, block
  /// re-entry into the flow entirely (S5 cooldown gate) rather than
  /// letting them fill Step 1/2 and hit a 409 on submit.
  void applyCooldownIfActive(LoanRequestResult? mostRecent) {
    if (mostRecent != null &&
        mostRecent.status == 'Rejected' &&
        mostRecent.cooldownUntil != null &&
        mostRecent.cooldownUntil!.isAfter(manaNowIst())) {
      state = state.copyWith(phase: LoanRequestPhase.cooldown, lastResult: mostRecent);
    }
  }

  void selectTemplate(LoanTemplateSummary template) {
    state = state.copyWith(
      selectedTemplate: template,
      requestingCustomAmount: false,
      requestedAmountText: template.defaultAmount.toStringAsFixed(0),
      preferredFrequency: template.repaymentFrequency,
      phase: LoanRequestPhase.requestDetails,
    );
  }

  void selectCustomAmount() {
    state = state.copyWith(
      clearSelectedTemplate: true,
      requestingCustomAmount: true,
      phase: LoanRequestPhase.requestDetails,
    );
  }

  void setRequestedAmount(String v) => state = state.copyWith(requestedAmountText: v);
  void setPurposeRemark(String v) => state = state.copyWith(purposeRemark: v);
  void setPreferredFrequency(String v) => state = state.copyWith(preferredFrequency: v);

  void backToTemplateSelection() {
    if (state.businessOffersTemplates) {
      state = state.copyWith(phase: LoanRequestPhase.templateSelection);
    }
  }

  Future<bool> submit({required String businessId}) async {
    if (!state.canSubmit) return false;
    state = state.copyWith(loading: true, clearError: true, phase: LoanRequestPhase.submitting);
    try {
      final api = ref.read(loanRequestApiServiceProvider);
      final result = await api.submitRequest(
        businessId: businessId,
        templateId: state.selectedTemplate?.templateId,
        requestedAmount: double.parse(state.requestedAmountText),
        purposeRemark: state.purposeRemark.trim().isEmpty ? null : state.purposeRemark.trim(),
        preferredFrequency: state.requestingCustomAmount ? state.preferredFrequency : null,
      );
      final phase = switch (result.status) {
        'Approved' => LoanRequestPhase.approved,
        'Rejected' => LoanRequestPhase.rejected,
        _ => LoanRequestPhase.pendingReview,
      };
      state = state.copyWith(loading: false, lastResult: result, phase: phase);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString(), phase: LoanRequestPhase.requestDetails);
      return false;
    }
  }

  void reset() => state = const LoanRequestState();
}

final loanRequestProvider = NotifierProvider<LoanRequestNotifier, LoanRequestState>(
  LoanRequestNotifier.new,
);

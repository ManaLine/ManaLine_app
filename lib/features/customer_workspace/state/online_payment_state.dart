import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_loans_state.dart' show CustomerLoanSummary;

/// CW-005 Make A Payment — real Supabase wiring over
/// `customer_online_payments` (§7.5).
///
/// Online payments never auto-post: submitting only creates a
/// `customer_online_payments` row at status Submitted — the actual
/// `collections` record (payment_mode=UPI, per BR-023/BR-025 split
/// rule) and Outstanding Balance update only happen once Owner/Agent
/// manually confirms (§8.4 Part3, `PATCH /online-payments/{id}` —
/// entirely out of this screen's scope, Owner/Agent-side).
///
/// FINANCIAL-INTEGRITY NOTE (this is NOT an RPC-blocked operation,
/// confirmed against the schema, not assumed): unlike the Owner/Agent
/// settlement/BF-cash operations, `submitPayment` below touches exactly
/// ONE table. The schema and API spec are both explicit that this call
/// "does NOT touch remaining_balance or any cash pool at this point"
/// (§8.4 Part3) — there is no second table to keep atomically in sync
/// with the insert, so a single Postgrest INSERT is the correct
/// implementation, not a risky multi-step sequence needing an RPC. If a
/// future change makes submission also need to touch `loans` or
/// `collections` directly (bypassing Owner/Agent confirmation), that
/// would need to be re-flagged as BLOCKED on an RPC at that time — it
/// isn't today.
class OnlinePaymentApiService {
  SupabaseClient get _db => Supabase.instance.client;

  /// POST /loans/{loan_id}/online-payments — Body: { amount }. Caller =
  /// Customer, loan_id mandatory (matches this screen's own "No Pay Any
  /// Loan Free Entry" rule).
  ///
  /// SIGNATURE GAP (flagged, resolved without changing the signature):
  /// `customer_online_payments.customer_id` is `NOT NULL` and is exactly
  /// what `customer_online_payments_customer_insert_own`'s `WITH CHECK
  /// (app.is_own_customer_row(customer_id))` evaluates — but this
  /// method's signature only takes `loanId`/`amount`. Resolved the same
  /// way as loan_request_state.dart's analogous gap: derive customer_id
  /// internally rather than add a parameter. Here the derivation is
  /// simpler — `loans.customer_id` already IS the value we need, and the
  /// Customer can only read their own loan in the first place
  /// (`loans_customer_select_own`), so a lookup on `loans` by
  /// `loan_id` is both sufficient and safe (it can't leak another
  /// customer's loan, since RLS returns zero rows for a loan_id the
  /// caller doesn't own — which surfaces here as a clean "not found"
  /// error rather than silently succeeding against the wrong row).
  Future<OnlinePaymentRecord> submitPayment({
    required String loanId,
    required double amount,
  }) async {
    final loan = await _db.from('loans').select('customer_id').eq('loan_id', loanId).single();
    final customerId = loan['customer_id'] as String;

    final row = await _db
        .from('customer_online_payments')
        .insert({
          'loan_id': loanId,
          'customer_id': customerId,
          'amount': amount,
          'status': 'Submitted',
        })
        .select('online_payment_id, loan_id, amount, status, confirmed_by_person_id, '
            'resulting_collection_id, submitted_at, confirmed_at')
        .single();

    return _fromRow(row);
  }

  /// GET /loans/{loan_id}/online-payments?status= — used to refetch and
  /// reflect the latest status (Submitted/Confirmed/Not
  /// Received-Disputed) for payments made toward this loan, since
  /// Owner/Agent confirmation happens entirely out of this screen. RLS
  /// (`customer_online_payments_customer_select_own`) already scopes
  /// this to the caller's own rows.
  Future<List<OnlinePaymentRecord>> fetchPaymentsForLoan({required String loanId}) async {
    final rows = await _db
        .from('customer_online_payments')
        .select('online_payment_id, loan_id, amount, status, confirmed_by_person_id, '
            'resulting_collection_id, submitted_at, confirmed_at')
        .eq('loan_id', loanId)
        .order('submitted_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map(_fromRow).toList();
  }

  /// GET /customers/{customer_id}/online-payments?status= — cross-loan
  /// list, named in CW-005's own API BINDING; not rendered by this
  /// screen (which is always loan-scoped) but exposed here in case
  /// CW-001's My Summary (owned elsewhere) wants a Pending Online
  /// Payments count sourced the same way. `customer_online_payments` has
  /// its own direct `customer_id` column (0008_module7_collection_
  /// domain.sql), so no join is needed here.
  Future<List<OnlinePaymentRecord>> fetchPaymentsForCustomer({required String customerId}) async {
    final rows = await _db
        .from('customer_online_payments')
        .select('online_payment_id, loan_id, amount, status, confirmed_by_person_id, '
            'resulting_collection_id, submitted_at, confirmed_at')
        .eq('customer_id', customerId)
        .order('submitted_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map(_fromRow).toList();
  }

  OnlinePaymentRecord _fromRow(Map<String, dynamic> row) {
    return OnlinePaymentRecord(
      onlinePaymentId: row['online_payment_id'] as String,
      loanId: row['loan_id'] as String,
      // MONEY PRECISION NOTE: customer_online_payments.amount is
      // DECIMAL(14,0) — whole rupees only, per Merged Addendum item 1.
      // Same safe-double reasoning as customer_loans_state.dart's header
      // note (14-digit whole numbers are exact in double). Flagging
      // again here since this is the one file in this batch that
      // actually writes a money value, not just reads one.
      amount: (row['amount'] as num).toDouble(),
      status: row['status'] as String,
      confirmedByPersonId: row['confirmed_by_person_id']?.toString(),
      resultingCollectionId: row['resulting_collection_id'] as String?,
      submittedAt: DateTime.parse(row['submitted_at'] as String),
      confirmedAt: row['confirmed_at'] != null ? DateTime.parse(row['confirmed_at'] as String) : null,
    );
  }
}

final onlinePaymentApiServiceProvider = Provider<OnlinePaymentApiService>((ref) {
  return OnlinePaymentApiService();
});

// ============================================================================
// Models
// ============================================================================

/// `customer_online_payments` row (§7.5). status drives S3/S4/S5.
class OnlinePaymentRecord {
  final String onlinePaymentId;
  final String loanId;
  final double amount;
  final String status; // Submitted | Confirmed | Not Received-Disputed
  final String? confirmedByPersonId;
  final String? resultingCollectionId; // set on Confirmed
  final DateTime submittedAt;
  final DateTime? confirmedAt;

  OnlinePaymentRecord({
    required this.onlinePaymentId,
    required this.loanId,
    required this.amount,
    required this.status,
    this.confirmedByPersonId,
    this.resultingCollectionId,
    required this.submittedAt,
    this.confirmedAt,
  });
}

// ============================================================================
// State
// ============================================================================

enum PaymentFlowPhase {
  entry, // S1 — loan locked in, amount being entered
  upiInProgress, // S2 — handed off to device's UPI app
  submitted, // S3
  confirmed, // S4 — reflected via refetch only, never built here
  disputed, // S5
}

class OnlinePaymentState {
  final PaymentFlowPhase phase;
  final bool submitting;
  final String? error;
  final OnlinePaymentRecord? lastSubmission;

  const OnlinePaymentState({
    this.phase = PaymentFlowPhase.entry,
    this.submitting = false,
    this.error,
    this.lastSubmission,
  });

  OnlinePaymentState copyWith({
    PaymentFlowPhase? phase,
    bool? submitting,
    String? error,
    bool clearError = false,
    OnlinePaymentRecord? lastSubmission,
  }) {
    return OnlinePaymentState(
      phase: phase ?? this.phase,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      lastSubmission: lastSubmission ?? this.lastSubmission,
    );
  }
}

class OnlinePaymentNotifier extends Notifier<OnlinePaymentState> {
  @override
  OnlinePaymentState build() => const OnlinePaymentState();

  /// S1 → S2, purely local UI transition — this screen hands off to
  /// the device's UPI app, it does not itself talk to any UPI SDK
  /// (out of scope/no endpoint for that here).
  void beginUpiHandoff() => state = state.copyWith(phase: PaymentFlowPhase.upiInProgress, clearError: true);

  void returnFromUpiApp() => state = state.copyWith(phase: PaymentFlowPhase.entry);

  Future<bool> submit({required String loanId, required double amount}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(onlinePaymentApiServiceProvider);
      final record = await api.submitPayment(loanId: loanId, amount: amount);
      final phase = switch (record.status) {
        'Confirmed' => PaymentFlowPhase.confirmed,
        'Not Received-Disputed' => PaymentFlowPhase.disputed,
        _ => PaymentFlowPhase.submitted,
      };
      state = state.copyWith(submitting: false, lastSubmission: record, phase: phase);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// Refetch-only status reflection — no Customer-side retry/resubmit
  /// action exists for a Disputed payment per CW-005's own rule; this
  /// just re-reads the current status so a Confirmed/Disputed
  /// transition (driven entirely by Owner/Agent, out of scope here)
  /// shows up if the Customer re-opens this screen or pulls to refresh.
  Future<void> refreshStatus({required String loanId}) async {
    final current = state.lastSubmission;
    if (current == null) return;
    try {
      final api = ref.read(onlinePaymentApiServiceProvider);
      final all = await api.fetchPaymentsForLoan(loanId: loanId);
      final match = all.where((p) => p.onlinePaymentId == current.onlinePaymentId);
      if (match.isEmpty) return;
      final updated = match.first;
      final phase = switch (updated.status) {
        'Confirmed' => PaymentFlowPhase.confirmed,
        'Not Received-Disputed' => PaymentFlowPhase.disputed,
        _ => PaymentFlowPhase.submitted,
      };
      state = state.copyWith(lastSubmission: updated, phase: phase);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void reset() => state = const OnlinePaymentState();
}

final onlinePaymentProvider = NotifierProvider<OnlinePaymentNotifier, OnlinePaymentState>(
  OnlinePaymentNotifier.new,
);

/// Re-exported so cw_005 can accept a loan snapshot handed off from
/// CW-004 without importing customer_loans_state.dart directly in two
/// places — matches this chat's CustomerLoanSummary consumption (it
/// already carries outstandingBalance, so no divergent local type is
/// needed here, unlike IW-004/InvestmentSummary's situation).
typedef SelectedLoanSummary = CustomerLoanSummary;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CW-004 My Loans — real Supabase wiring over Module 6/7
/// (loans/loan_schedule/loan_templates/penalty_entries/
/// customer_online_payments/collections). RLS
/// (`loans_customer_select_own`, `loan_schedule_customer_select_own`,
/// `penalty_entries_customer_select_own`,
/// `customer_online_payments_customer_select_own`,
/// `collections_customer_select_own` — see rls_role_matrix.md) already
/// scopes every query below to the logged-in person's own loans via
/// `app.is_own_customer_row(customer_id)`. No redundant person_id filter
/// added anywhere, matching agent_notifications_state.dart's established
/// reasoning.
///
/// MONEY PRECISION NOTE (M8): every amount column touched here
/// (`repayment_amount`, `remaining_balance`, `installment_amount`,
/// `penalty_amount_applied`, `collected_amount`) is `DECIMAL(14,0)` —
/// whole rupees, no fractional part, per Merged Addendum item 1. Postgrest
/// serializes NUMERIC as a bare JSON number (not a string) at this scale.
/// Money is therefore modelled as `int` (whole rupees), never `double`, so
/// no float artifact can ever surface in a displayed balance or a payment
/// amount. Reads use `.toInt()` (whole values — no truncation risk).
class CustomerLoansApiService {
  SupabaseClient get _db => Supabase.instance.client;

  /// GET /customers/{customer_id}/loans (all loans, any status — the
  /// Closed-loans-hidden filter and active-first/earliest-due sort are
  /// applied client-side in `CustomerLoansState.visibleSorted`, per this
  /// screen's own locked rules, exactly as the original stub's comment
  /// specified).
  ///
  /// `nextDueDate`/`nextDueAmount` aren't stored columns — derived here
  /// from the loan's own `loan_schedule` rows (earliest `status='Pending'`
  /// entry by `due_date`), same derivation approach as
  /// customer_state.dart's `todaysDue`/`outstanding` aggregation over
  /// `loans` (that file sums flat `installment_amount` across
  /// Active/Grace/Penalty loans for a *list* of customers; this is the
  /// single-loan-schedule equivalent for one customer's own loan list).
  Future<List<CustomerLoanSummary>> fetchLoans({required String customerId, required String businessId}) async {
    final rows = await _db
        .from('loans')
        .select('''
          loan_id, loan_number, repayment_amount, remaining_balance, loan_status, template_id,
          loan_templates(template_name),
          loan_schedule(due_date, installment_amount, status)
        ''')
        .eq('customer_id', customerId)
        .eq('business_id', businessId);

    return (rows as List).map((r) => _summaryFromRow(r as Map<String, dynamic>)).toList();
  }

  /// GET /loans/{loan_id} — Agreement Summary + core loan fields, plus
  /// full schedule, pending online payments, and outstanding penalty —
  /// all fetched in one nested-select round trip (mirrors CW-004's own
  /// "fewer round trips on poor connections" reasoning already used
  /// elsewhere in this app, e.g. §6.6/§8.1 statement endpoints).
  ///
  /// SCHEMA/BR GAP (flagged, not populated): `CustomerLoanDetail.
  /// gracePeriodEndDate` is left `null` here on purpose.
  /// `loans.grace_period_days` is explicitly commented in the schema as
  /// "internal only, never shown to customer (BR-206)", and the later
  /// `loans.grace_override_until` addendum column carries the same
  /// internal-only intent (it exists to let the *server* compute
  /// eligibility, not to be surfaced on a Customer screen). This method
  /// does not even select either column, so there's no risk of an
  /// accidental future leak via this row shape — CW-004 should keep
  /// showing "Due Date" / "Overdue" derived from `loan_schedule` only,
  /// never a grace boundary. Flagged for master chat if CW-004's actual
  /// design calls for a boolean "in grace" indicator instead of the raw
  /// date — that would need a new, explicitly-customer-safe field, not
  /// this one.
  Future<CustomerLoanDetail> fetchLoanDetail({required String loanId}) async {
    final row = await _db
        .from('loans')
        .select('''
          loan_id, loan_number, repayment_amount, remaining_balance, loan_status, template_id,
          repayment_type, duration_value, installment_amount, effective_date,
          loan_templates(template_name),
          business_members!loans_collection_agent_membership_id_fkey(persons!business_members_person_id_fkey(full_name)),
          loan_schedule(installment_number, due_date, installment_amount, status),
          customer_online_payments(online_payment_id, amount, submitted_at, status),
          penalty_entries(penalty_amount_applied, is_waived_or_reduced)
        ''')
        .eq('loan_id', loanId)
        .single();

    final summary = _summaryFromRow(row);

    final schedule = ((row['loan_schedule'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((s) => LoanScheduleEntry(
              installmentNumber: s['installment_number'] as int,
              dueDate: DateTime.parse(s['due_date'] as String),
              installmentAmount: (s['installment_amount'] as num).toInt(),
              status: s['status'] as String,
            ))
        .toList()
      ..sort((a, b) => a.installmentNumber.compareTo(b.installmentNumber));

    final pendingOnline = ((row['customer_online_payments'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((p) => p['status'] == 'Submitted')
        .map((p) => PendingOnlinePayment(
              onlinePaymentId: p['online_payment_id'] as String,
              amount: (p['amount'] as num).toInt(),
              submittedAt: DateTime.parse(p['submitted_at'] as String),
            ))
        .toList();

    // Outstanding (unwaived) penalty total. `penalty_entries` has no
    // `waived_amount` column in the locked schema — only the boolean
    // `is_waived_or_reduced` (the API spec's own PATCH body mentions a
    // `waived_amount` field, but it isn't a real column here; see
    // 0007_module6_loan_domain.sql §6.7). SCHEMA/API-SPEC GAP flagged:
    // a *partially* waived penalty therefore can't be distinguished from
    // a fully-waived one at this layer — this sums every entry that is
    // NOT flagged waived at all, which slightly overstates outstanding
    // penalty in the (currently unsupported) partial-waiver case. Not
    // silently working around it — flagged for master chat: either add
    // `penalty_entries.waived_amount` or confirm waivers are always
    // full-amount in V1.
    final penaltyEntries = ((row['penalty_entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final unwaived = penaltyEntries.where((p) => p['is_waived_or_reduced'] != true);
    final penaltyTotal = unwaived.fold<int>(0, (sum, p) => sum + (p['penalty_amount_applied'] as num).toInt());

    // "Loan Given by" — the agent who carries this loan. The embed has to name
    // its FK: business_members is reachable from loans by more than one path,
    // and an unnamed embed is a PGRST201 error, not a null.
    final agentMember = row['business_members'] as Map<String, dynamic>?;
    final agentPerson = agentMember?['persons'] as Map<String, dynamic>?;

    return CustomerLoanDetail(
      summary: summary,
      loanGivenBy: (agentPerson?['full_name'] as String?)?.trim(),
      repaymentType: row['repayment_type'] as String,
      durationValue: row['duration_value'] as int,
      installmentAmount: (row['installment_amount'] as num).toInt(),
      effectiveDate: DateTime.parse(row['effective_date'] as String),
      schedule: schedule,
      pendingOnlinePayments: pendingOnline,
      penaltyAmount: unwaived.isEmpty ? null : penaltyTotal,
      gracePeriodEndDate: null, // see method doc above — BR-206, never shown to customer
    );
  }

  /// GET /loans/{loan_id}/statement — Payment History. `collections`
  /// already covers both Cash and confirmed-Online payments (a confirmed
  /// online payment becomes a `collections` row with
  /// `payment_mode='UPI'` via `collection_payment_splits`, per §8.4 Part3
  /// — there is no separate online-only history source to merge in
  /// here). A collection can be split across multiple payment modes
  /// (BR-023/025); this maps to a single `paymentMode` string per the
  /// existing `LoanPaymentHistoryEntry` shape by reporting the actual
  /// mode when there's exactly one split, or `'Mixed'` when there's more
  /// than one — this is a display simplification of the split detail,
  /// not a data loss (the full splits aren't needed by this row shape).
  Future<List<LoanPaymentHistoryEntry>> fetchStatement({required String loanId}) async {
    final rows = await _db
        .from('collections')
        .select('collection_id, business_date, collected_amount, receipt_number, '
            'collection_payment_splits(payment_mode)')
        .eq('loan_id', loanId)
        .order('business_date', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final splits = ((r['collection_payment_splits'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final mode = splits.isEmpty
          ? 'Cash' // defensive fallback; every collection should have >=1 split per schema invariant
          : (splits.length == 1 ? splits.first['payment_mode'] as String : 'Mixed');
      return LoanPaymentHistoryEntry(
        collectionId: r['collection_id'] as String,
        businessDate: DateTime.parse(r['business_date'] as String),
        collectedAmount: (r['collected_amount'] as num).toInt(),
        paymentMode: mode,
        receiptNumber: r['receipt_number'] as String,
      );
    }).toList();
  }

  CustomerLoanSummary _summaryFromRow(Map<String, dynamic> row) {
    final template = row['loan_templates'] as Map<String, dynamic>?;
    final scheduleRows = ((row['loan_schedule'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final pending = scheduleRows.where((s) => s['status'] == 'Pending').toList()
      ..sort((a, b) => (a['due_date'] as String).compareTo(b['due_date'] as String));
    final nextPending = pending.isEmpty ? null : pending.first;

    return CustomerLoanSummary(
      loanId: row['loan_id'] as String,
      loanNumber: row['loan_number'] as String,
      templateName: template?['template_name'] as String?,
      principalAmount: (row['repayment_amount'] as num).toInt(),
      outstandingBalance: (row['remaining_balance'] as num).toInt(),
      nextDueDate: nextPending != null ? DateTime.parse(nextPending['due_date'] as String) : null,
      nextDueAmount: nextPending != null ? (nextPending['installment_amount'] as num).toInt() : null,
      loanStatus: row['loan_status'] as String,
    );
  }
}

final customerLoansApiServiceProvider = Provider<CustomerLoansApiService>((ref) {
  return CustomerLoansApiService();
});

// ============================================================================
// Models
// ============================================================================

/// LOAN LIST row per CW-004: Loan ID, Loan Template/Type, Principal
/// Amount, Outstanding Balance, Next Due Date, Next Due Amount, Status.
class CustomerLoanSummary {
  final String loanId;
  final String loanNumber;
  final String? templateName;
  final int principalAmount; // repayment_amount, per §6.1
  final int outstandingBalance; // remaining_balance
  final DateTime? nextDueDate;
  final int? nextDueAmount;
  final String loanStatus; // Active | Grace Period | Overdue | Penalty | Closed | ...

  CustomerLoanSummary({
    required this.loanId,
    required this.loanNumber,
    this.templateName,
    required this.principalAmount,
    required this.outstandingBalance,
    this.nextDueDate,
    this.nextDueAmount,
    required this.loanStatus,
  });

  bool get isClosed => loanStatus == 'Closed' || loanStatus == 'Cancelled' || loanStatus == 'Defaulted';
  bool get isActiveFamily => !isClosed;
}

class LoanScheduleEntry {
  final int installmentNumber;
  final DateTime dueDate;
  final int installmentAmount;
  final String status; // Pending | Completed | Partial

  LoanScheduleEntry({
    required this.installmentNumber,
    required this.dueDate,
    required this.installmentAmount,
    required this.status,
  });
}

/// Payment History row. Field shape/labels intentionally kept close to
/// AG-002/OW-006's CollectionDueRow where the schema overlaps
/// (loanNumber, amount, status) per this chat's brief — extended with
/// paymentMode (Cash|Online) and businessDate since CollectionDueRow
/// itself has no payment-mode field (it's a due-list row, not a
/// history row). Flagged in the integration note for master chat to
/// reconcile if a shared history-row type is preferred instead.
class LoanPaymentHistoryEntry {
  final String collectionId;
  final DateTime businessDate;
  final int collectedAmount;
  final String paymentMode; // Cash | Online, per §7.1/§7.5
  final String receiptNumber;

  LoanPaymentHistoryEntry({
    required this.collectionId,
    required this.businessDate,
    required this.collectedAmount,
    required this.paymentMode,
    required this.receiptNumber,
  });
}

/// Pending Online Payment awaiting Owner/Agent confirmation, per
/// `customer_online_payments` §7.5.
class PendingOnlinePayment {
  final String onlinePaymentId;
  final int amount;
  final DateTime submittedAt;

  PendingOnlinePayment({required this.onlinePaymentId, required this.amount, required this.submittedAt});
}

class CustomerLoanDetail {
  final CustomerLoanSummary summary;
  final String repaymentType; // Daily | Weekly | Monthly
  final int durationValue;
  final int installmentAmount;
  final DateTime effectiveDate;
  final List<LoanScheduleEntry> schedule;
  final List<PendingOnlinePayment> pendingOnlinePayments;
  final int? penaltyAmount; // penalty_entries, if applicable
  final DateTime? gracePeriodEndDate; // if applicable
  /// The collecting agent's name. Null when the embed came back empty rather
  /// than "nobody" — the screen simply omits the row in that case instead of
  /// showing a blank one.
  final String? loanGivenBy;

  CustomerLoanDetail({
    required this.summary,
    this.loanGivenBy,
    required this.repaymentType,
    required this.durationValue,
    required this.installmentAmount,
    required this.effectiveDate,
    this.schedule = const [],
    this.pendingOnlinePayments = const [],
    this.penaltyAmount,
    this.gracePeriodEndDate,
  });
}

// ============================================================================
// State — Loan List
// ============================================================================

class CustomerLoansState {
  final bool loading;
  final String? error;
  final List<CustomerLoanSummary> loans;

  const CustomerLoansState({this.loading = false, this.error, this.loans = const []});

  /// Closed-loans-hidden is a Customer-screen-only rule (explicit,
  /// locked exception — OW-004/AG-004 keep showing closed loans, this
  /// is intentionally asymmetric, not a universal filter). Sort is
  /// locked: active-family loans first, earliest due date → latest.
  List<CustomerLoanSummary> get visibleSorted {
    final visible = loans.where((l) => !l.isClosed).toList();
    visible.sort((a, b) {
      final aDue = a.nextDueDate;
      final bDue = b.nextDueDate;
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return visible;
  }

  CustomerLoansState copyWith({bool? loading, String? error, bool clearError = false, List<CustomerLoanSummary>? loans}) {
    return CustomerLoansState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      loans: loans ?? this.loans,
    );
  }
}

class CustomerLoansNotifier extends Notifier<CustomerLoansState> {
  @override
  CustomerLoansState build() => const CustomerLoansState();

  Future<void> load({required String customerId, required String businessId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(customerLoansApiServiceProvider);
      final loans = await api.fetchLoans(customerId: customerId, businessId: businessId);
      state = state.copyWith(loading: false, loans: loans);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final customerLoansProvider = NotifierProvider<CustomerLoansNotifier, CustomerLoansState>(
  CustomerLoansNotifier.new,
);

// ============================================================================
// State — Loan Detail
// ============================================================================

class LoanDetailState {
  final bool loading;
  final String? error;
  final CustomerLoanDetail? detail;
  final bool historyLoading;
  final List<LoanPaymentHistoryEntry> paymentHistory;

  const LoanDetailState({
    this.loading = false,
    this.error,
    this.detail,
    this.historyLoading = false,
    this.paymentHistory = const [],
  });

  LoanDetailState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    CustomerLoanDetail? detail,
    bool? historyLoading,
    List<LoanPaymentHistoryEntry>? paymentHistory,
  }) {
    return LoanDetailState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      detail: detail ?? this.detail,
      historyLoading: historyLoading ?? this.historyLoading,
      paymentHistory: paymentHistory ?? this.paymentHistory,
    );
  }
}

class LoanDetailNotifier extends Notifier<LoanDetailState> {
  @override
  LoanDetailState build() => const LoanDetailState();

  Future<void> load(String loanId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(customerLoansApiServiceProvider);
      final detail = await api.fetchLoanDetail(loanId: loanId);
      state = state.copyWith(loading: false, detail: detail);
      unawaited(_loadHistory(loanId));
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> _loadHistory(String loanId) async {
    state = state.copyWith(historyLoading: true);
    try {
      final api = ref.read(customerLoansApiServiceProvider);
      final history = await api.fetchStatement(loanId: loanId);
      state = state.copyWith(historyLoading: false, paymentHistory: history);
    } catch (e) {
      state = state.copyWith(historyLoading: false, error: e.toString());
    }
  }

  void reset() => state = const LoanDetailState();
}

final loanDetailProvider = NotifierProvider<LoanDetailNotifier, LoanDetailState>(
  LoanDetailNotifier.new,
);

// Small local helper so this file has no extra package dependency just
// for a single fire-and-forget call.
void unawaited(Future<void> future) {}

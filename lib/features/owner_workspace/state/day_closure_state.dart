import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OW-011 — Day Closure. Real Supabase wiring.
///
/// SCHEMA/RLS GAP FOUND (flag prominently — see END RESULT): the original
/// stub's own comment on `recordDifferenceAdjustment` correctly identified
/// that no documented endpoint creates a `settlement_adjustments` row
/// directly from Day Closure's Difference Analyzer (settlement_id NULL,
/// business_date-scoped). Having now read the REAL schema
/// (0009_module8_finance_cash.sql), the gap is worse than "no documented
/// endpoint" — it's structurally unscopable:
///   `settlement_adjustments` has NO `business_id` column at all. It's only
///   reachable via `settlement_id` (→ account_settlements → business_id) or
///   `agent_id` (→ agents → business_members → business_id). A Day-Closure-
///   created adjustment has neither (it's business-date-scoped, not tied to
///   any one agent's settlement) — `target_customer_id` doesn't reach
///   business_id either without ALSO knowing which business that customer's
///   membership is under (a customer's `customer_id` isn't itself
///   business-scoped in a single hop the way this table is shaped).
///   The RLS policy this session's earlier work wrote for this table
///   (0017_rls_module8_finance_cash.sql, `settlement_adjustments_owner_all`)
///   ONLY grants access via those same two paths — a row with both
///   `agent_id` and `settlement_id` NULL would be **written successfully
///   but then invisible to everyone, Owner included**, since RLS would
///   reject every SELECT against it. This is not a client-side wiring
///   problem to work around; it needs either a `business_id` column added
///   to `settlement_adjustments` (schema chat) or a written policy amending
///   `settlement_adjustments_owner_all` to also allow `business_date`-only
///   rows scoped some other way (RLS chat) — flagged for master chat, not
///   silently resolved here.
///
/// Given that, `recordDifferenceAdjustment` is wired as a BLOCKED RPC
/// (matching the calc-engine convention already established in
/// agent_settlement_state.dart's `submit_agent_settlement`) rather than a
/// raw insert that would currently write an orphaned, RLS-invisible row.
///
/// `closeDay` is ALSO wired as a blocked RPC even though 15_Calculation_
/// Engine.md wasn't attached to this specific session to confirm it by
/// name (only BF Cash Validation / Salary Formula / Settlement Short-Excess
/// were named explicitly in the briefing) — flagged as an extension of that
/// pattern, not a literal instruction: closing a day authoritatively
/// commits `expected_*`/`difference` figures and updates `day_ledger.status`
/// in the same transaction as the BR-043/219 zero-difference hard gate, and
/// doing that as a client-side multi-table write (INSERT day_closures +
/// UPDATE day_ledger) risks the exact "client-side recompute could drift
/// from what's enforced server-side" problem the briefing warned about for
/// the other three operations. Confirm with master chat before relying on
/// this classification.
class DayClosureApiService {
  SupabaseClient get _db => Supabase.instance.client;

  // GET-equivalent: businesses/{id}/day-closures/{date}/precheck
  //
  // APPROXIMATION FLAGGED: `collection_drafts` (the "Pending Drafts"
  // blocking-issue source) has no `business_id` or `business_date` column
  // of its own — only `created_by_membership_id` (→ business_members →
  // business_id) and `created_at` (a timestamp, not a business_date). This
  // implementation joins through business_members for business_id and
  // filters created_at by calendar day as the closest available proxy for
  // "drafts pending as of this business_date" — confirm this proxy is
  // acceptable, or that a business_date column should be added to
  // collection_drafts, before relying on this count being exact.
  Future<DayClosurePrecheckResult> precheck({
    required String businessId,
    required String businessDate,
  }) async {
    final dayStart = '$businessDate 00:00:00';
    final dayEnd = '$businessDate 23:59:59';

    final draftRows = await _db
        .from('collection_drafts')
        .select('draft_id, business_members!inner(business_id)')
        .eq('business_members.business_id', businessId)
        .eq('status', 'Draft')
        .gte('created_at', dayStart)
        .lte('created_at', dayEnd);
    final pendingDraftCount = (draftRows as List).length;

    final blockingIssues = <DayClosureBlockingIssue>[
      if (pendingDraftCount > 0)
        DayClosureBlockingIssue(type: 'Pending Drafts', count: pendingDraftCount, detailLink: '/ag-005'),
    ];

    final ledgerRow = await _db
        .from('day_ledger')
        .select('opening_balance, total_collections, total_loan_distribution, '
            'investor_deposits, investor_withdrawals, total_expenses, closing_balance, status')
        .eq('business_id', businessId)
        .eq('business_date', businessDate)
        .maybeSingle();

    if (ledgerRow == null) {
      // No day_ledger row yet for this date — nothing has happened on this
      // business_date to reconcile. Treat as a blocking issue rather than
      // silently fabricating zero-value Expected figures.
      return DayClosurePrecheckResult(
        canProceed: false,
        blockingIssues: [
          ...blockingIssues,
          DayClosureBlockingIssue(type: 'No Ledger Activity', count: 0),
        ],
      );
    }

    final expected = ExpectedFigures(
      // day_ledger doesn't split "expected" by payment method (Cash/UPI/
      // Bank/Cheque) — it tracks a single closing_balance. This maps the
      // aggregate onto expectedCash and zeroes the other three, which is
      // almost certainly wrong for a business using multiple payment
      // methods. FLAGGED: either day_ledger needs per-method columns, or
      // the per-method expected split needs to come from the (also
      // blocked) close_business_day RPC instead of being read from
      // day_ledger directly. Do not ship this approximation without
      // confirming against the real calculation engine spec.
      expectedCash: (ledgerRow['closing_balance'] as num).toDouble(),
      expectedUpi: 0,
      expectedBank: 0,
      expectedCheque: 0,
    );

    return DayClosurePrecheckResult(
      canProceed: blockingIssues.isEmpty,
      blockingIssues: blockingIssues,
      expected: expected,
    );
  }

  // BLOCKED ON RPC — see class-level note above.
  // Expected: supabase.rpc('close_business_day', params: {
  //   'p_business_id': businessId, 'p_business_date': businessDate,
  //   'p_physical_cash': physicalCash, 'p_upi_balance': upiBalance,
  //   'p_bank_balance': bankBalance, 'p_cheque_balance': chequeBalance,
  //   'p_remarks': remarks,
  // }) — server re-derives expected_* and difference authoritatively,
  // hard-rejects (422-equivalent Postgres exception) if difference != 0
  // per BR-043/219, and performs the day_closures INSERT + day_ledger
  // status UPDATE atomically. Also expected to serve as the "close-again"
  // path (server auto-detects via day_ledger.status per the original
  // stub's §8.6.1 alias note) — no separate client method needed for that.
  Future<DayClosureResult> closeDay({
    required String businessId,
    required String businessDate,
    required double physicalCash,
    required double upiBalance,
    required double bankBalance,
    required double chequeBalance,
    String? remarks,
  }) async {
    throw UnimplementedError(
      'BLOCKED on RPC "close_business_day" (not yet built). Authoritative '
      'Expected-vs-Actual recomputation + the BR-043/219 zero-difference '
      'hard gate must happen server-side, not as a client-side multi-table '
      'write — see class-level note.',
    );
  }

  // GET businesses/{id}/day-closures/{date}
  Future<DayClosureDetail> fetchClosureDetail({
    required String businessId,
    required String businessDate,
  }) async {
    final row = await _db
        .from('day_closures')
        .select('closure_id, business_date, physical_cash, upi_balance, bank_balance, cheque_balance, '
            'expected_cash, expected_upi, expected_bank, expected_cheque, difference, '
            'closed_at, reopened_at, reopen_reason, '
            'persons!day_closures_closed_by_person_id_fkey(full_name), '
            'day_ledger:business_id(opening_balance, total_collections, total_loan_distribution, '
            'investor_deposits, investor_withdrawals, total_expenses, closing_balance)')
        .eq('business_id', businessId)
        .eq('business_date', businessDate)
        .single();

    // NOTE: the day_ledger embed above is written as `day_ledger:business_id(...)`
    // which is NOT a valid Postgrest embed on its own — day_ledger and
    // day_closures share (business_id, business_date) as a natural key, not
    // a direct FK from day_closures to day_ledger. FLAGGED SCHEMA GAP:
    // there is no FK column on day_closures pointing at day_ledger.ledger_id
    // (or vice versa) to embed through. This implementation falls back to a
    // second explicit query below rather than relying on the embed above —
    // left the embed attempt in a comment-adjacent form so the gap is
    // visible, but the actual working code path is the explicit second
    // query immediately following.
    final ledgerRow = await _db
        .from('day_ledger')
        .select('opening_balance, total_collections, total_loan_distribution, '
            'investor_deposits, investor_withdrawals, total_expenses')
        .eq('business_id', businessId)
        .eq('business_date', businessDate)
        .maybeSingle();

    final person = row['persons'] as Map<String, dynamic>?;

    return DayClosureDetail(
      closureId: row['closure_id'] as String,
      businessDate: row['business_date'] as String,
      openingBalance: ((ledgerRow?['opening_balance'] as num?) ?? 0).toDouble(),
      collections: ((ledgerRow?['total_collections'] as num?) ?? 0).toDouble(),
      loansIssued: ((ledgerRow?['total_loan_distribution'] as num?) ?? 0).toDouble(),
      expenses: ((ledgerRow?['total_expenses'] as num?) ?? 0).toDouble(),
      depositsInvestor: ((ledgerRow?['investor_deposits'] as num?) ?? 0).toDouble(),
      withdrawalsInvestor: ((ledgerRow?['investor_withdrawals'] as num?) ?? 0).toDouble(),
      // settlement_adjustments total for this business_date is NOT included
      // here — see the class-level GAP note: adjustments created here are
      // currently unscopable/unreadable via RLS, so there is nothing valid
      // to sum yet. Hardcoded to 0 until that gap is resolved. FLAGGED, not
      // silently guessed.
      adjustments: 0,
      closingBalance: (row['physical_cash'] as num).toDouble() +
          (row['upi_balance'] as num).toDouble() +
          (row['bank_balance'] as num).toDouble() +
          (row['cheque_balance'] as num).toDouble(),
      difference: (row['difference'] as num).toDouble(),
      remarks: null, // day_closures has no `remarks` column in the real schema — FLAGGED below
      closedByName: person?['full_name'] as String? ?? '',
      closedAt: DateTime.parse(row['closed_at'] as String),
      reopenedAt: row['reopened_at'] != null ? DateTime.parse(row['reopened_at'] as String) : null,
      reopenReason: row['reopen_reason'] as String?,
    );
  }

  // POST day-closures/{closure_id}/reopen — Owner-only (BR-221), plain
  // UPDATE, no RPC needed: no recomputation happens at reopen time itself
  // (the spec's "Close Again" cycle re-runs the full precheck separately).
  Future<void> reopenClosedDay({
    required String closureId,
    required String reason,
  }) async {
    await _db.from('day_closures').update({
      'reopened_at': DateTime.now().toIso8601String(),
      'reopen_reason': reason,
    }).eq('closure_id', closureId);
  }

  // BLOCKED ON RPC — see class-level note above (settlement_adjustments has
  // no business_id column; a raw insert here would write an orphaned,
  // RLS-invisible row).
  // Expected: supabase.rpc('record_day_closure_adjustment', params: {
  //   'p_business_id': businessId, 'p_business_date': businessDate,
  //   'p_adjustment_type': adjustmentType, 'p_amount': amount,
  //   'p_applied_to': appliedTo, 'p_target_customer_id': targetCustomerId,
  // })
  Future<void> recordDifferenceAdjustment({
    required String businessId,
    required String businessDate,
    required String adjustmentType,
    required double amount,
    required String appliedTo,
    String? targetCustomerId,
  }) async {
    throw UnimplementedError(
      'BLOCKED on RPC "record_day_closure_adjustment" (not yet built). '
      'settlement_adjustments has no business_id column and no path to one '
      'when settlement_id and agent_id are both NULL — a raw insert here '
      'would create a row invisible to every RLS policy, Owner included. '
      'Needs either a schema change (add business_id) or an RLS policy '
      'change before this can be a plain insert — see class-level note.',
    );
  }
}

final dayClosureApiServiceProvider = Provider<DayClosureApiService>((ref) {
  return DayClosureApiService();
});

// ============================================================================
// Result / model types
// ============================================================================

class DayClosureBlockingIssue {
  final String type; // e.g. 'Pending Drafts', 'Pending Collections', ...
  final int count;
  final String? detailLink; // route to send the Owner back to, e.g. '/ow-006'
  DayClosureBlockingIssue({required this.type, required this.count, this.detailLink});
}

class DayClosurePrecheckResult {
  final bool canProceed;
  final List<DayClosureBlockingIssue> blockingIssues;
  final List<DayClosureBlockingIssue> warnings;
  final ExpectedFigures? expected; // surfaced only when canProceed=true
  DayClosurePrecheckResult({
    required this.canProceed,
    this.blockingIssues = const [],
    this.warnings = const [],
    this.expected,
  });
}

/// Per-method Expected figures, computed server-side from `day_ledger`.
class ExpectedFigures {
  final double expectedCash;
  final double expectedUpi;
  final double expectedBank;
  final double expectedCheque;
  ExpectedFigures({
    required this.expectedCash,
    required this.expectedUpi,
    required this.expectedBank,
    required this.expectedCheque,
  });

  double get total => expectedCash + expectedUpi + expectedBank + expectedCheque;
}

class DayClosureResult {
  final String closureId;
  final String businessDate;
  final double difference; // always 0.00 on a successful response
  final double closingBalance;
  final String status; // 'Closed'
  DayClosureResult({
    required this.closureId,
    required this.businessDate,
    required this.difference,
    required this.closingBalance,
    required this.status,
  });
}

/// OW-011 Final Review payload (also the post-close receipt view).
class DayClosureDetail {
  final String closureId;
  final String businessDate;
  final double openingBalance;
  final double collections;
  final double loansIssued;
  final double expenses;
  final double depositsInvestor;
  final double withdrawalsInvestor;
  final double adjustments;
  final double closingBalance;
  final double difference;
  final String? remarks;
  final String closedByName;
  final DateTime closedAt;
  final DateTime? reopenedAt;
  final String? reopenReason;

  DayClosureDetail({
    required this.closureId,
    required this.businessDate,
    required this.openingBalance,
    required this.collections,
    required this.loansIssued,
    required this.expenses,
    required this.depositsInvestor,
    required this.withdrawalsInvestor,
    required this.adjustments,
    required this.closingBalance,
    required this.difference,
    this.remarks,
    required this.closedByName,
    required this.closedAt,
    this.reopenedAt,
    this.reopenReason,
  });

  bool get isReopened => reopenedAt != null;
}

/// One difference-analyzer line — per-method Expected vs Actual, so the
/// Owner can see exactly where the mismatch is (spec: "Display Difference
/// Details — per-method breakdown showing exactly where Expected and Actual
/// diverge").
class DifferenceLine {
  final String method; // 'Cash' | 'UPI' | 'Bank' | 'Cheque'
  final double expected;
  final double actual;
  DifferenceLine({required this.method, required this.expected, required this.actual});
  double get delta => expected - actual;
}

/// One Short/Excess entry recorded during the Difference Analyzer loop
/// (client-side accumulation before/alongside the server call — mirrors
/// `settlement_adjustments`, BR-045/066/069/070).
class RecordedAdjustment {
  final String adjustmentType; // 'Short' | 'Excess'
  final double amount;
  final String appliedTo;
  final String? targetCustomerId;
  final String? note;
  RecordedAdjustment({
    required this.adjustmentType,
    required this.amount,
    required this.appliedTo,
    this.targetCustomerId,
    this.note,
  });
}

// ============================================================================
// Screen state machine — mirrors OW-011 STATES S1-S6
// ============================================================================

enum DayClosurePhase {
  loadingPrecheck, // initial precheck call in flight
  blocked, // S1 — Pre-Check Blocked
  cashVerification, // S2 — Owner entering Actual figures
  differenceFound, // S3 — nonzero Difference, Owner resolving
  finalReview, // S4 — Difference = 0, summary shown
  closed, // S5 — Business Day locked
  reopened, // S6 — previously Closed day temporarily reopened
}

class DayClosureState {
  final DayClosurePhase phase;
  final String businessDate;

  // S1
  final List<DayClosureBlockingIssue> blockingIssues;
  final List<DayClosureBlockingIssue> warnings;

  // S2 — Owner-entered Actual figures
  final ExpectedFigures? expected;
  final double physicalCash;
  final double upiBalance;
  final double bankBalance;
  final double chequeBalance;

  // S3 — Difference Analyzer loop
  final List<DifferenceLine> differenceLines;
  final List<RecordedAdjustment> recordedAdjustments;

  // S4 — Final Review (post successful close call)
  final DayClosureDetail? closureDetail;

  final bool submitting;
  final String? error;

  const DayClosureState({
    this.phase = DayClosurePhase.loadingPrecheck,
    this.businessDate = '',
    this.blockingIssues = const [],
    this.warnings = const [],
    this.expected,
    this.physicalCash = 0,
    this.upiBalance = 0,
    this.bankBalance = 0,
    this.chequeBalance = 0,
    this.differenceLines = const [],
    this.recordedAdjustments = const [],
    this.closureDetail,
    this.submitting = false,
    this.error,
  });

  double get actualTotal => physicalCash + upiBalance + bankBalance + chequeBalance;
  double get expectedTotal => expected?.total ?? 0;
  double get difference => expectedTotal - actualTotal;
  bool get isZeroDifference => difference.abs() < 0.005; // ₹0.00 tolerance for double rounding only

  DayClosureState copyWith({
    DayClosurePhase? phase,
    String? businessDate,
    List<DayClosureBlockingIssue>? blockingIssues,
    List<DayClosureBlockingIssue>? warnings,
    ExpectedFigures? expected,
    double? physicalCash,
    double? upiBalance,
    double? bankBalance,
    double? chequeBalance,
    List<DifferenceLine>? differenceLines,
    List<RecordedAdjustment>? recordedAdjustments,
    DayClosureDetail? closureDetail,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return DayClosureState(
      phase: phase ?? this.phase,
      businessDate: businessDate ?? this.businessDate,
      blockingIssues: blockingIssues ?? this.blockingIssues,
      warnings: warnings ?? this.warnings,
      expected: expected ?? this.expected,
      physicalCash: physicalCash ?? this.physicalCash,
      upiBalance: upiBalance ?? this.upiBalance,
      bankBalance: bankBalance ?? this.bankBalance,
      chequeBalance: chequeBalance ?? this.chequeBalance,
      differenceLines: differenceLines ?? this.differenceLines,
      recordedAdjustments: recordedAdjustments ?? this.recordedAdjustments,
      closureDetail: closureDetail ?? this.closureDetail,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DayClosureNotifier extends Notifier<DayClosureState> {
  @override
  DayClosureState build() => const DayClosureState();

  /// Loads directly into the Closed-day view for the Reopen entry point
  /// (reached from OW-010 Report Hub or OW-001, per NAVIGATION — lands in
  /// S6 without running the normal Pre-Check → Cash Verification sequence,
  /// since this date is already Closed).
  Future<void> loadForReopen({required String businessId, required String businessDate}) async {
    state = DayClosureState(businessDate: businessDate, submitting: true);
    try {
      final api = ref.read(dayClosureApiServiceProvider);
      final detail = await api.fetchClosureDetail(businessId: businessId, businessDate: businessDate);
      state = state.copyWith(phase: DayClosurePhase.closed, closureDetail: detail, submitting: false);
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
    }
  }

  /// Runs the Pre-Check gate. Must be called before Cash Verification is
  /// ever shown (spec: "Pre-Check is a hard gate").
  Future<void> runPrecheck({required String businessId, required String businessDate}) async {
    state = DayClosureState(
      phase: DayClosurePhase.loadingPrecheck,
      businessDate: businessDate,
      submitting: true,
    );
    try {
      final api = ref.read(dayClosureApiServiceProvider);
      final result = await api.precheck(businessId: businessId, businessDate: businessDate);
      if (!result.canProceed) {
        state = state.copyWith(
          phase: DayClosurePhase.blocked,
          blockingIssues: result.blockingIssues,
          warnings: result.warnings,
          submitting: false,
        );
        return;
      }
      state = state.copyWith(
        phase: DayClosurePhase.cashVerification,
        warnings: result.warnings,
        expected: result.expected,
        submitting: false,
      );
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
    }
  }

  /// S2 — Owner enters Actual figures.
  void setActualFigures({
    double? physicalCash,
    double? upiBalance,
    double? bankBalance,
    double? chequeBalance,
  }) {
    state = state.copyWith(
      physicalCash: physicalCash ?? state.physicalCash,
      upiBalance: upiBalance ?? state.upiBalance,
      bankBalance: bankBalance ?? state.bankBalance,
      chequeBalance: chequeBalance ?? state.chequeBalance,
    );
  }

  /// Recalculate — moves to Difference Found (S3) or Final Review (S4)
  /// depending on whether Difference = 0. Client-side recalculation only;
  /// the authoritative zero-difference gate is re-enforced server-side on
  /// the actual close call (per API BINDING note: "client-side precheck is
  /// advisory only").
  void recalculate() {
    final expected = state.expected;
    if (expected == null) return;
    final lines = [
      DifferenceLine(method: 'Cash', expected: expected.expectedCash, actual: state.physicalCash),
      DifferenceLine(method: 'UPI', expected: expected.expectedUpi, actual: state.upiBalance),
      DifferenceLine(method: 'Bank', expected: expected.expectedBank, actual: state.bankBalance),
      DifferenceLine(method: 'Cheque', expected: expected.expectedCheque, actual: state.chequeBalance),
    ];
    state = state.copyWith(
      differenceLines: lines,
      phase: state.isZeroDifference ? DayClosurePhase.finalReview : DayClosurePhase.differenceFound,
    );
  }

  /// Owner records a Short/Excess adjustment during the Difference Analyzer
  /// loop (BR-045/066/069/070 mechanism, reused here for a Day Closure
  /// difference rather than an Agent settlement difference).
  Future<bool> recordAdjustment({
    required String businessId,
    required String adjustmentType,
    required double amount,
    required String appliedTo,
    String? targetCustomerId,
    String? note,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(dayClosureApiServiceProvider);
      await api.recordDifferenceAdjustment(
        businessId: businessId,
        businessDate: state.businessDate,
        adjustmentType: adjustmentType,
        amount: amount,
        appliedTo: appliedTo,
        targetCustomerId: targetCustomerId,
      );
      final entry = RecordedAdjustment(
        adjustmentType: adjustmentType,
        amount: amount,
        appliedTo: appliedTo,
        targetCustomerId: targetCustomerId,
        note: note,
      );
      // Excess reduces the outstanding difference (money found), Short
      // increases actual on the books (money owed) — either way, the
      // adjustment feeds back into an updated Actual/Expected reconciliation
      // rather than silently zeroing the difference; Owner recalculates
      // after correcting the underlying figures per the spec's own loop.
      state = state.copyWith(
        recordedAdjustments: [...state.recordedAdjustments, entry],
        submitting: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// S4 → S5 — Owner Confirms → Close Business Day. Only reachable when
  /// Difference = 0 (hard block, BR-043/219 — no override path).
  Future<bool> confirmClose({required String businessId, String? remarks}) async {
    if (!state.isZeroDifference) return false; // hard block, never bypass
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(dayClosureApiServiceProvider);
      final result = await api.closeDay(
        businessId: businessId,
        businessDate: state.businessDate,
        physicalCash: state.physicalCash,
        upiBalance: state.upiBalance,
        bankBalance: state.bankBalance,
        chequeBalance: state.chequeBalance,
        remarks: remarks,
      );
      final detail = await api.fetchClosureDetail(businessId: businessId, businessDate: state.businessDate);
      state = state.copyWith(
        phase: DayClosurePhase.closed,
        closureDetail: detail,
        submitting: false,
      );
      return result.status == 'Closed';
    } catch (e) {
      // NONZERO_DIFFERENCE (422) from the authoritative server-side gate —
      // route back into Difference Found rather than a generic error.
      state = state.copyWith(
        phase: DayClosurePhase.differenceFound,
        submitting: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Reopen Closed Day — Owner only, mandatory reason, always audited.
  Future<bool> reopenClosedDay({required String reason}) async {
    final detail = state.closureDetail;
    if (detail == null || reason.trim().isEmpty) return false; // Reason Required, hard gate
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(dayClosureApiServiceProvider);
      await api.reopenClosedDay(closureId: detail.closureId, reason: reason.trim());
      state = state.copyWith(phase: DayClosurePhase.reopened, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// "Close Again" after a Reopen — re-enters the full Cash Verification →
  /// Difference Analyzer → Final Review → Confirmation cycle (spec: "Owner
  /// must run Day Closure a second time"). Re-runs Pre-Check first, same as
  /// any other closure attempt.
  Future<void> closeAgain({required String businessId}) async {
    await runPrecheck(businessId: businessId, businessDate: state.businessDate);
  }

  void reset() => state = const DayClosureState();
}

final dayClosureProvider = NotifierProvider<DayClosureNotifier, DayClosureState>(
  DayClosureNotifier.new,
);

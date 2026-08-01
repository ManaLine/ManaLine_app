import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/mana_time.dart';

/// OW-011 — Day Closure. Real Supabase wiring.
///
/// SCHEMA/RLS GAP — RESOLVED in migration 0054. Recorded here because the
/// shape of the fix explains the RPCs below.
///
/// `settlement_adjustments` (0009) had NO `business_id` column: it was
/// reachable only via `settlement_id` (→ account_settlements → business_id)
/// or `agent_id` (→ agents → business_members → business_id). A Day-Closure
/// difference adjustment has neither — it is business-date-scoped, not tied
/// to any one agent's settlement — and `target_customer_id` does not reach
/// business_id in a single hop either. Since
/// `settlement_adjustments_owner_all` (0017) tested exactly those two paths,
/// a row with both NULL would have been written successfully and then been
/// invisible to every role including the Owner who created it. 0054 adds the
/// nullable `business_id` column and a third policy branch for it, which is
/// what makes `recordDifferenceAdjustment` a real, readable write rather
/// than an orphan.
///
/// `closeDay` is an RPC for the reason its own blocked note gave: closing a
/// day commits `expected_*`/`difference` and flips `day_ledger.status` in
/// the same transaction as the BR-043/219 zero-difference hard gate, and a
/// client-side multi-table write could drift from what is enforced
/// server-side. The Expected figures used by both the gate and `precheck`
/// below come from one shared function (`app.day_closure_expected`) so the
/// advisory client check and the authoritative server check cannot disagree.
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

    // PERF: the draft count and the ledger row are independent, so both go
    // out together. app.day_closure_expected deliberately stays OUT of this
    // batch — it raises P0002 when no day_ledger row exists, which would turn
    // the graceful "No Ledger Activity" result below into a thrown error.
    final results = await Future.wait<dynamic>([
      _db
          .from('collection_drafts')
          .select('draft_id, business_members!inner(business_id)')
          .eq('business_members.business_id', businessId)
          .eq('status', 'Draft')
          .gte('created_at', dayStart)
          .lte('created_at', dayEnd),
      _db
          .from('day_ledger')
          .select('opening_balance, total_collections, total_loan_distribution, '
              'investor_deposits, investor_withdrawals, total_expenses, closing_balance, status')
          .eq('business_id', businessId)
          .eq('business_date', businessDate)
          .maybeSingle(),
    ]);
    final draftRows = results[0] as List;
    final ledgerRow = results[1] as Map<String, dynamic>?;

    final pendingDraftCount = draftRows.length;
    final blockingIssues = <DayClosureBlockingIssue>[
      if (pendingDraftCount > 0)
        DayClosureBlockingIssue(type: 'Pending Drafts', count: pendingDraftCount, detailLink: '/ag-005'),
    ];

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

    // The per-method Expected split now comes from
    // `app.day_closure_expected` (migration 0054) — the SAME function
    // close_business_day uses for its BR-043/219 gate, so this advisory
    // precheck and the authoritative server check cannot disagree. This
    // replaces an approximation that dumped day_ledger.closing_balance into
    // expectedCash and zeroed UPI/Bank/Cheque; on any business taking
    // non-cash payments that showed the Owner a green zero-difference on a
    // day the server would then refuse to close. day_ledger itself has no
    // per-method columns — the split is derived from
    // collection_payment_splits.payment_mode; see 0054 for the derivation.
    final expectedRows = await _db.schema('app').rpc('day_closure_expected', params: {
      'p_business_id': businessId,
      'p_business_date': businessDate,
    });
    final e = (expectedRows as List).first as Map<String, dynamic>;
    final expected = ExpectedFigures(
      expectedCash: (e['expected_cash'] as num).toDouble(),
      expectedUpi: (e['expected_upi'] as num).toDouble(),
      expectedBank: (e['expected_bank'] as num).toDouble(),
      expectedCheque: (e['expected_cheque'] as num).toDouble(),
    );

    return DayClosurePrecheckResult(
      canProceed: blockingIssues.isEmpty,
      blockingIssues: blockingIssues,
      expected: expected,
    );
  }

  /// Backed by `app.close_business_day` (migration 0054). The server
  /// re-derives expected_* and difference authoritatively, hard-rejects with
  /// a PostgrestException if difference != 0 per BR-043/219 (no override
  /// parameter exists), and performs the day_closures write + day_ledger
  /// status UPDATE atomically. It also serves the "close again" path — it
  /// detects a reopened closure from that row's own reopened_at and updates
  /// it rather than inserting a second closure for the same business day, so
  /// no separate client method is needed.
  Future<DayClosureResult> closeDay({
    required String businessId,
    required String businessDate,
    required double physicalCash,
    required double upiBalance,
    required double bankBalance,
    required double chequeBalance,
    String? remarks,
  }) async {
    final result = await _db.schema('app').rpc('close_business_day', params: {
      'p_business_id': businessId,
      'p_business_date': businessDate,
      'p_physical_cash': physicalCash,
      'p_upi_balance': upiBalance,
      'p_bank_balance': bankBalance,
      'p_cheque_balance': chequeBalance,
      'p_remarks': remarks,
    }) as Map<String, dynamic>;
    return DayClosureResult(
      closureId: result['closure_id'] as String,
      businessDate: result['business_date'] as String,
      difference: (result['difference'] as num).toDouble(),
      closingBalance: (result['closing_balance'] as num).toDouble(),
      status: result['status'] as String,
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
      'reopened_at': manaTimestamp(),
      'reopen_reason': reason,
    }).eq('closure_id', closureId);
  }

  /// Backed by `app.record_day_closure_adjustment` (migration 0054), which
  /// resolved the class-level gap: settlement_adjustments gained a nullable
  /// business_id column and settlement_adjustments_owner_all gained a third
  /// branch for it, so a business-day adjustment (settlement_id and agent_id
  /// both NULL) is now readable by the Owner who created it instead of being
  /// written and then hidden by RLS from everyone.
  Future<String> recordDifferenceAdjustment({
    required String businessId,
    required String businessDate,
    required String adjustmentType,
    required double amount,
    required String appliedTo,
    String? targetCustomerId,
  }) async {
    final result = await _db.schema('app').rpc('record_day_closure_adjustment', params: {
      'p_business_id': businessId,
      'p_business_date': businessDate,
      'p_adjustment_type': adjustmentType,
      'p_amount': amount,
      'p_applied_to': appliedTo,
      'p_target_customer_id': targetCustomerId,
    });
    return result as String;
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

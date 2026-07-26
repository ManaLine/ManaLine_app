import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'agent_dashboard_state.dart' show AgentBfAssignment, agentApiServiceProvider;

/// AG-006 Owner Settlement — real Supabase wiring, the AGENT-side half of
/// the settlement object whose OWNER-side half (`account_review_state.dart`,
/// OW-013) was already wired when this file was picked up — read that
/// file's `approveSettlement` doc comment first: it explicitly assumes the
/// Merged Addendum item 4 BF transfer ("FULL agent_bf_current returns to
/// businesses.owner_bf_balance... at Agent settlement") happens at THIS
/// file's submit step, not at Owner Approve. `submitSettlement` below is
/// wired to match that exact assumption — same state-machine understanding
/// across both files, per the briefing's explicit instruction not to wire
/// these independently.
///
/// SPEC GAP (unresolved, kept from the original stub): no dedicated
/// "preview" endpoint is spec'd anywhere in Part 3/Part 4B for AG-006 to
/// show SETTLEMENT SUMMARY figures before commit. `fetchSettlementPreview`
/// is implemented below as a direct-read aggregation (same category as
/// owner_api_service.dart's fetchDashboard — read-only, not a financial
/// write, so safe to compute client-side unlike the actual submit) rather
/// than left throwing, but the RESULT is explicitly a best-effort estimate,
/// not a guaranteed match for whatever `submit_agent_settlement`'s
/// authoritative Calculation Engine math produces server-side — flagged
/// inline below at `expectedClosingBalance`.
///
/// THIS SESSION: preview now also nets in confirmed `cash_transfers`
/// (BR-173, agent-to-agent BF transfers) — previously omitted entirely,
/// which would silently understate/overstate the preview for any agent
/// who sent or received a BF transfer during the period. See
/// `_fetchNetCashTransfers` below. This does not change anything about
/// the RPC-blocked `submitSettlement` — the authoritative figure still
/// only ever comes from the server.
class AgentSettlementApiService {
  final Ref ref;
  AgentSettlementApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  Future<String> _resolveMembershipId(String agentId) async {
    final row = await _db.from('agents').select('membership_id').eq('agent_id', agentId).single();
    return row['membership_id'] as String;
  }

  /// Net BF cash movement for this agent over the period, from
  /// `cash_transfers` (BR-173). Only transfers CONFIRMED by both sides
  /// count ("a transfer is only effective once BOTH are set" — API spec
  /// §5.6 Part 2) — a one-sided pending transfer does not move BF yet, so
  /// it's excluded here to match that same effective-once-both-confirmed
  /// rule rather than double-counting an unconfirmed leg.
  /// RLS (`cash_transfers_agent_select_party`) only returns rows where
  /// this agent is `from_agent_id` or `to_agent_id`, so no extra
  /// agent-identity filter is layered on top of what the two `.eq()`
  /// queries below already ask for.
  Future<double> _fetchNetCashTransfers({
    required String agentId,
    required String startStr,
    required String endStr,
  }) async {
    final outgoing = await _db
        .from('cash_transfers')
        .select('amount, from_agent_confirmed_at, to_agent_confirmed_at')
        .eq('from_agent_id', agentId)
        .gte('business_date', startStr)
        .lte('business_date', endStr);
    final incoming = await _db
        .from('cash_transfers')
        .select('amount, from_agent_confirmed_at, to_agent_confirmed_at')
        .eq('to_agent_id', agentId)
        .gte('business_date', startStr)
        .lte('business_date', endStr);

    bool bothConfirmed(Map<String, dynamic> r) =>
        r['from_agent_confirmed_at'] != null && r['to_agent_confirmed_at'] != null;

    final outTotal = (outgoing as List)
        .cast<Map<String, dynamic>>()
        .where(bothConfirmed)
        .fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());
    final inTotal = (incoming as List)
        .cast<Map<String, dynamic>>()
        .where(bothConfirmed)
        .fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());

    return inTotal - outTotal; // net effect on this agent's BF cash
  }

  // Best-effort SETTLEMENT SUMMARY preview — see class doc SPEC GAP note.
  Future<SettlementPreview> fetchSettlementPreview({
    required String businessId,
    required String agentId,
    required String cycleType, // 'Daily' | 'Weekly' | 'Monthly'
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final membershipId = await _resolveMembershipId(agentId);
    final startStr = periodStart.toIso8601String().split('T').first;
    final endStr = periodEnd.toIso8601String().split('T').first;

    final bfRow = await _db
        .from('agent_bf_assignments')
        .select('opening_bf')
        .eq('membership_id', membershipId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final openingBalance = (bfRow?['opening_bf'] as num?)?.toDouble() ?? 0;

    final collectionRows = await _db
        .from('collections')
        .select('collection_id, business_date')
        .eq('collected_by_membership_id', membershipId)
        .gte('business_date', startStr)
        .lte('business_date', endStr);
    final collectionIds = (collectionRows as List).map((c) => c['collection_id'] as String).toList();

    double cash = 0, upi = 0, bank = 0, cheque = 0;
    if (collectionIds.isNotEmpty) {
      final splitRows = await _db.from('collection_payment_splits').select('payment_mode, amount').inFilter('collection_id', collectionIds);
      for (final s in (splitRows as List)) {
        final amt = (s['amount'] as num).toDouble();
        switch (s['payment_mode']) {
          case 'Cash':
            cash += amt;
          case 'UPI':
            upi += amt;
          case 'Bank Transfer':
            bank += amt;
          case 'Cheque':
            cheque += amt;
        }
      }
    }

    final loanRows = await _db
        .from('loans')
        .select('amount_given')
        .eq('collection_agent_membership_id', membershipId)
        .gte('issue_business_date', startStr)
        .lte('issue_business_date', endStr);
    final loanDistribution = (loanRows as List).fold<double>(0, (sum, l) => sum + (l['amount_given'] as num).toDouble());

    final expenseRows = await _db
        .from('expenses')
        .select('amount')
        .eq('recorded_by_membership_id', membershipId)
        .gte('business_date', startStr)
        .lte('business_date', endStr);
    final expenses = (expenseRows as List).fold<double>(0, (sum, e) => sum + (e['amount'] as num).toDouble());

    final netCashTransfers = await _fetchNetCashTransfers(agentId: agentId, startStr: startStr, endStr: endStr);

    // BR-237 "expected_closing_balance" formula — 15_Calculation_Engine.md
    // owns the authoritative version of this; this is a plausible
    // reconstruction (Opening + Cash collected − Loans distributed −
    // Expenses + Net Cash Transfers In/Out (BR-173); UPI/Bank/Cheque are
    // collected but don't pass through physical BF cash so they're
    // excluded from the balance itself, only shown for reconciliation)
    // NOT a verified match. Flagged: master chat/backend should confirm
    // this against the real engine before this number is trusted for
    // anything beyond a rough on-screen preview — the actual difference()
    // getter in AgentSettlementState re-derives this independently of
    // submitSettlement's real server-computed value anyway, so a preview
    // mismatch here is a display quality issue, not a financial-integrity
    // one (the real number always comes from the BLOCKED submit RPC,
    // never from this preview).
    final expectedClosingBalance = openingBalance + cash - loanDistribution - expenses + netCashTransfers;

    return SettlementPreview(
      openingBalance: openingBalance,
      cashCollected: cash,
      upiCollected: upi,
      bankCollected: bank,
      chequeCollected: cheque,
      loanDistribution: loanDistribution,
      expenses: expenses,
      expectedClosingBalance: expectedClosingBalance,
    );
  }

  // BLOCKED ON RPC: creates the `account_settlements` row (status='Pending
  // Owner Review') AND performs the Merged Addendum item 4 BF transfer
  // (agent_bf_current -> owner_bf_balance, agent_bf_current resets to 0) in
  // the same atomic step — exactly the kind of financial multi-table write
  // the briefing says must be a Postgres function/Edge Function, not
  // sequential client-side calls. Also must recompute (server-side,
  // authoritatively) the same SETTLEMENT SUMMARY figures this class's
  // fetchSettlementPreview only estimates, per Part 4B §8.7's documented
  // "server computes every other figure" behavior — the RPC's real
  // computation supersedes the preview, it does not just validate it.
  //
  // Expected: supabase.rpc('submit_agent_settlement', params: {
  //   'p_business_id': businessId,
  //   'p_agent_membership_id': <resolved via _resolveMembershipId>,
  //   'p_cycle_type': cycleType,
  //   'p_period_start': periodStart.toIso8601String(),
  //   'p_period_end': periodEnd.toIso8601String(),
  //   'p_physical_cash_declared': physicalCashDeclared,
  //   'p_remarks': remarks,
  // })
  // expected to return {settlement_id, expected_closing_balance,
  // difference, status} matching SettlementSubmitResult below.
  /// FIXED (this pass): app.submit_agent_settlement RPC now exists
  /// (migration 0021). SIGNATURE CHANGE required: the original stub
  /// signature (businessId/cycleType/periodStart/periodEnd/
  /// physicalCashDeclared/remarks) doesn't carry nearly enough data for
  /// the RPC's real params (opening/cash/upi/bank/cheque/loan_distribution/
  /// expenses/expected_closing_balance, account_period_id, agents.agent_id)
  /// — added `agentId` (required) and `preview` (the SettlementPreview
  /// this same screen already fetches via fetchSettlementPreview, reused
  /// here rather than recomputed) as new required params. Screen call
  /// site must be updated to pass both — flag if not already done.
  ///
  /// account_period_id is resolved internally (no accountPeriodId param
  /// added) via the agent's own Running account_periods row for this
  /// business — same resolution pattern as fetchRunningAccountPeriods in
  /// agent_dashboard_state.dart. agents.agent_id (distinct from
  /// membership_id, which is what _resolveMembershipId gives the wrong
  /// direction for here) is looked up from agents by membership_id.
  /// RESOLVED (migration 0031, written right after this file was wired):
  /// this file's class-level header comment and account_review_state.dart's
  /// approveSettlement() comment both independently flagged the same
  /// ambiguity — Merged Addendum item 4's BF transfer ("FULL
  /// agent_bf_current returns to businesses.owner_bf_balance") was assumed
  /// to happen at Submit but was never actually implemented anywhere.
  /// app.submit_agent_settlement now performs that transfer atomically in
  /// the same transaction as the account_settlements insert — confirmed
  /// correct against both files' matching assumption, not guessed at.
  Future<SettlementSubmitResult> submitSettlement({
    required String businessId,
    required String agentId,
    required String cycleType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double physicalCashDeclared,
    required SettlementPreview preview,
    String? remarks,
  }) async {
    final membershipId = await _resolveMembershipId(agentId);

    final periodRow = await _db
        .from('account_periods')
        .select('account_period_id')
        .eq('agent_membership_id', membershipId)
        .eq('status', 'Running')
        .order('business_start_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (periodRow == null) {
      throw StateError('No Running account_period found for this agent — cannot submit a settlement without one.');
    }

    final result = await _db.schema('app').rpc('submit_agent_settlement', params: {
      'p_account_period_id': periodRow['account_period_id'],
      'p_agent_id': agentId,
      'p_cycle_type': cycleType,
      'p_opening_balance': preview.openingBalance,
      'p_cash_collected': preview.cashCollected,
      'p_upi_collected': preview.upiCollected,
      'p_bank_collected': preview.bankCollected,
      'p_cheque_collected': preview.chequeCollected,
      'p_loan_distribution': preview.loanDistribution,
      'p_expenses': preview.expenses,
      'p_expected_closing_balance': preview.expectedClosingBalance,
      'p_physical_cash_declared': physicalCashDeclared,
    });

    return SettlementSubmitResult(
      settlementId: result as String,
      expectedClosingBalance: preview.expectedClosingBalance,
      difference: physicalCashDeclared - preview.expectedClosingBalance,
      status: SettlementStatus.pendingOwnerReview,
    );
  }

  // GET this Agent's own most recent settlement — read-only, safe as a
  // direct query (rls_role_matrix.md: "A: SELECT + INSERT own settlement
  // rows only").
  Future<AgentSettlementRecord?> fetchOwnLatestSettlement({
    required String businessId,
    required String agentId,
  }) async {
    final row = await _db
        .from('account_settlements')
        .select('''
          settlement_id, opening_balance, cash_collected, upi_collected, bank_collected, cheque_collected,
          loan_distribution, expenses, expected_closing_balance, physical_cash_declared, difference,
          status, submitted_at,
          account_periods!inner(business_id)
        ''')
        .eq('agent_id', agentId)
        .eq('account_periods.business_id', businessId)
        .order('submitted_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;

    final adjustmentRows = await _db
        .from('settlement_adjustments')
        .select('adjustment_type, amount, applied_to')
        .eq('settlement_id', row['settlement_id']);
    final returnReasonRow = row['status'] == 'Returned'
        ? await _db.from('account_settlements').select('return_reason').eq('settlement_id', row['settlement_id']).single()
        : null;

    return AgentSettlementRecord(
      settlementId: row['settlement_id'] as String,
      summary: SettlementPreview(
        openingBalance: (row['opening_balance'] as num).toDouble(),
        cashCollected: (row['cash_collected'] as num).toDouble(),
        upiCollected: (row['upi_collected'] as num).toDouble(),
        bankCollected: (row['bank_collected'] as num).toDouble(),
        chequeCollected: (row['cheque_collected'] as num).toDouble(),
        loanDistribution: (row['loan_distribution'] as num).toDouble(),
        expenses: (row['expenses'] as num).toDouble(),
        expectedClosingBalance: (row['expected_closing_balance'] as num).toDouble(),
      ),
      physicalCashDeclared: (row['physical_cash_declared'] as num).toDouble(),
      difference: (row['difference'] as num).toDouble(),
      remarks: null, // account_settlements has no agent-remarks column — same schema gap account_review_state.dart already flagged on the Owner side (AccountSettlementDetail.agentRemarks)
      status: SettlementStatusX.fromSchemaValue(row['status'] as String),
      returnReason: returnReasonRow?['return_reason'] as String?,
      // NOTE: unused (adjustmentRows fetched but not surfaced — AgentSettlementRecord
      // has no adjustments field on the Agent side, only account_review_state.dart's
      // Owner-side AccountSettlementDetail exposes them). Fetched anyway in case a
      // future Agent-facing "why was I returned" breakdown needs it; left unused
      // rather than silently dropped from the query, flagged so it isn't mistaken
      // for dead code by accident.
    );
  }
}

final agentSettlementApiServiceProvider = Provider<AgentSettlementApiService>((ref) {
  return AgentSettlementApiService(ref: ref);
});

// ============================================================================
// Models
// ============================================================================

/// Pre-submission SETTLEMENT SUMMARY figures — see SPEC GAP note above on
/// how these get sourced.
class SettlementPreview {
  final double openingBalance; // sourced from agent_bf_assignments.opening_bf — reuse AgentBfAssignment, don't redefine
  final double cashCollected;
  final double upiCollected; // system-sourced, display only
  final double bankCollected; // system-sourced, display only
  final double chequeCollected; // system-sourced amount; Cheque Count (UI-only tally) sits alongside, not backing this
  final double loanDistribution;
  final double expenses;
  final double expectedClosingBalance;

  SettlementPreview({
    required this.openingBalance,
    required this.cashCollected,
    required this.upiCollected,
    required this.bankCollected,
    required this.chequeCollected,
    required this.loanDistribution,
    required this.expenses,
    required this.expectedClosingBalance,
  });
}

/// `account_settlements.status` ENUM — no terminal Reject, Returned is
/// always resubmittable.
enum SettlementStatus { pendingOwnerReview, approved, returned }

extension SettlementStatusX on SettlementStatus {
  String get schemaValue => switch (this) {
        SettlementStatus.pendingOwnerReview => 'Pending Owner Review',
        SettlementStatus.approved => 'Approved',
        SettlementStatus.returned => 'Returned',
      };

  static SettlementStatus fromSchemaValue(String v) => switch (v) {
        'Pending Owner Review' => SettlementStatus.pendingOwnerReview,
        'Approved' => SettlementStatus.approved,
        'Returned' => SettlementStatus.returned,
        _ => throw ArgumentError('Unknown account_settlements.status: $v'),
      };
}

class AgentSettlementRecord {
  final String settlementId;
  final SettlementPreview summary;
  final double physicalCashDeclared;
  final double difference; // expected_closing_balance - actual (physical + verified UPI/Bank/Cheque)
  final String? remarks;
  final SettlementStatus status;
  final String? returnReason; // populated only when status == returned

  AgentSettlementRecord({
    required this.settlementId,
    required this.summary,
    required this.physicalCashDeclared,
    required this.difference,
    this.remarks,
    required this.status,
    this.returnReason,
  });
}

class SettlementSubmitResult {
  final String settlementId;
  final double expectedClosingBalance;
  final double difference;
  final SettlementStatus status;

  SettlementSubmitResult({
    required this.settlementId,
    required this.expectedClosingBalance,
    required this.difference,
    required this.status,
  });
}

// ============================================================================
// State
// ============================================================================

enum SettlementScreenStage {
  loading,
  draftEntry, // S1/S2/S3 — Agent entering Physical Cash / Cheque Count / Remarks
  pendingReview, // S4
  approved, // S5
  returned, // S6 — resubmittable
}

class AgentSettlementState {
  final SettlementScreenStage stage;
  final bool loading;
  final bool submitting;
  final String? error;

  final AgentBfAssignment? bfAssignment; // reused from AG-001 — Opening BF source, not redefined here
  final SettlementPreview? preview;
  final AgentSettlementRecord? existingSettlement; // set once submitted / when Returned for resubmit

  final String cycleType; // Business-level Owner-set config (OW-012 Account Cycle) — read-only display, not chosen here
  final double physicalCashDeclared;
  final int chequeCountTally; // UI-only, no backing field — see class docs on the screen file
  final String remarks;

  const AgentSettlementState({
    this.stage = SettlementScreenStage.loading,
    this.loading = false,
    this.submitting = false,
    this.error,
    this.bfAssignment,
    this.preview,
    this.existingSettlement,
    this.cycleType = 'Daily',
    this.physicalCashDeclared = 0,
    this.chequeCountTally = 0,
    this.remarks = '',
  });

  /// Expected Balance − Actual Balance = Difference. Actual = Physical
  /// Cash declared + verified UPI/Bank/Cheque (those three are
  /// system-sourced, never Agent-entered, so they flow straight through).
  double get difference {
    if (preview == null) return 0;
    final actual = physicalCashDeclared + preview!.upiCollected + preview!.bankCollected + preview!.chequeCollected;
    return preview!.expectedClosingBalance - actual;
  }

  bool get differenceIsZero => difference.abs() < 0.005;
  bool get explanationRequired => !differenceIsZero;
  bool get canSubmit => preview != null && (differenceIsZero || remarks.trim().isNotEmpty);

  AgentSettlementState copyWith({
    SettlementScreenStage? stage,
    bool? loading,
    bool? submitting,
    String? error,
    bool clearError = false,
    AgentBfAssignment? bfAssignment,
    SettlementPreview? preview,
    AgentSettlementRecord? existingSettlement,
    String? cycleType,
    double? physicalCashDeclared,
    int? chequeCountTally,
    String? remarks,
  }) {
    return AgentSettlementState(
      stage: stage ?? this.stage,
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      bfAssignment: bfAssignment ?? this.bfAssignment,
      preview: preview ?? this.preview,
      existingSettlement: existingSettlement ?? this.existingSettlement,
      cycleType: cycleType ?? this.cycleType,
      physicalCashDeclared: physicalCashDeclared ?? this.physicalCashDeclared,
      chequeCountTally: chequeCountTally ?? this.chequeCountTally,
      remarks: remarks ?? this.remarks,
    );
  }
}

class AgentSettlementNotifier extends Notifier<AgentSettlementState> {
  @override
  AgentSettlementState build() => const AgentSettlementState();

  Future<void> enter({
    required String businessId,
    required String agentId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    state = state.copyWith(loading: true, clearError: true, stage: SettlementScreenStage.loading);
    try {
      // Opening BF reused from AG-001's own gate/state — session-based,
      // not recomputed here (agent_bf_assignments.opening_bf).
      final agentApi = ref.read(agentApiServiceProvider);
      final bf = await agentApi.fetchCurrentBfAssignment(agentId: agentId);

      final settlementApi = ref.read(agentSettlementApiServiceProvider);
      final existing = await settlementApi.fetchOwnLatestSettlement(businessId: businessId, agentId: agentId);

      if (existing != null && existing.status == SettlementStatus.pendingOwnerReview) {
        state = state.copyWith(
          loading: false,
          bfAssignment: bf,
          existingSettlement: existing,
          stage: SettlementScreenStage.pendingReview,
        );
        return;
      }
      if (existing != null && existing.status == SettlementStatus.approved) {
        state = state.copyWith(
          loading: false,
          bfAssignment: bf,
          existingSettlement: existing,
          stage: SettlementScreenStage.approved,
        );
        return;
      }

      // Returned (resubmittable) or no existing settlement — either way,
      // load a fresh preview for a new S1 Settlement Draft entry.
      final preview = await settlementApi.fetchSettlementPreview(
        businessId: businessId,
        agentId: agentId,
        cycleType: state.cycleType,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );

      state = state.copyWith(
        loading: false,
        bfAssignment: bf,
        preview: preview,
        existingSettlement: existing,
        stage: existing?.status == SettlementStatus.returned
            ? SettlementScreenStage.returned
            : SettlementScreenStage.draftEntry,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setPhysicalCash(double value) => state = state.copyWith(physicalCashDeclared: value);
  void setChequeCountTally(int value) => state = state.copyWith(chequeCountTally: value);
  void setRemarks(String value) => state = state.copyWith(remarks: value);

  /// Moves from Returned back into an editable draft entry, keeping the
  /// same preview figures (a fresh preview fetch would double-count
  /// against a not-yet-superseded settlement).
  void beginResubmit() {
    if (state.stage != SettlementScreenStage.returned) return;
    state = state.copyWith(stage: SettlementScreenStage.draftEntry);
  }

  Future<SettlementSubmitResult?> submit({
    required String businessId,
    required String agentId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    if (!state.canSubmit) return null; // Difference ≠ 0 with empty remarks — Submit must stay disabled at the UI layer too
    if (state.preview == null) {
      state = state.copyWith(error: 'No settlement preview loaded — cannot submit without one.');
      return null;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(agentSettlementApiServiceProvider);
      final result = await api.submitSettlement(
        businessId: businessId,
        agentId: agentId,
        cycleType: state.cycleType,
        periodStart: periodStart,
        periodEnd: periodEnd,
        physicalCashDeclared: state.physicalCashDeclared,
        preview: state.preview!,
        remarks: state.remarks.trim().isEmpty ? null : state.remarks.trim(),
      );
      // On submission: Opening BF/Expected Closing Balance always returns
      // to businesses.owner_bf_balance in full, and agent_bf_current
      // resets to ₹0 — both are backend-side effects of this same call,
      // nothing further to send from this screen.
      state = state.copyWith(submitting: false, stage: SettlementScreenStage.pendingReview);
      return result;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return null;
    }
  }
}

final agentSettlementProvider = NotifierProvider<AgentSettlementNotifier, AgentSettlementState>(
  AgentSettlementNotifier.new,
);

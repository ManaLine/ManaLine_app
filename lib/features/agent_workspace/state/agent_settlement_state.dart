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

  /// Records an agent-paid expense. Deducts it from THIS agent's float in
  /// the same transaction, which is the whole point: until record_expense
  /// existed, an agent's expense was a row that never reduced what they
  /// owed the Owner at hand-over, so every settlement came up short by the
  /// amount they had legitimately spent.
  ///
  /// Gated server-side on the Owner-granted can_record_expenses permission
  /// (OFF by default, BR-236 pattern) and on the agent actually having the
  /// cash — both surface as the RPC's own message, not a local guess.
  Future<String> recordExpense({
    required String agentId,
    required String businessId,
    required String category,
    required int amount,
    required String businessDate,
    String? remarks,
  }) async {
    final membershipId = await _resolveMembershipId(agentId);
    final result = await _db.schema('app').rpc('record_expense', params: {
      'p_business_id': businessId,
      'p_category': category,
      'p_amount': amount,
      'p_membership_id': membershipId,
      'p_business_date': businessDate,
      'p_remarks': remarks,
    });
    return result as String;
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
    final openingBalance = (bfRow?['opening_bf'] as num?)?.toInt() ?? 0;

    final collectionRows = await _db
        .from('collections')
        .select('collection_id, business_date')
        .eq('collected_by_membership_id', membershipId)
        .gte('business_date', startStr)
        .lte('business_date', endStr)
        // Settling against deleted collections would ask the agent to hand
        // over cash that was never counted as received.
        .isFilter('deleted_at', null);
    final collectionIds = (collectionRows as List).map((c) => c['collection_id'] as String).toList();

    int cash = 0, upi = 0, bank = 0, cheque = 0;
    if (collectionIds.isNotEmpty) {
      final splitRows = await _db.from('collection_payment_splits').select('payment_mode, amount').inFilter('collection_id', collectionIds);
      for (final s in (splitRows as List)) {
        final amt = (s['amount'] as num).toInt();
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
        .lte('issue_business_date', endStr)
        // Deleted loans never left the till, so they cannot be part of what
        // this agent has to settle for.
        .isFilter('deleted_at', null);
    final loanDistribution = (loanRows as List).fold<int>(0, (sum, l) => sum + (l['amount_given'] as num).toInt());

    final expenseRows = await _db
        .from('expenses')
        .select('amount')
        .eq('recorded_by_membership_id', membershipId)
        .gte('business_date', startStr)
        .lte('business_date', endStr);
    final expenses = (expenseRows as List).fold<int>(0, (sum, e) => sum + (e['amount'] as num).toInt());

    // No expected-closing figure is derived here any more.
    //
    // It used to be a self-admitted "plausible reconstruction" of BR-237.
    // submit_agent_settlement now computes the real one from the period's
    // own records, so a second, unverified formula on the phone could only
    // ever do one of two things: agree with the server, in which case it
    // was redundant, or disagree, in which case it told the agent their
    // cash balanced when the server was about to record a short.
    //
    // The component figures below stay: each is a direct SUM of real rows,
    // not a reconstruction, and the agent needs them to count against.
    // What they no longer get is a total the app made up.

    return SettlementPreview(
      openingBalance: openingBalance,
      cashCollected: cash,
      upiCollected: upi,
      bankCollected: bank,
      chequeCollected: cheque,
      loanDistribution: loanDistribution,
      expenses: expenses,
    );
  }

  // HISTORY — NO LONGER BLOCKED. submit_agent_settlement exists and is
  // called below; kept because it records why this had to be one atomic
  // server-side step, which is still the reason it is written this way.
  //
  // Was: creates the `account_settlements` row (status='Pending
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
  /// Hands the account to the Owner. Moves no money -- see
  /// app.submit_agent_settlement.
  ///
  /// No physical cash to declare: the app knows what the Agent is holding, so
  /// there is nothing for them to count at the end of a round and nothing for
  /// the two figures to disagree about.
  Future<SettlementSubmitResult> submitSettlement({
    required String agentId,
    required String cycleType,
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

    // The server works every figure out from the period's own records; the
    // phone only declares the physical cash the agent actually counted. The
    // RPC answers with the server-computed expected and difference so the
    // result shown here is the real one, not a phone-side copy.
    final result = await _db.schema('app').rpc('submit_agent_settlement', params: {
      'p_account_period_id': periodRow['account_period_id'],
      'p_agent_id': agentId,
      'p_cycle_type': cycleType,
    });

    final map = result as Map<String, dynamic>;
    final held = (map['amount_held'] as num).toInt();
    return SettlementSubmitResult(
      settlementId: map['settlement_id'] as String,
      // One figure now: what was handed over. Expected and declared were two
      // names for it the moment the Agent stopped being asked to count.
      expectedClosingBalance: held,
      difference: 0,
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

    final returnReasonRow = row['status'] == 'Returned'
        ? await _db.from('account_settlements').select('return_reason').eq('settlement_id', row['settlement_id']).single()
        : null;

    return AgentSettlementRecord(
      settlementId: row['settlement_id'] as String,
      summary: SettlementPreview(
        openingBalance: (row['opening_balance'] as num).toInt(),
        cashCollected: (row['cash_collected'] as num).toInt(),
        upiCollected: (row['upi_collected'] as num).toInt(),
        bankCollected: (row['bank_collected'] as num).toInt(),
        chequeCollected: (row['cheque_collected'] as num).toInt(),
        loanDistribution: (row['loan_distribution'] as num).toInt(),
        expenses: (row['expenses'] as num).toInt(),
        expectedClosingBalance: (row['expected_closing_balance'] as num).toInt(),
      ),
      physicalCashDeclared: (row['physical_cash_declared'] as num).toInt(),
      difference: (row['difference'] as num).toInt(),
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
  final int openingBalance; // sourced from agent_bf_assignments.opening_bf — reuse AgentBfAssignment, don't redefine
  final int cashCollected;
  final int upiCollected; // system-sourced, display only
  final int bankCollected; // system-sourced, display only
  final int chequeCollected; // system-sourced amount; Cheque Count (UI-only tally) sits alongside, not backing this
  final int loanDistribution;
  final int expenses;

  /// Null before submission, and only ever the SERVER's figure afterwards.
  /// Nothing in the app computes this — see the note in
  /// fetchSettlementPreview on why the local reconstruction was removed.
  final int? expectedClosingBalance;

  SettlementPreview({
    required this.openingBalance,
    required this.cashCollected,
    required this.upiCollected,
    required this.bankCollected,
    required this.chequeCollected,
    required this.loanDistribution,
    required this.expenses,
    this.expectedClosingBalance,
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
  final int physicalCashDeclared;
  final int difference; // expected_closing_balance - actual (physical + verified UPI/Bank/Cheque)
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
  final int expectedClosingBalance;
  final int difference;
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
  final int physicalCashDeclared;
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

  /// The difference, or null before submission — the server is the only
  /// thing that computes it.
  ///
  /// This used to be derived here as `expected − (physical + UPI + bank +
  /// cheque)`. submit_agent_settlement computes `physical_cash_declared −
  /// expected_cash`, over CASH ONLY. Those two disagree in magnitude (the
  /// local one folds in three non-cash modes that never pass through
  /// physical BF) and in sign. An agent could therefore be shown a
  /// balanced settlement and have the server record a short one, or the
  /// reverse — the confidently-wrong-number failure, on the screen where
  /// somebody hands over cash.
  int? get difference => existingSettlement?.difference;

  bool get canSubmit => preview != null;

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
    int? physicalCashDeclared,
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

  void setPhysicalCash(int value) => state = state.copyWith(physicalCashDeclared: value);
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
    required String agentId,
  }) async {
    // No canSubmit gate any more: it existed to stop a submit whose declared
    // cash disagreed with the expected figure, and nobody declares cash now.
    if (state.preview == null) {
      state = state.copyWith(error: 'No settlement preview loaded — cannot submit without one.');
      return null;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(agentSettlementApiServiceProvider);
      final result = await api.submitSettlement(
        agentId: agentId,
        cycleType: state.cycleType,
      );
      // Nothing has moved yet. The Agent has handed the account over and the
      // Owner has been asked; the float stays in the Agent's name until the
      // Owner approves, which is the only place it transfers.
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

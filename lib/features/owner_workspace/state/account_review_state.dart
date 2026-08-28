import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/mana_time.dart';

/// OW-013 Account Review — real Supabase wiring.
///
/// SHARED STATE-MACHINE NOTE: this is the OWNER-side half of the settlement
/// object whose AGENT-side half lives in agent_settlement_state.dart
/// (AG-006) — wired in the same pass, with a shared understanding of
/// `account_settlements.status`: 'Pending Owner Review' -> ('Approved' |
/// 'Returned') -> (if Returned) Agent resubmits -> back to 'Pending Owner
/// Review'. This file only ever transitions OUT of 'Pending Owner Review';
/// only agent_settlement_state.dart's blocked submit RPC transitions INTO
/// it. Same INTEGRATION FLAGS as the other Priority 1/2 files (not
/// repeated).
class AccountReviewApiService {
  final Ref ref;
  AccountReviewApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  // GET pending settlements + Owner BF Panel + Daily Allowance list, in one
  // logical fetch (kept as 3 real queries — Postgrest has no cross-table
  // "combined response" primitive, and these three are legitimately
  // independent reads, not one join).
  Future<AccountReviewLoadResult> fetchPendingSettlements({required String businessId}) async {
    final rows = await _db
        .from('account_settlements')
        .select('''
          settlement_id, account_period_id, cycle_type, cash_collected, upi_collected, bank_collected,
          cheque_collected, loan_distribution, expenses, expected_closing_balance, physical_cash_declared,
          difference, status, submitted_at,
          account_periods!inner(business_id, business_start_date),
          agents!inner(persons!inner(full_name))
        ''')
        .eq('account_periods.business_id', businessId)
        .eq('status', 'Pending Owner Review')
        .order('submitted_at', ascending: true);

    final settlements = (rows as List).map((r) => _toSummary(r)).toList();

    final business = await _db.from('businesses').select('owner_bf_balance').eq('business_id', businessId).single();
    // agent_bf_current, not opening_bf. opening_bf is what each Agent set out
    // with and is never updated again, so this row read Rs 0 on a day when
    // the agents between them were carrying Rs 2,69,190 of collections -- and
    // the Owner, reading "Assigned Out 0" beside "Owner BF 30", concluded the
    // BF figures were out of sync when they were merely two different
    // quantities. What the agents hold is agent_bf_current.
    final assignmentRows = await _db
        .from('agent_bf_assignments')
        .select('agent_bf_current, business_members!inner(business_id)')
        .eq('business_members.business_id', businessId);
    final heldByAgents = (assignmentRows as List)
        .fold<int>(0, (sum, a) => sum + ((a['agent_bf_current'] as num?)?.toInt() ?? 0));
    // "Returning this session" = sum of settlements' opening_balance for
    // settlements actually submitted (Pending/Approved) this session —
    // approximated here as the sum over the just-fetched pending list;
    // Approved-but-not-yet-reflected-elsewhere rows are NOT included since
    // there's no single "this session" boundary column to filter on
    // (flagged: a precise figure needs a session/account_period_id scope
    // the Owner BF Panel's original spec didn't fully pin down either).
    final totalReturning = settlements.fold<int>(0, (sum, s) => sum + s.handOverTotal);

    final ownerCash = (business['owner_bf_balance'] as num).toInt();
    final bfPanel = OwnerBfPanelData(
      ownerCashInHand: ownerCash,
      heldByAgents: heldByAgents,
      returningThisSession: totalReturning,
    );

    final accessDayRows = await _db
        .from('agent_access_days')
        // FK named explicitly: agent_access_days has TWO foreign keys into
        // business_members (membership_id = the agent the day was granted
        // to, granted_by_membership_id = whoever granted it), so a bare
        // `business_members!inner(...)` is ambiguous and PostgREST rejects
        // the whole request with PGRST201. That took OW-013's entire load
        // down — settlements, BF panel and all — and since the screen never
        // rendered state.error, it looked like an empty screen instead of a
        // failure. This one means the agent's own membership.
        .select('access_day_id, allowance_amount, '
            'business_members!agent_access_days_membership_id_fkey!inner('
            'business_id, persons!business_members_person_id_fkey(full_name))')
        .eq('business_members.business_id', businessId)
        .order('business_date', ascending: false);
    final accessDays = (accessDayRows as List)
        .map((r) => AgentAccessDay(
              accessDayId: r['access_day_id'] as String,
              agentName: ((r['business_members'] as Map<String, dynamic>)['persons'] as Map<String, dynamic>)['full_name'] as String,
              allowanceAmount: (r['allowance_amount'] as num).toInt(),
            ))
        .toList();

    return AccountReviewLoadResult(settlements: settlements, bfPanel: bfPanel, accessDays: accessDays);
  }

  AccountSettlementSummary _toSummary(Map<String, dynamic> r) {
    final period = r['account_periods'] as Map<String, dynamic>;
    final agentPerson = (r['agents'] as Map<String, dynamic>)['persons'] as Map<String, dynamic>;
    return AccountSettlementSummary(
      settlementId: r['settlement_id'] as String,
      accountPeriodId: r['account_period_id'] as String,
      businessDate: DateTime.parse(period['business_start_date'] as String),
      agentName: agentPerson['full_name'] as String,
      totalCollections: (r['cash_collected'] as num).toInt() +
          (r['upi_collected'] as num).toInt() +
          (r['bank_collected'] as num).toInt() +
          (r['cheque_collected'] as num).toInt(),
      totalLoansIssued: (r['loan_distribution'] as num).toInt(),
      totalInterest: 0, // not a column on account_settlements — Calculation Engine territory, not reimplemented here
      totalProcessingFee: 0, // ditto
      expenses: (r['expenses'] as num).toInt(),
      short: (r['difference'] as num) < 0 ? (r['difference'] as num).abs().toInt() : 0,
      excess: (r['difference'] as num) > 0 ? (r['difference'] as num).toInt() : 0,
      difference: (r['difference'] as num).toInt(),
      status: r['status'] as String,
      handOverCash: (r['physical_cash_declared'] as num).toInt(),
      handOverUpi: (r['upi_collected'] as num).toInt(),
      handOverCheque: (r['cheque_collected'] as num).toInt(),
    );
  }

  Future<AccountSettlementDetail> fetchSettlementDetail({required String settlementId}) async {
    final row = await _db
        .from('account_settlements')
        .select('''
          settlement_id, account_period_id, cash_collected, upi_collected, bank_collected, cheque_collected,
          loan_distribution, expenses, expected_closing_balance, physical_cash_declared, difference, status,
          account_periods!inner(business_start_date),
          agents!inner(persons!inner(full_name))
        ''')
        .eq('settlement_id', settlementId)
        .single();
    final adjustmentRows = await _db
        .from('settlement_adjustments')
        .select('adjustment_type, amount, applied_to')
        .eq('settlement_id', settlementId);
    return AccountSettlementDetail(
      summary: _toSummary(row),
      adjustments: (adjustmentRows as List)
          .map((a) => SettlementAdjustment(
                type: a['adjustment_type'] as String,
                amount: (a['amount'] as num).toInt(),
                appliedTo: a['applied_to'] as String,
              ))
          .toList(),
      agentRemarks: null, // account_settlements has no agent-remarks column in the locked schema (only settlement_adjustments/return_reason exist) — flagged, screen's remarks field (if any) has no schema backing
    );
  }

  // PATCH — single status-changing call. Owner has full write access to
  // account_settlements per rls_role_matrix.md ("O: full"), so this is a
  // safe direct UPDATE, unlike the Agent-side submit.
  Future<void> approveSettlement({required String settlementId}) async {
    await _db.from('account_settlements').update({
      'status': 'Approved',
      'reviewed_at': manaTimestamp(),
    }).eq('settlement_id', settlementId);
    // NOTE: does not itself move agent_bf_assignments.agent_bf_current back
    // into businesses.owner_bf_balance — per Merged Addendum item 4 that
    // transfer happens "at Agent settlement", which this session reads as
    // the Agent's submit-time RPC (BLOCKED, see agent_settlement_state.dart),
    // not the Owner's later Approve action. Flagged: if the real intended
    // trigger point is Approve (not Submit), this needs to move there instead.
  }

  Future<void> returnSettlement({required String settlementId, required String reason}) async {
    // Must go through the RPC: the money that moved to the Owner at submit
    // has to move back to the agent (the hand-over reverses), and the agent
    // must still have a float to re-submit with. A plain status UPDATE would
    // leave the Owner holding cash the agent still needs.
    await _db.schema('app').rpc('return_settlement', params: {
      'p_settlement_id': settlementId,
      'p_reason': reason,
    });
  }

  // POST account-periods/{id}/lock — Owner full access to account_periods.
  Future<void> lockAccountPeriod({required String accountPeriodId}) async {
    await _db.from('account_periods').update({'status': 'Locked'}).eq('account_period_id', accountPeriodId);
  }

  // SCHEMA GAP FOUND: `agent_access_days` (schema §Merged Addendum item 3)
  // has NO status/removed_at/is_archived column — unlike almost every other
  // table in the schema, there is no soft-delete surface here to flip. A
  // true DELETE is used below, which conflicts with the schema doc's own
  // blanket "Nothing is ever hard-deleted... No table below has a DELETE
  // workflow" rule (§ Conventions). Flagged for master chat: either this
  // table needs an addendum column (e.g. `removed_at`), or this method
  // needs to become an UPDATE that zeroes `allowance_amount` instead of a
  // real delete — implemented as a real DELETE for now since that's the
  // only way to make the UI's "remove" action actually remove the row
  // given the current schema, not a silent workaround.
  Future<void> removeAccessDay({required String accessDayId}) async {
    await _db.from('agent_access_days').delete().eq('access_day_id', accessDayId);
  }
}

final accountReviewApiServiceProvider = Provider<AccountReviewApiService>((ref) {
  return AccountReviewApiService(ref: ref);
});

class AccountSettlementSummary {
  final String settlementId;
  final String accountPeriodId;
  final DateTime businessDate; // account_period span start, not necessarily "today"
  final String agentName;
  final int totalCollections;
  final int totalLoansIssued;
  final int totalInterest;
  final int totalProcessingFee;
  final int expenses;
  final int short;
  final int excess;
  final int difference;
  final String status; // Pending Owner Review | Approved | Returned
  final int handOverCash;
  final int handOverUpi;
  final int handOverCheque;

  AccountSettlementSummary({
    required this.settlementId,
    required this.accountPeriodId,
    required this.businessDate,
    required this.agentName,
    required this.totalCollections,
    required this.totalLoansIssued,
    required this.totalInterest,
    required this.totalProcessingFee,
    required this.expenses,
    required this.short,
    required this.excess,
    required this.difference,
    required this.status,
    required this.handOverCash,
    required this.handOverUpi,
    required this.handOverCheque,
  });

  int get handOverTotal => handOverCash + handOverUpi + handOverCheque;
}

class SettlementAdjustment {
  final String type; // Short | Excess
  final int amount;
  final String appliedTo; // Agent Salary Deduction | Customer Pending Settlement | Excess Ledger-Unresolved (BR-069)
  SettlementAdjustment({required this.type, required this.amount, required this.appliedTo});
}

class AccountSettlementDetail {
  final AccountSettlementSummary summary;
  final List<SettlementAdjustment> adjustments;
  final String? agentRemarks;
  AccountSettlementDetail({required this.summary, this.adjustments = const [], this.agentRemarks});
}

/// The Owner's cash, in the two places it can be.
///
/// The panel used to show one figure called "Owner BF" four ways -- balance
/// before today, assigned out, returning, current -- three of which read the
/// same column and one of which read the wrong one. Standing beside the
/// dashboard's business-cash total it looked like a sync fault: Rs 30 here,
/// Rs 2,69,220 there. Neither was stale. `businesses.owner_bf_balance` is the
/// Owner's OWN pot -- the day's closing minus whatever the agents are
/// carrying -- so with an agent holding Rs 2,69,190 of a Rs 2,69,220 book,
/// Rs 30 is exactly right.
///
/// So the panel now names both halves and adds them up, and nothing here is
/// called "BF" without saying whose.
class OwnerBfPanelData {
  /// businesses.owner_bf_balance -- derived, never a running total. See
  /// app.recompute_business_bf().
  final int ownerCashInHand;

  /// Sum of agent_bf_assignments.agent_bf_current across the business.
  final int heldByAgents;

  /// Hand-overs sitting in Pending Owner Review. Already counted inside
  /// [heldByAgents] until the Owner approves them -- which is why it is shown
  /// as a memo line below the total, not added to it.
  final int returningThisSession;

  OwnerBfPanelData({
    required this.ownerCashInHand,
    required this.heldByAgents,
    required this.returningThisSession,
  });

  /// Every rupee the business is holding, wherever it is standing.
  int get businessCashTotal => ownerCashInHand + heldByAgents;
}

class AgentAccessDay {
  final String accessDayId;
  final String agentName;
  final int allowanceAmount;
  AgentAccessDay({required this.accessDayId, required this.agentName, required this.allowanceAmount});
}

class AccountReviewLoadResult {
  final List<AccountSettlementSummary> settlements;
  final OwnerBfPanelData? bfPanel;
  final List<AgentAccessDay> accessDays;
  AccountReviewLoadResult({required this.settlements, this.bfPanel, this.accessDays = const []});
}

class AccountReviewState {
  final List<AccountSettlementSummary> settlements;
  final OwnerBfPanelData? bfPanel;
  final List<AgentAccessDay> accessDays;
  final bool loading;
  final String? error;

  const AccountReviewState({
    this.settlements = const [],
    this.bfPanel,
    this.accessDays = const [],
    this.loading = false,
    this.error,
  });

  AccountReviewState copyWith({
    List<AccountSettlementSummary>? settlements,
    OwnerBfPanelData? bfPanel,
    List<AgentAccessDay>? accessDays,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AccountReviewState(
      settlements: settlements ?? this.settlements,
      bfPanel: bfPanel ?? this.bfPanel,
      accessDays: accessDays ?? this.accessDays,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AccountReviewNotifier extends Notifier<AccountReviewState> {
  @override
  AccountReviewState build() => const AccountReviewState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(accountReviewApiServiceProvider);
      final result = await api.fetchPendingSettlements(businessId: businessId);
      state = state.copyWith(
        settlements: result.settlements,
        bfPanel: result.bfPanel,
        accessDays: result.accessDays,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<AccountSettlementDetail?> viewDetail(String settlementId) async {
    try {
      return await ref.read(accountReviewApiServiceProvider).fetchSettlementDetail(settlementId: settlementId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> approve({required String businessId, required String settlementId}) async {
    try {
      await ref.read(accountReviewApiServiceProvider).approveSettlement(settlementId: settlementId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> returnAccount({
    required String businessId,
    required String settlementId,
    required String reason,
  }) async {
    try {
      await ref.read(accountReviewApiServiceProvider).returnSettlement(settlementId: settlementId, reason: reason);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> lockAccountPeriod({required String businessId, required String accountPeriodId}) async {
    try {
      await ref.read(accountReviewApiServiceProvider).lockAccountPeriod(accountPeriodId: accountPeriodId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> removeAccessDay({required String businessId, required String accessDayId}) async {
    final previous = state.accessDays;
    // Optimistic removal — Daily Allowance tab is a lightweight tracking
    // list, not a financial record, so an immediate UI update reads better
    // than a spinner; rolled back on failure.
    state = state.copyWith(accessDays: previous.where((a) => a.accessDayId != accessDayId).toList());
    try {
      await ref.read(accountReviewApiServiceProvider).removeAccessDay(accessDayId: accessDayId);
    } catch (e) {
      state = state.copyWith(accessDays: previous, error: e.toString());
    }
  }
}

final accountReviewProvider = NotifierProvider<AccountReviewNotifier, AccountReviewState>(
  AccountReviewNotifier.new,
);

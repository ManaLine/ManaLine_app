import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// AG-001 Agent Home Dashboard — real Supabase wiring. Per the spec's own
/// API BINDING, there is no persisted "session" object — Business Session
/// is the Agent-facing presentation of one or more `account_periods` rows.
///
/// Same INTEGRATION FLAGS as owner_api_service.dart (Supabase.initialize
/// timing, personId String->BIGINT parsing), not repeated in full.
///
/// PARAM-NAMING GAP FOUND: every method here takes `agentId`, but the real
/// schema has TWO different identifiers that both plausibly mean "this
/// Agent": `agents.agent_id` (what `agent_area_assignments`,
/// `agent_permissions`, `agent_compensation_history` key on) and
/// `business_members.membership_id` (what `agent_bf_assignments` and
/// `account_periods.agent_membership_id` key on instead). This file treats
/// every `agentId` param as `agents.agent_id` (the more natural reading of
/// the name) and resolves `membership_id` internally via one extra lookup
/// query wherever a BF/account_periods table needs it — flagged because if
/// AG-001's screen is actually passing `business_members.membership_id`
/// today, `_resolveMembershipId` below will silently do a second lookup
/// that just returns the same value back (harmless but wasteful) OR — if
/// the screen is passing something else entirely — will throw a clear
/// "not found" error rather than fail silently.
class AgentApiService {
  final Ref ref;
  AgentApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  int get _personId {
    final id = ref.read(authFlowProvider).personId;
    if (id == null) throw StateError('No logged-in person_id available.');
    return int.parse(id);
  }

  Future<String> _resolveMembershipId(String agentId) async {
    final row = await _db.from('agents').select('membership_id').eq('agent_id', agentId).single();
    return row['membership_id'] as String;
  }

  // GET current agent_bf_assignments row — RLS (rls_role_matrix.md:
  // "agent_bf_assignments — A: SELECT own rows only") already scopes this
  // to the caller's own row; ordered by created_at so the latest session's
  // assignment wins if more than one exists (business_date OR
  // account_period_id keys the session per schema comment).
  Future<AgentBfAssignment?> fetchCurrentBfAssignment({required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    final rows = await _db
        .from('agent_bf_assignments')
        .select('assignment_id, opening_bf, confirmed_by_agent, update_requested')
        .eq('membership_id', membershipId)
        .order('created_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final r = rows.first;
    return AgentBfAssignment(
      bfAssignmentId: r['assignment_id'] as String,
      openingBf: (r['opening_bf'] as num).toDouble(),
      confirmedByAgent: r['confirmed_by_agent'] as bool,
      updateRequested: r['update_requested'] as bool,
    );
  }

  // BLOCKED ON RPC: rls_role_matrix.md is explicit here — "agent_bf_
  // assignments: ... No Agent UPDATE — session-start confirmation
  // (confirmed_by_agent/update_requested) should go through a SECURITY
  // DEFINER RPC, not a raw column-scoped UPDATE grant." This is not a
  // judgment call being made in this session — RLS as delivered has NO
  // Agent UPDATE policy on this table at all, so a direct `.update()` call
  // would fail with an RLS-denied error every time, not just be
  // architecturally undesirable. Stubbed per the same "flag, don't fake"
  // instruction as the BF Cash Validation / Salary Formula / Settlement
  // math blockers.
  //
  // Expected once built: supabase.rpc('confirm_bf_assignment', params: {
  //   'p_assignment_id': bfAssignmentId,
  // })
  // FIXED (this pass): app.confirm_bf_assignment RPC now exists (migration
  // 0022), closing the block described above. p_membership_id, not
  // p_assignment_id — the RPC resolves the caller's own latest
  // agent_bf_assignments row internally rather than taking a specific
  // assignment_id, so bfAssignmentId is no longer needed here but the
  // param is kept in the method signature (unused) rather than changing
  // callers — flag if a cleanup pass wants to drop it later.
  Future<void> confirmBfAssignment({required String bfAssignmentId, required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.rpc('confirm_bf_assignment', params: {'p_membership_id': membershipId});
  }

  // FIXED (this pass): app.request_bf_update RPC now exists (migration 0022).
  Future<void> requestBfUpdate({required String bfAssignmentId, required String agentId, String? note}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.rpc('request_bf_update', params: {'p_membership_id': membershipId, 'p_note': note});
  }

  // GET Owner-enabled Operating Areas assigned to this Agent.
  Future<List<AgentAreaAssignment>> fetchAreaAssignments({required String agentId}) async {
    final rows = await _db
        .from('agent_area_assignments')
        .select('''
          operating_area_id,
          operating_areas!inner(status, locations!inner(village_town_name))
        ''')
        .eq('agent_id', agentId)
        .isFilter('removed_at', null);
    return (rows as List).map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>;
      final location = area['locations'] as Map<String, dynamic>;
      return AgentAreaAssignment(
        operatingAreaId: r['operating_area_id'] as String,
        areaName: (location['village_town_name'] as String?) ?? '',
        enabled: area['status'] == 'Active',
      );
    }).toList();
  }

  // GET this Agent's currently Running account_periods rows — one per
  // Operating Area, per the "Operating Areas Never Share Account Periods"
  // rule (OW-012), read via `account_periods_agent_select` (0013 RLS:
  // Agent SELECT scoped to agent_membership_id = own). This is the real
  // source of truth for "is a Business Session currently running" — BUG
  // FIXED this pass: the previous version of this file checked
  // `state.runningPeriods.isNotEmpty` in `_loadAreasAndDashboard` but
  // nothing anywhere ever populated `runningPeriods`, so that check was
  // always false and the dashboard could never leave S1 Area Selection
  // even after a session had actually been started via the
  // `start_business_session` RPC. This method + the updated
  // `_loadAreasAndDashboard` below close that gap.
  Future<List<AgentAccountPeriodSummary>> fetchRunningAccountPeriods({required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    final rows = await _db
        .from('account_periods')
        .select('''
          operating_area_id, business_start_date, planned_business_end_date, status,
          operating_areas!inner(locations!inner(village_town_name))
        ''')
        .eq('agent_membership_id', membershipId)
        .eq('status', 'Running');
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>;
      final location = area['locations'] as Map<String, dynamic>;
      return AgentAccountPeriodSummary(
        operatingAreaId: r['operating_area_id'] as String,
        areaName: (location['village_town_name'] as String?) ?? '',
        businessStartDate: DateTime.parse(r['business_start_date'] as String),
        plannedBusinessEndDate: DateTime.parse(r['planned_business_end_date'] as String),
        status: r['status'] as String,
      );
    }).toList();
  }

  // BLOCKED ON RPC: rls_role_matrix.md, `account_periods` — "No client
  // INSERT/UPDATE for Agent — submission must go through a SECURITY
  // DEFINER RPC." Same non-optional RLS constraint as the BF methods
  // above — creating one account_periods row per selected area, all
  // sharing business_start_date, is also a small multi-row atomic write
  // (per-area rows must all get the identical business_start_date or the
  // "Operating Areas Never Share Account Periods" invariant this class's
  // own doc comment describes gets subtly violated by a partial failure
  // partway through a client-side loop of inserts).
  //
  // Expected: supabase.rpc('start_business_session', params: {
  //   'p_agent_membership_id': <resolved via _resolveMembershipId(agentId)>,
  //   'p_operating_area_ids': operatingAreaIds,
  // })
  // FIXED (this pass): app.start_business_session RPC now exists (migration
  // 0022), taking p_area_ids as a UUID[] array — all rows created
  // atomically with one shared business_start_date, closing the exact
  // partial-failure concern described above.
  Future<void> startBusinessSession({
    required String agentId,
    required List<String> operatingAreaIds,
  }) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.rpc('start_business_session', params: {
      'p_membership_id': membershipId,
      'p_area_ids': operatingAreaIds,
    });
  }

  // FIXED (this pass): app.add_area_to_session RPC now exists (migration 0022).
  Future<void> addAreaToSession({required String agentId, required String operatingAreaId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.rpc('add_area_to_session', params: {
      'p_membership_id': membershipId,
      'p_area_id': operatingAreaId,
    });
  }

  // FIXED (this pass): app.remove_area_from_session RPC now exists
  // (migration 0022) — per that RPC's own doc comment, it deliberately
  // does NOT modify account_periods (the row keeps running to its own end
  // date); this call only produces the required audit_log entry. The
  // client is responsible for no longer presenting this area as part of
  // the active working set — handled by refreshDashboard/
  // fetchRunningAccountPeriods re-deriving state after this call.
  Future<void> removeAreaFromSession({required String agentId, required String operatingAreaId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.rpc('remove_area_from_session', params: {
      'p_membership_id': membershipId,
      'p_area_id': operatingAreaId,
    });
  }

  // GET aggregate Agent dashboard.
  //
  // KNOWN SIMPLIFICATION (flagged, same reasoning as owner_api_service.dart's
  // fetchDashboard): rebuilt from direct reads rather than one server-side
  // aggregate. Fields requiring the Calculation Engine or a "today" cutoff
  // this session couldn't safely define without a shared business_date
  // source (account_periods vs local device clock — BR-194 removed Daily
  // Lock specifically so these can legitimately differ) are defaulted to 0
  // / empty, inline-flagged below, not approximated.
  Future<AgentDashboardData> fetchDashboard({
    required String businessId,
    required String agentId,
    DateTime? businessDate,
  }) async {
    final membershipId = await _resolveMembershipId(agentId);

    final business = await _db.from('businesses').select('business_name, owner_person_id').eq('business_id', businessId).single();
    final owner = await _db.from('persons').select('full_name').eq('person_id', business['owner_person_id']).single();

    final membershipRow = await _db
        .from('business_members')
        .select('membership_status')
        .eq('membership_id', membershipId)
        .single();

    final permRow = await _db.from('agent_permissions').select().eq('agent_id', agentId).order('updated_at', ascending: false).limit(1).maybeSingle();
    final visibleActions = <String>{};
    if (permRow != null) {
      for (final entry in permRow.entries) {
        if (entry.value == true) visibleActions.add(entry.key as String);
      }
    }

    final assignedLoans = await _db
        .from('loans')
        .select('loan_status, remaining_balance')
        .eq('collection_agent_membership_id', membershipId)
        .inFilter('loan_status', ['Active', 'Grace Period', 'Penalty']);
    final customersAssignedCount = await _db
        .from('customers')
        .select('customer_id')
        .eq('assigned_agent_membership_id', membershipId);

    final pendingDrafts = await _db.from('collection_drafts').select('draft_id').eq('created_by_membership_id', membershipId).eq('status', 'Draft');

    final pendingSettlementRows = await _db
        .from('account_settlements')
        .select('settlement_id')
        .eq('agent_id', agentId)
        .eq('status', 'Pending Owner Review')
        .limit(1);

    final compHistory = await _db
        .from('agent_compensation_history')
        .select('fixed_salary_amount, salary_cycle, daily_allowance, profit_share_percent')
        .eq('agent_id', agentId)
        .isFilter('superseded_at', null)
        .maybeSingle();

    final routeRow = await _db.from('routes').select('route_name').eq('default_agent_id', membershipId).limit(1).maybeSingle();

    return AgentDashboardData(
      // BUG FIXED this pass: previously hardcoded DateTime.now() with a
      // comment saying the real source "isn't in scope at call time" —
      // it now is, via fetchRunningAccountPeriods() feeding this param
      // from the Notifier (see _loadAreasAndDashboard/refreshDashboard
      // below). Device clock is kept only as the last-resort fallback
      // for the edge case where fetchDashboard is somehow called before
      // any Running period exists.
      businessDate: businessDate ?? DateTime.now(),
      assignedRoute: (routeRow?['route_name'] as String?) ?? '',
      pendingDraftsCount: (pendingDrafts as List).length,
      pendingSettlement: (pendingSettlementRows as List).isNotEmpty,
      todaysTarget: 0, // requires loan_schedule due-today sum — same gap as collection_mode_state.dart's fetchDueList
      customersAssigned: (customersAssignedCount as List).length,
      customersVisited: 0, // requires today-scoped collections/no_collection_visits count — deferred, same "today" cutoff caveat as above
      collectionsCash: 0,
      collectionsUpi: 0,
      collectionsBank: 0,
      collectionsCheque: 0,
      collectionsMixed: 0,
      loansIssued: 0, // today-scoped — deferred
      pendingCollections: (assignedLoans as List).length,
      skippedCustomers: 0,
      shortAmount: 0, // Settlement Short/Excess math — Calculation Engine territory, not reimplemented here
      excessAmount: 0,
      visibleQuickActions: visibleActions,
      liveActivity: const [], // deferred, same reasoning as owner_api_service.dart
      businessName: business['business_name'] as String,
      ownerName: owner['full_name'] as String,
      membershipStatus: membershipRow['membership_status'] as String,
      permissionProfile: visibleActions.isEmpty ? 'Restricted' : 'Custom',
      lastSync: DateTime.now(),
      pendingCustomerRequests: 0, // membership_requests targeting this Agent isn't a modeled relationship (requests target the Owner/business) — 0 is structurally correct, not a placeholder
      pendingExtensionRequests: 0, // deferred: would need a second query scoped to this agent's assigned customers' loans
      pendingRouteChanges: 0,
      pendingMessages: 0,
      fixedSalary: (compHistory?['fixed_salary_amount'] as num?)?.toDouble() ?? 0,
      salaryCycleStatus: (compHistory?['salary_cycle'] as String?) ?? '',
      dailyAllowance: (compHistory?['daily_allowance'] as num?)?.toDouble() ?? 0,
      profitSharePercent: (compHistory?['profit_share_percent'] as num?)?.toDouble(),
      advancesDeducted: 0, // Salary Formula territory (BLOCKED RPC, per briefing) — not reimplemented client-side
      shortsDeducted: 0,
      pendingSalary: 0,
      salaryHistory: const [],
    );
  }
}

final agentApiServiceProvider = Provider<AgentApiService>((ref) {
  return AgentApiService(ref: ref);
});

// ============================================================================
// Models
// ============================================================================

class AgentBfAssignment {
  final String bfAssignmentId;
  final double openingBf;
  final bool confirmedByAgent;
  final bool updateRequested;

  AgentBfAssignment({
    required this.bfAssignmentId,
    required this.openingBf,
    this.confirmedByAgent = false,
    this.updateRequested = false,
  });
}

class AgentAreaAssignment {
  final String operatingAreaId;
  final String areaName;
  final bool enabled; // agent_area_assignments joined against operating_areas.status = 'Active'
  final bool selectedInSession; // client-side: currently part of the running Business Session

  AgentAreaAssignment({
    required this.operatingAreaId,
    required this.areaName,
    this.enabled = true,
    this.selectedInSession = false,
  });

  AgentAreaAssignment copyWith({bool? selectedInSession}) => AgentAreaAssignment(
        operatingAreaId: operatingAreaId,
        areaName: areaName,
        enabled: enabled,
        selectedInSession: selectedInSession ?? this.selectedInSession,
      );
}

/// One row per selected Operating Area's `account_periods` entry — per the
/// locked "Operating Areas Never Share Account Periods" rule (OW-012).
class AgentAccountPeriodSummary {
  final String operatingAreaId;
  final String areaName;
  final DateTime businessStartDate;
  final DateTime plannedBusinessEndDate;
  final String status; // Running | Submitted | Locked

  AgentAccountPeriodSummary({
    required this.operatingAreaId,
    required this.areaName,
    required this.businessStartDate,
    required this.plannedBusinessEndDate,
    required this.status,
  });
}

class AgentLiveActivityEntry {
  final String kind; // Collection Received | Loan Issued | Draft Saved | ...
  final String description;
  final DateTime at;
  AgentLiveActivityEntry({required this.kind, required this.description, required this.at});
}

class AgentDashboardData {
  // Business Status
  final DateTime businessDate;
  final String assignedRoute;
  final int pendingDraftsCount;
  final bool pendingSettlement;
  final double todaysTarget;

  // Today Summary
  final int customersAssigned;
  final int customersVisited;
  final double collectionsCash;
  final double collectionsUpi;
  final double collectionsBank;
  final double collectionsCheque;
  final double collectionsMixed;
  final int loansIssued;
  final int pendingCollections;
  final int skippedCustomers;
  final double shortAmount;
  final double excessAmount;

  // Quick Actions visibility (agent_permissions)
  final Set<String> visibleQuickActions;

  final List<AgentLiveActivityEntry> liveActivity;

  // Workspace Information
  final String businessName;
  final String ownerName;
  final String membershipStatus;
  final String permissionProfile;
  final DateTime lastSync;

  // Attention Required
  final int pendingCustomerRequests;
  final int pendingExtensionRequests;
  final int pendingRouteChanges;
  final int pendingMessages;

  // My Compensation (Read-Only, Set By Owner) — per AG-001 spec section of
  // the same name; AG-009 Profile links out to this panel rather than
  // duplicating it. All Owner-set, no Agent edit affordance anywhere.
  final double fixedSalary;
  final String salaryCycleStatus; // e.g. "Daily" / "Weekly" / "Monthly" + current-cycle status
  final double dailyAllowance;
  final double? profitSharePercent; // null when not enabled for this Agent
  final double advancesDeducted;
  final double shortsDeducted;
  final double pendingSalary;
  final List<AgentSalaryHistoryEntry> salaryHistory;

  AgentDashboardData({
    required this.businessDate,
    required this.assignedRoute,
    required this.pendingDraftsCount,
    required this.pendingSettlement,
    required this.todaysTarget,
    required this.customersAssigned,
    required this.customersVisited,
    required this.collectionsCash,
    required this.collectionsUpi,
    required this.collectionsBank,
    required this.collectionsCheque,
    required this.collectionsMixed,
    required this.loansIssued,
    required this.pendingCollections,
    required this.skippedCustomers,
    required this.shortAmount,
    required this.excessAmount,
    required this.visibleQuickActions,
    required this.liveActivity,
    required this.businessName,
    required this.ownerName,
    required this.membershipStatus,
    required this.permissionProfile,
    required this.lastSync,
    required this.pendingCustomerRequests,
    required this.pendingExtensionRequests,
    required this.pendingRouteChanges,
    required this.pendingMessages,
    this.fixedSalary = 0,
    this.salaryCycleStatus = '',
    this.dailyAllowance = 0,
    this.profitSharePercent,
    this.advancesDeducted = 0,
    this.shortsDeducted = 0,
    this.pendingSalary = 0,
    this.salaryHistory = const [],
  });

  int get customersRemaining => customersAssigned - customersVisited;
  double get todaysCollectionsTotal =>
      collectionsCash + collectionsUpi + collectionsBank + collectionsCheque + collectionsMixed;
}

class AgentSalaryHistoryEntry {
  final DateTime paidOn;
  final double amount;
  final String cycleLabel; // e.g. "Jul 2026" or "Week of 14 Jul"
  AgentSalaryHistoryEntry({required this.paidOn, required this.amount, required this.cycleLabel});
}

// ============================================================================
// State
// ============================================================================

enum AgentSessionStage {
  loadingGate, // checking BF assignment
  bfBlockedNoAssignment, // no agent_bf_assignments row — access not yet granted
  bfConfirmPending, // gate shown, awaiting Confirm/Update
  bfUpdateRequested, // Agent disputed — blocked until Owner corrects
  areaSelection, // S1 — no active session
  running, // S2 — session running, dashboard populated
}

class AgentDashboardState {
  final AgentSessionStage stage;
  final bool loading;
  final String? error;

  final AgentBfAssignment? bfAssignment;
  final List<AgentAreaAssignment> areaAssignments;
  final List<AgentAccountPeriodSummary> runningPeriods;
  final bool hasPendingUnsavedTransactions; // gates Change Area (S3)

  final AgentDashboardData? dashboard;

  const AgentDashboardState({
    this.stage = AgentSessionStage.loadingGate,
    this.loading = false,
    this.error,
    this.bfAssignment,
    this.areaAssignments = const [],
    this.runningPeriods = const [],
    this.hasPendingUnsavedTransactions = false,
    this.dashboard,
  });

  List<AgentAreaAssignment> get enabledAreas => areaAssignments.where((a) => a.enabled).toList();
  List<AgentAreaAssignment> get selectedAreas => areaAssignments.where((a) => a.selectedInSession).toList();
  bool get canStartSession => selectedAreas.isNotEmpty;

  AgentDashboardState copyWith({
    AgentSessionStage? stage,
    bool? loading,
    String? error,
    bool clearError = false,
    AgentBfAssignment? bfAssignment,
    List<AgentAreaAssignment>? areaAssignments,
    List<AgentAccountPeriodSummary>? runningPeriods,
    bool? hasPendingUnsavedTransactions,
    AgentDashboardData? dashboard,
  }) {
    return AgentDashboardState(
      stage: stage ?? this.stage,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      bfAssignment: bfAssignment ?? this.bfAssignment,
      areaAssignments: areaAssignments ?? this.areaAssignments,
      runningPeriods: runningPeriods ?? this.runningPeriods,
      hasPendingUnsavedTransactions: hasPendingUnsavedTransactions ?? this.hasPendingUnsavedTransactions,
      dashboard: dashboard ?? this.dashboard,
    );
  }
}

class AgentDashboardNotifier extends Notifier<AgentDashboardState> {
  @override
  AgentDashboardState build() => const AgentDashboardState();

  /// Entry sequence: BF Confirm/Update gate first, then Area Selection or
  /// Running dashboard — per AG-001's ENTRY POINT + OPENING BF GATE order.
  Future<void> enter({required String agentId, required String businessId}) async {
    state = state.copyWith(loading: true, clearError: true, stage: AgentSessionStage.loadingGate);
    try {
      final api = ref.read(agentApiServiceProvider);
      final bf = await api.fetchCurrentBfAssignment(agentId: agentId);

      if (bf == null) {
        state = state.copyWith(loading: false, stage: AgentSessionStage.bfBlockedNoAssignment);
        return;
      }
      if (bf.updateRequested) {
        state = state.copyWith(loading: false, bfAssignment: bf, stage: AgentSessionStage.bfUpdateRequested);
        return;
      }
      if (!bf.confirmedByAgent) {
        state = state.copyWith(loading: false, bfAssignment: bf, stage: AgentSessionStage.bfConfirmPending);
        return;
      }

      await _loadAreasAndDashboard(agentId: agentId, businessId: businessId, bf: bf);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> _loadAreasAndDashboard({
    required String agentId,
    required String businessId,
    AgentBfAssignment? bf,
  }) async {
    final api = ref.read(agentApiServiceProvider);
    final areas = await api.fetchAreaAssignments(agentId: agentId);
    // BUG FIXED this pass: this used to check `state.runningPeriods
    // .isNotEmpty`, but nothing ever populated that list, so a session
    // could never be detected as running. Now actually queried.
    final runningPeriods = await api.fetchRunningAccountPeriods(agentId: agentId);
    final runningAreaIds = runningPeriods.map((p) => p.operatingAreaId).toSet();
    final markedAreas = areas
        .map((a) => a.copyWith(selectedInSession: runningAreaIds.contains(a.operatingAreaId)))
        .toList();

    if (runningPeriods.isNotEmpty) {
      // Business Date is controlled by the running account_period, not
      // the device clock (AG-001 "Business Date controls all financial
      // entries"). Multiple areas share one business_start_date per
      // session (AG-001's own DATA MODEL note), so any one of them is
      // representative — earliest taken defensively in case of drift.
      final businessDate =
          runningPeriods.map((p) => p.businessStartDate).reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(
        loading: false,
        bfAssignment: bf,
        areaAssignments: markedAreas,
        runningPeriods: runningPeriods,
        dashboard: dashboard,
        stage: AgentSessionStage.running,
      );
    } else {
      state = state.copyWith(
        loading: false,
        bfAssignment: bf,
        areaAssignments: markedAreas,
        runningPeriods: runningPeriods,
        stage: AgentSessionStage.areaSelection,
      );
    }
  }

  Future<bool> confirmBf({required String agentId, required String businessId}) async {
    if (state.bfAssignment == null) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.confirmBfAssignment(bfAssignmentId: state.bfAssignment!.bfAssignmentId, agentId: agentId);
      await _loadAreasAndDashboard(
        agentId: agentId,
        businessId: businessId,
        bf: AgentBfAssignment(
          bfAssignmentId: state.bfAssignment!.bfAssignmentId,
          openingBf: state.bfAssignment!.openingBf,
          confirmedByAgent: true,
        ),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// SIGNATURE CHANGE (this pass): now requires agentId — the underlying
  /// requestBfUpdate RPC call needs it to resolve membership_id. Updated
  /// the one screen call site (ag_001_agent_home_dashboard.dart's _update)
  /// to pass widget.agentId, which was already in scope there.
  Future<bool> disputeBf({required String agentId}) async {
    if (state.bfAssignment == null) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.requestBfUpdate(bfAssignmentId: state.bfAssignment!.bfAssignmentId, agentId: agentId);
      state = state.copyWith(stage: AgentSessionStage.bfUpdateRequested);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void toggleAreaSelection(String operatingAreaId, bool selected) {
    final updated = state.areaAssignments
        .map((a) => a.operatingAreaId == operatingAreaId ? a.copyWith(selectedInSession: selected) : a)
        .toList();
    state = state.copyWith(areaAssignments: updated);
  }

  Future<bool> startBusinessSession({required String agentId, required String businessId}) async {
    if (!state.canStartSession) return false; // "cannot start a session without selecting at least one area"
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.startBusinessSession(
        agentId: agentId,
        operatingAreaIds: state.selectedAreas.map((a) => a.operatingAreaId).toList(),
      );
      // Re-derive from account_periods rather than assuming success wrote
      // exactly what was requested — same "don't assume, re-fetch" pattern
      // as the rest of this notifier.
      final runningPeriods = await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods.map((p) => p.businessStartDate).reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(
        dashboard: dashboard,
        runningPeriods: runningPeriods,
        stage: AgentSessionStage.running,
        loading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Change Area (S3) — blocked if Pending Unsaved Transactions exist.
  Future<bool> addArea({required String agentId, required String businessId, required String operatingAreaId}) async {
    if (state.hasPendingUnsavedTransactions) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.addAreaToSession(agentId: agentId, operatingAreaId: operatingAreaId);
      toggleAreaSelection(operatingAreaId, true);
      final runningPeriods = await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods.map((p) => p.businessStartDate).reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(dashboard: dashboard, runningPeriods: runningPeriods);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> removeArea({required String agentId, required String businessId, required String operatingAreaId}) async {
    if (state.hasPendingUnsavedTransactions) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.removeAreaFromSession(agentId: agentId, operatingAreaId: operatingAreaId);
      toggleAreaSelection(operatingAreaId, false);
      final runningPeriods = await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods.map((p) => p.businessStartDate).reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(dashboard: dashboard, runningPeriods: runningPeriods);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> refreshDashboard({required String agentId, required String businessId}) async {
    try {
      final api = ref.read(agentApiServiceProvider);
      final businessDate = state.runningPeriods.isEmpty
          ? DateTime.now()
          : state.runningPeriods.map((p) => p.businessStartDate).reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(dashboard: dashboard);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final agentDashboardProvider = NotifierProvider<AgentDashboardNotifier, AgentDashboardState>(
  AgentDashboardNotifier.new,
);

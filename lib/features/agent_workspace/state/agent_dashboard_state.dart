import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/text_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// PERF: `agents.agent_id -> membership_id` is immutable for the life of an
  /// agent record, but eight separate methods in this file each resolved it
  /// with their own round trip — the AG-001 entry flow alone did three
  /// identical `agents` lookups (fetchCurrentBfAssignment,
  /// fetchRunningAccountPeriods, fetchDashboard). Memoised per service
  /// instance, which is a kept-alive Provider, so each agent is looked up once
  /// per app run.
  ///
  /// Safe to cache precisely because the mapping never changes: an agent's
  /// membership_id is set when the agents row is created and there is no code
  /// path anywhere that reassigns it. If that ever becomes untrue, this cache
  /// is the thing to invalidate.
  final Map<String, String> _membershipIdCache = {};

  Future<String> _resolveMembershipId(String agentId) async {
    final cached = _membershipIdCache[agentId];
    if (cached != null) return cached;
    final row = await _db
        .from('agents')
        .select('membership_id')
        .eq('agent_id', agentId)
        .single();
    final membershipId = row['membership_id'] as String;
    _membershipIdCache[agentId] = membershipId;
    return membershipId;
  }

  // GET current agent_bf_assignments row — RLS (rls_role_matrix.md:
  // "agent_bf_assignments — A: SELECT own rows only") already scopes this
  // to the caller's own row; ordered by created_at so the latest session's
  // assignment wins if more than one exists (business_date OR
  // account_period_id keys the session per schema comment).
  Future<AgentBfAssignment?> fetchCurrentBfAssignment(
      {required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    final rows = await _db
        .from('agent_bf_assignments')
        .select(
            'assignment_id, opening_bf, agent_bf_current, confirmed_by_agent, update_requested')
        .eq('membership_id', membershipId)
        // business_date first, matching app.create_loan_with_bf_check's own
        // ORDER BY. This read created_at while the loan check read
        // business_date, so with more than one assignment row the screen
        // could show one row's float while the server spent another's.
        .order('business_date', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false)
        .limit(1);
    // No row yet does NOT mean the Agent is locked out — it means they hold
    // nothing. Create the zero row and carry on: an Agent with no float is an
    // ordinary morning, and app.create_loan_with_bf_check still stops them
    // lending money they do not have.
    if ((rows as List).isEmpty) {
      final created = await _db.schema('app').rpc(
          'ensure_agent_bf_assignment',
          params: {'p_membership_id': membershipId});
      final c = Map<String, dynamic>.from(created as Map);
      return AgentBfAssignment(
        bfAssignmentId: c['assignment_id'] as String,
        openingBf: (c['opening_bf'] as num).toInt(),
        currentBf: (c['agent_bf_current'] as num?)?.toInt() ?? 0,
        confirmedByAgent: c['confirmed_by_agent'] as bool,
        updateRequested: c['update_requested'] as bool,
      );
    }
    final r = rows.first;
    return AgentBfAssignment(
      bfAssignmentId: r['assignment_id'] as String,
      openingBf: (r['opening_bf'] as num).toInt(),
      currentBf: (r['agent_bf_current'] as num?)?.toInt() ?? 0,
      confirmedByAgent: r['confirmed_by_agent'] as bool,
      updateRequested: r['update_requested'] as bool,
    );
  }

  // HISTORY — NO LONGER BLOCKED. The RPC exists and is called below; this
  // paragraph is kept because it records WHY the write goes through a
  // SECURITY DEFINER function rather than a direct update, which is still
  // true. See the FIXED note further down.
  //
  // Was: rls_role_matrix.md is explicit here — "agent_bf_
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
  Future<void> confirmBfAssignment(
      {required String bfAssignmentId, required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.schema('app').rpc('confirm_bf_assignment',
        params: {'p_membership_id': membershipId});
  }

  // FIXED (this pass): app.request_bf_update RPC now exists (migration 0022).
  Future<void> requestBfUpdate(
      {required String bfAssignmentId,
      required String agentId,
      String? note}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.schema('app').rpc('request_bf_update',
        params: {'p_membership_id': membershipId, 'p_note': note});
  }

  // GET Owner-enabled Operating Areas assigned to this Agent.
  Future<List<AgentAreaAssignment>> fetchAreaAssignments(
      {required String agentId}) async {
    final rows = await _db.from('agent_area_assignments').select('''
          operating_area_id,
          operating_areas!inner(status, name)
        ''').eq('agent_id', agentId).isFilter('removed_at', null);
    return (rows as List).map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>;
      return AgentAreaAssignment(
        operatingAreaId: r['operating_area_id'] as String,
        // An area is a NAMED round covering N villages now, so its own
        // name is the label — it used to be joined out of the single
        // `location_id` this table no longer has.
        areaName: (area['name'] as String?) ?? '',
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
  Future<List<AgentAccountPeriodSummary>> fetchRunningAccountPeriods(
      {required String agentId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    final rows = await _db.from('account_periods').select('''
          operating_area_id, business_start_date, planned_business_end_date, status,
          operating_areas!inner(name)
        ''').eq('agent_membership_id', membershipId).eq('status', 'Running');
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>;
      return AgentAccountPeriodSummary(
        operatingAreaId: r['operating_area_id'] as String,
        areaName: (area['name'] as String?) ?? '',
        businessStartDate: DateTime.parse(r['business_start_date'] as String),
        plannedBusinessEndDate:
            DateTime.parse(r['planned_business_end_date'] as String),
        status: r['status'] as String,
      );
    }).toList();
  }

  // HISTORY — NO LONGER BLOCKED. start_business_session exists and is called
  // below; kept for the reasoning, which still holds.
  //
  // Was: rls_role_matrix.md, `account_periods` — "No client
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
    await _db.schema('app').rpc('start_business_session', params: {
      'p_membership_id': membershipId,
      'p_area_ids': operatingAreaIds,
    });
  }

  // FIXED (this pass): app.add_area_to_session RPC now exists (migration 0022).
  Future<void> addAreaToSession(
      {required String agentId, required String operatingAreaId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.schema('app').rpc('add_area_to_session', params: {
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
  Future<void> removeAreaFromSession(
      {required String agentId, required String operatingAreaId}) async {
    final membershipId = await _resolveMembershipId(agentId);
    await _db.schema('app').rpc('remove_area_from_session', params: {
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
    // PERF: this was 11 sequential round trips. Restructured into two waves
    // by actual data dependency — only two things genuinely have to wait for
    // something else: `owner` needs business.owner_person_id, and the five
    // membership-scoped reads need the resolved membershipId.
    //
    // Future.wait (not record `.wait`) throughout: it propagates the first
    // original error rather than wrapping everything in a ParallelWaitError,
    // which NetworkErrorHandler would fail to recognise as server-reached and
    // would report as a generic "Something went wrong", hiding the real
    // Postgres message.
    //
    // WAVE 1 — nothing here depends on anything else in this method.
    final wave1 = await Future.wait<dynamic>([
      _resolveMembershipId(agentId),
      _db.from('businesses').select('business_name, owner_person_id').eq('business_id', businessId).single(),
      _db
          .from('account_settlements')
          .select('settlement_id')
          .eq('agent_id', agentId)
          .eq('status', 'Pending Owner Review')
          .limit(1),
      _db
          .from('agent_compensation_history')
          .select('fixed_salary_amount, salary_cycle, daily_allowance, profit_share_percent')
          .eq('agent_id', agentId)
          .isFilter('superseded_at', null)
          .maybeSingle(),
    ]);
    final membershipId = wave1[0] as String;
    final business = wave1[1] as Map<String, dynamic>;
    final pendingSettlementRows = wave1[2] as List;
    final compHistory = wave1[3] as Map<String, dynamic>?;

    // WAVE 2 — `owner` needs business from wave 1; the rest need membershipId.
    final wave2 = await Future.wait<dynamic>([
      _db.from('persons').select('full_name').eq('person_id', business['owner_person_id']).single(),
      _db.from('business_members').select('membership_status').eq('membership_id', membershipId).single(),
      // Scoped to THIS business, not left to RLS.
      //
      // The note here used to say app.agent_covers_customer scoped it to the
      // agent's assigned areas. It does not, because RLS grants the UNION of
      // what any policy allows: an Owner who is also an Agent of their own
      // business matches customers_owner_all as well, which covers every
      // business they own. On the live account that is two businesses, and the
      // dashboard counted 85 customers for a book that has 55.
      //
      // RLS knows what a person is ALLOWED to see. It cannot know which
      // business they are LOOKING AT, and no policy ever will.
      _db
          .from('customers')
          .select('customer_id, '
              'business_members!customers_membership_id_fkey!inner(business_id)')
          .eq('business_members.business_id', businessId),
      _db
          .from('collection_drafts')
          .select('draft_id')
          .eq('created_by_membership_id', membershipId)
          .eq('status', 'Draft'),
      _db.from('routes').select('route_name').eq('default_agent_id', membershipId).limit(1).maybeSingle(),
    ]);
    final owner = wave2[0] as Map<String, dynamic>;
    final membershipRow = wave2[1] as Map<String, dynamic>;
    final customersAssignedCount = wave2[2] as List;
    final pendingDrafts = wave2[3] as List;
    final routeRow = wave2[4] as Map<String, dynamic>?;

    // The Agent's own round, as the server sees it. v_collection_due carries
    // today's outcome per loan, so visited / pending / skipped and the day's
    // target all come from one read instead of being guessed at.
    final roundRows = ((await _db
            .schema('app')
            .from('v_collection_due')
            .select('loan_id, customer_id, total_due, today_result, collected_today')
            .eq('business_id', businessId)
            .eq('collection_agent_membership_id', membershipId)) as List)
        .cast<Map<String, dynamic>>();

    // What was taken today, split by how it was handed over. Joined through
    // collections so the day and the collector are the server's, not the
    // handset's idea of "today".
    final splitRows = ((await _db
            .from('collection_payment_splits')
            .select('collection_id, payment_mode, amount, '
                'collections!inner(business_date, collected_by_membership_id, deleted_at)')
            .eq('collections.collected_by_membership_id', membershipId)
            .eq('collections.business_date', manaBusinessDate())
            .isFilter('collections.deleted_at', null)) as List)
        .cast<Map<String, dynamic>>();

    int byMode(String mode) => splitRows
        .where((r) => r['payment_mode'] == mode)
        .fold(0, (sum, r) => sum + ((r['amount'] as num?)?.toInt() ?? 0));

    // A collection handed over in more than one mode. Counted as its own
    // figure rather than added to Cash and UPI both, which would report more
    // money than changed hands.
    final splitsByCollection = <String, int>{};
    for (final r in splitRows) {
      final id = r['collection_id']?.toString();
      if (id != null) splitsByCollection[id] = (splitsByCollection[id] ?? 0) + 1;
    }

    final loansToday = ((await _db
            .from('loans')
            .select('loan_id')
            .eq('business_id', businessId)
            .eq('collection_agent_membership_id', membershipId)
            .eq('issue_business_date', manaBusinessDate())
            .isFilter('deleted_at', null)) as List)
        .length;

    final permRow = await _db
        .from('agent_permissions')
        .select()
        .eq('agent_id', agentId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    // BUG FIXED this pass: this used to add the raw agent_permissions
    // COLUMN NAMES (e.g. "can_collect_payments") to visibleActions, but
    // ag_001_agent_home_dashboard.dart's _QuickActions filters its tiles
    // by their DISPLAY LABELS ("Collection Mode") — the two vocabularies
    // never intersected, so Quick Actions rendered as an empty
    // SizedBox.shrink() for every Agent regardless of what permissions
    // the Owner actually granted. Mapping each tile to its governing
    // permission column explicitly, rather than assuming names line up.
    // Notifications/Universal Search aren't privileged actions (same as
    // OW-001's header icons having no permission gate) so they're always
    // visible rather than tied to a column that doesn't exist for them.
    const tilePermissionColumns = {
      'Collection Mode': 'can_access_collection_mode',
      'Area Work Session': 'can_view_dashboard',
      'Customer List': 'can_view_customers',
      'Loan Distribution': 'can_issue_loans',
      'Draft Transactions': 'can_create_drafts',
      'Settlement': 'can_perform_day_settlement',
    };
    final visibleActions = <String>{'Notifications', 'Universal Search'};
    if (permRow != null) {
      tilePermissionColumns.forEach((label, column) {
        if (permRow[column] == true) visibleActions.add(label);
      });
    }

    return AgentDashboardData(
      // BUG FIXED this pass: previously hardcoded DateTime.now() with a
      // comment saying the real source "isn't in scope at call time" —
      // it now is, via fetchRunningAccountPeriods() feeding this param
      // from the Notifier (see _loadAreasAndDashboard/refreshDashboard
      // below). Device clock is kept only as the last-resort fallback
      // for the edge case where fetchDashboard is somehow called before
      // any Running period exists.
      businessDate: businessDate ?? manaNowIst(),
      assignedRoute: (routeRow?['route_name'] as String?) ?? '',
      pendingDraftsCount: pendingDrafts.length,
      pendingSettlement: pendingSettlementRows.isNotEmpty,
      // Every one of these read 0, hardcoded, with a comment deferring it.
      // The strip has therefore been telling every Agent they had visited
      // nobody and collected nothing, all day, since it was built.
      todaysTarget: roundRows.fold(
          0, (sum, r) => sum + ((r['total_due'] as num?)?.toInt() ?? 0)),
      customersAssigned: customersAssignedCount.length,
      // Doors knocked on: a payment OR a recorded visit without one. Counted
      // by CUSTOMER, not by loan -- one person with two loans is one door.
      customersVisited: roundRows
          .where((r) => r['today_result'] != null)
          .map((r) => r['customer_id'])
          .toSet()
          .length,
      collectionsCash: byMode('Cash'),
      collectionsUpi: byMode('UPI'),
      collectionsBank: byMode('Bank Transfer'),
      collectionsCheque: byMode('Cheque'),
      collectionsMixed:
          splitsByCollection.values.where((n) => n > 1).length,
      loansIssued: loansToday,
      // Still owed at a door not yet answered for. Was every active loan the
      // Agent holds, which never moved as the round was worked.
      pendingCollections:
          roundRows.where((r) => r['today_result'] == null).length,
      skippedCustomers: roundRows
          .where((r) => r['today_result'] == 'No Collection')
          .length,
      shortAmount:
          0, // Settlement Short/Excess math — Calculation Engine territory, not reimplemented here
      excessAmount: 0,
      visibleQuickActions: visibleActions,
      liveActivity: const [], // deferred, same reasoning as owner_api_service.dart
      businessName: titleCaseName(business['business_name'] as String),
      ownerName: owner['full_name'] as String,
      membershipStatus: membershipRow['membership_status'] as String,
      // Notifications/Universal Search are always in visibleActions now
      // (see fix note above), so "Restricted" has to be judged from the
      // actual permission-gated tiles, not the full set.
      permissionProfile: tilePermissionColumns.values.any((c) => permRow?[c] == true) ? 'Custom' : 'Restricted',
      lastSync: DateTime.now(),
      pendingCustomerRequests:
          0, // membership_requests targeting this Agent isn't a modeled relationship (requests target the Owner/business) — 0 is structurally correct, not a placeholder
      pendingExtensionRequests:
          0, // deferred: would need a second query scoped to this agent's assigned customers' loans
      pendingRouteChanges: 0,
      pendingMessages: 0,
      fixedSalary:
          (compHistory?['fixed_salary_amount'] as num?)?.toInt() ?? 0,
      salaryCycleStatus: (compHistory?['salary_cycle'] as String?) ?? '',
      dailyAllowance:
          (compHistory?['daily_allowance'] as num?)?.toInt() ?? 0,
      profitSharePercent:
          (compHistory?['profit_share_percent'] as num?)?.toDouble(),
      advancesDeducted:
          0, // Salary Formula territory (BLOCKED RPC, per briefing) — not reimplemented client-side
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

  /// What the Agent was handed at the START of the session. Written once and
  /// never moved again -- app.submit_agent_settlement reads it as the
  /// session's opening figure.
  ///
  /// It is NOT what the Agent is holding, and every Agent-facing screen used
  /// to show it as though it were: an Agent carrying Rs 2,69,190 of the day's
  /// collections read Rs 0 on their own BF panel and was refused their own
  /// New Loan screen, while the Owner's workforce view of the same person
  /// read Rs 2,69,190.
  final int openingBf;

  /// Cash in hand, now. Collections add to it, disbursements subtract, and
  /// app.create_loan_with_bf_check locks THIS column to decide whether a loan
  /// can be funded. Anything that answers "how much does this Agent have"
  /// answers with this.
  final int currentBf;

  final bool confirmedByAgent;
  final bool updateRequested;

  AgentBfAssignment({
    required this.bfAssignmentId,
    required this.openingBf,
    this.currentBf = 0,
    this.confirmedByAgent = false,
    this.updateRequested = false,
  });
}

class AgentAreaAssignment {
  final String operatingAreaId;
  final String areaName;
  final bool
      enabled; // agent_area_assignments joined against operating_areas.status = 'Active'
  final bool
      selectedInSession; // client-side: currently part of the running Business Session

  AgentAreaAssignment({
    required this.operatingAreaId,
    required this.areaName,
    this.enabled = true,
    this.selectedInSession = false,
  });

  AgentAreaAssignment copyWith({bool? selectedInSession}) =>
      AgentAreaAssignment(
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
  AgentLiveActivityEntry(
      {required this.kind, required this.description, required this.at});
}

class AgentDashboardData {
  // Business Status
  final DateTime businessDate;
  final String assignedRoute;
  final int pendingDraftsCount;
  final bool pendingSettlement;
  final int todaysTarget;

  // Today Summary
  final int customersAssigned;
  final int customersVisited;
  final int collectionsCash;
  final int collectionsUpi;
  final int collectionsBank;
  final int collectionsCheque;
  final int collectionsMixed;
  final int loansIssued;
  final int pendingCollections;
  final int skippedCustomers;
  final int shortAmount;
  final int excessAmount;

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
  final int fixedSalary;
  final String
      salaryCycleStatus; // e.g. "Daily" / "Weekly" / "Monthly" + current-cycle status
  final int dailyAllowance;
  final double? profitSharePercent; // null when not enabled for this Agent
  final int advancesDeducted;
  final int shortsDeducted;
  final int pendingSalary;
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
  int get todaysCollectionsTotal =>
      collectionsCash +
      collectionsUpi +
      collectionsBank +
      collectionsCheque +
      collectionsMixed;
}

class AgentSalaryHistoryEntry {
  final DateTime paidOn;
  final int amount;
  final String cycleLabel; // e.g. "Jul 2026" or "Week of 14 Jul"
  AgentSalaryHistoryEntry(
      {required this.paidOn, required this.amount, required this.cycleLabel});
}

// ============================================================================
// State
// ============================================================================

enum AgentSessionStage {
  loadingGate, // checking BF assignment
  // Reached only when the zero-row could not be created (offline, or the
  // membership is gone). NOT the normal "Owner has not granted BF yet" case:
  // that is an ordinary session opening at zero.
  bfBlockedNoAssignment,
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

  List<AgentAreaAssignment> get enabledAreas =>
      areaAssignments.where((a) => a.enabled).toList();
  List<AgentAreaAssignment> get selectedAreas =>
      areaAssignments.where((a) => a.selectedInSession).toList();
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
      hasPendingUnsavedTransactions:
          hasPendingUnsavedTransactions ?? this.hasPendingUnsavedTransactions,
      dashboard: dashboard ?? this.dashboard,
    );
  }
}

class AgentDashboardNotifier extends Notifier<AgentDashboardState> {
  @override
  AgentDashboardState build() => const AgentDashboardState();

  /// Entry sequence: BF Confirm/Update gate first, then Area Selection or
  /// Running dashboard — per AG-001's ENTRY POINT + OPENING BF GATE order.
  Future<void> enter(
      {required String agentId, required String businessId}) async {
    state = state.copyWith(
        loading: true, clearError: true, stage: AgentSessionStage.loadingGate);
    try {
      final api = ref.read(agentApiServiceProvider);
      final bf = await api.fetchCurrentBfAssignment(agentId: agentId);

      if (bf == null) {
        state = state.copyWith(
            loading: false, stage: AgentSessionStage.bfBlockedNoAssignment);
        return;
      }
      if (bf.updateRequested) {
        state = state.copyWith(
            loading: false,
            bfAssignment: bf,
            stage: AgentSessionStage.bfUpdateRequested);
        return;
      }
      if (!bf.confirmedByAgent) {
        state = state.copyWith(
            loading: false,
            bfAssignment: bf,
            stage: AgentSessionStage.bfConfirmPending);
        return;
      }

      await _loadAreasAndDashboard(
          agentId: agentId, businessId: businessId, bf: bf);
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
    // PERF: these two reads are independent, so they are started together.
    // These are `async` methods, so calling one runs its body up to its first
    // await — where the request is issued — meaning both are in flight before
    // the awaits below. Awaited individually rather than via record `.wait` so
    // a failure keeps its original PostgrestException instead of becoming a
    // ParallelWaitError that NetworkErrorHandler would report generically.
    //
    // BUG FIXED an earlier pass: runningPeriods used to check
    // `state.runningPeriods.isNotEmpty`, but nothing ever populated that list,
    // so a session could never be detected as running. Now actually queried.
    final areasFuture = api.fetchAreaAssignments(agentId: agentId);
    final runningPeriodsFuture = api.fetchRunningAccountPeriods(agentId: agentId);
    final areas = await areasFuture;
    final runningPeriods = await runningPeriodsFuture;
    final runningAreaIds = runningPeriods.map((p) => p.operatingAreaId).toSet();
    final markedAreas = areas
        .map((a) => a.copyWith(
            selectedInSession: runningAreaIds.contains(a.operatingAreaId)))
        .toList();

    if (runningPeriods.isNotEmpty) {
      // Business Date is controlled by the running account_period, not
      // the device clock (AG-001 "Business Date controls all financial
      // entries"). Multiple areas share one business_start_date per
      // session (AG-001's own DATA MODEL note), so any one of them is
      // representative — earliest taken defensively in case of drift.
      final businessDate = runningPeriods
          .map((p) => p.businessStartDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(
          businessId: businessId, agentId: agentId, businessDate: businessDate);
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

  Future<bool> confirmBf(
      {required String agentId, required String businessId}) async {
    if (state.bfAssignment == null) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.confirmBfAssignment(
          bfAssignmentId: state.bfAssignment!.bfAssignmentId, agentId: agentId);
      await _loadAreasAndDashboard(
        agentId: agentId,
        businessId: businessId,
        bf: AgentBfAssignment(
          bfAssignmentId: state.bfAssignment!.bfAssignmentId,
          openingBf: state.bfAssignment!.openingBf,
          currentBf: state.bfAssignment!.currentBf,
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
      await api.requestBfUpdate(
          bfAssignmentId: state.bfAssignment!.bfAssignmentId, agentId: agentId);
      state = state.copyWith(stage: AgentSessionStage.bfUpdateRequested);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void toggleAreaSelection(String operatingAreaId, bool selected) {
    final updated = state.areaAssignments
        .map((a) => a.operatingAreaId == operatingAreaId
            ? a.copyWith(selectedInSession: selected)
            : a)
        .toList();
    state = state.copyWith(areaAssignments: updated);
  }

  Future<bool> startBusinessSession(
      {required String agentId, required String businessId}) async {
    if (!state.canStartSession) {
      return false; // "cannot start a session without selecting at least one area"
    }
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.startBusinessSession(
        agentId: agentId,
        operatingAreaIds:
            state.selectedAreas.map((a) => a.operatingAreaId).toList(),
      );
      // Re-derive from account_periods rather than assuming success wrote
      // exactly what was requested — same "don't assume, re-fetch" pattern
      // as the rest of this notifier.
      final runningPeriods =
          await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods
              .map((p) => p.businessStartDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(
          businessId: businessId, agentId: agentId, businessDate: businessDate);
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
  Future<bool> addArea(
      {required String agentId,
      required String businessId,
      required String operatingAreaId}) async {
    if (state.hasPendingUnsavedTransactions) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.addAreaToSession(
          agentId: agentId, operatingAreaId: operatingAreaId);
      toggleAreaSelection(operatingAreaId, true);
      final runningPeriods =
          await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods
              .map((p) => p.businessStartDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(
          businessId: businessId, agentId: agentId, businessDate: businessDate);
      state =
          state.copyWith(dashboard: dashboard, runningPeriods: runningPeriods);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> removeArea(
      {required String agentId,
      required String businessId,
      required String operatingAreaId}) async {
    if (state.hasPendingUnsavedTransactions) return false;
    try {
      final api = ref.read(agentApiServiceProvider);
      await api.removeAreaFromSession(
          agentId: agentId, operatingAreaId: operatingAreaId);
      toggleAreaSelection(operatingAreaId, false);
      final runningPeriods =
          await api.fetchRunningAccountPeriods(agentId: agentId);
      final businessDate = runningPeriods.isEmpty
          ? DateTime.now()
          : runningPeriods
              .map((p) => p.businessStartDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(
          businessId: businessId, agentId: agentId, businessDate: businessDate);
      state =
          state.copyWith(dashboard: dashboard, runningPeriods: runningPeriods);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> refreshDashboard(
      {required String agentId, required String businessId}) async {
    try {
      final api = ref.read(agentApiServiceProvider);
      final businessDate = state.runningPeriods.isEmpty
          ? DateTime.now()
          : state.runningPeriods
              .map((p) => p.businessStartDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
      final dashboard = await api.fetchDashboard(
          businessId: businessId, agentId: agentId, businessDate: businessDate);
      state = state.copyWith(dashboard: dashboard);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final agentDashboardProvider =
    NotifierProvider<AgentDashboardNotifier, AgentDashboardState>(
  AgentDashboardNotifier.new,
);

/// One Agent's permission row, as a plain map.
///
/// The dashboard already reads agent_permissions, but it converts the columns
/// into Quick Action LABELS and throws the raw flags away -- so a screen that
/// needs to ask "may this Agent create a customer?" had nowhere to look.
///
/// Advisory only. Every one of these permissions is enforced server-side in
/// the RPC that does the work; this exists so the UI can avoid OFFERING an
/// action that would be refused, which is kinder than a form that cannot save.
/// It must never be the only thing standing between an Agent and a write.
final agentPermissionsProvider =
    FutureProvider.family<Map<String, bool>, String>((ref, agentId) async {
  final row = await Supabase.instance.client
      .from('agent_permissions')
      .select()
      .eq('agent_id', agentId)
      .order('updated_at', ascending: false)
      .limit(1)
      .maybeSingle();
  if (row == null) return const <String, bool>{};
  return {
    for (final e in row.entries)
      if (e.key.startsWith('can_') && e.value is bool) e.key: e.value as bool,
  };
});

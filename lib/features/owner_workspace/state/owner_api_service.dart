import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/document_viewer.dart' show DocumentSummary;
import '../../login_registration/state/auth_flow_state.dart';

/// Real Supabase wiring over the Owner Workspace endpoints touched by
/// OW-000/OW-001/OW-002.
///
/// INTEGRATION FLAGS (same caveats as collection_mode_state.dart /
/// loan_wizard_state.dart, not repeated in full here):
///  - Assumes `Supabase.initialize(...)` has already run in main.dart.
///  - `authFlowProvider.personId` is `String?`, parsed with `int.parse` to
///    match `persons.person_id BIGINT`.
///
/// CALLER NOTE: every method here is called from
/// `business_management_state.dart`'s notifiers (`businessSetupProvider`,
/// `workforceProvider`, `businessDetailProvider`, `agentProfileProvider`),
/// NOT directly from any screen — confirmed by grep of
/// `owner_workspace/screens/*.dart`. That means these method signatures are
/// safe to reshape without breaking a screen file directly, but changing
/// them still ripples into `business_management_state.dart` (Priority 3,
/// not yet wired in this session) — kept UNCHANGED here anyway, to avoid
/// silently deciding that file's contract before it exists.
class OwnerApiService {
  final Ref ref;
  OwnerApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  int get _personId {
    final id = ref.read(authFlowProvider).personId;
    if (id == null) throw StateError('No logged-in person_id available.');
    return int.parse(id);
  }

  // --- OW-000 Step 1 / OW-012 Create Business -----------------------------
  //
  // SCHEMA GAP FOUND: `businesses.mlbi` is `VARCHAR(20) UNIQUE NOT NULL`
  // with no DEFAULT and no generating trigger anywhere in migrations
  // 0001-0011 (grep confirms zero `CREATE TRIGGER`/`CREATE SEQUENCE` in the
  // whole schema) — despite the schema doc's own comment calling it
  // "system-generated". As delivered, SOMETHING has to generate it, and a
  // client-generated value racing another client is exactly the kind of
  // thing a UNIQUE constraint is supposed to catch, not prevent. Generated
  // here from a millisecond timestamp with a retry-on-conflict loop as a
  // stop-gap; flagged for master chat to move to a proper Postgres
  // sequence + trigger (e.g. `nextval` zero-padded into 'MLBI-00000125'
  // format) so generation is atomic and gapless.
  Future<CreateBusinessResult> createBusiness({
    required String businessName,
    required String registeredFinanceName,
    String? logoUrl,
    String? businessType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final candidateMlbi = 'MLBI-${DateTime.now().microsecondsSinceEpoch % 100000000}';
      try {
        final rows = await _db.schema('app').rpc('create_business_with_owner', params: {
          'p_mlbi': candidateMlbi,
          // Title-cased on the way IN, so the stored value is right rather
          // than every read site having to repair it. Matches how person
          // names are already normalised (titleCaseName, text_utils.dart) —
          // business names were simply never included in that rule, so
          // "sri satyanarayana" was stored and displayed exactly as typed.
          'p_business_name': titleCaseName(businessName),
          'p_registered_finance_name': titleCaseName(registeredFinanceName),
          'p_logo_url': logoUrl,
          'p_business_type': businessType,
          'p_business_address': businessAddress,
          'p_business_phone': businessPhone,
          'p_business_email': businessEmail,
        });
        final row = (rows as List).first as Map<String, dynamic>;
        return CreateBusinessResult(businessId: row['business_id'] as String, mlbi: row['mlbi'] as String);
      } on PostgrestException catch (e) {
        final isUniqueViolation = e.code == '23505';
        if (isUniqueViolation && attempt < maxAttempts - 1) continue;
        rethrow;
      }
    }
    throw StateError('createBusiness: exhausted MLBI generation retries — see SCHEMA GAP note above.');
  }

  // --- OW-000 Step 2 — Create Operating Area(s) ---------------------------
  Future<OperatingAreaResult> addOperatingArea({
    required String businessId,
    required String pinCode,
    required String villageId,
  }) async {
    // account_cycle_duration/unit/submission_time are NOT NULL on
    // operating_areas but this method's params don't collect them (that
    // happens in Step 3 / setAccountCycleConfig below, per the wizard's own
    // step split) — insert with schema-legal placeholder defaults
    // (3 Days, 21:00, matching the schema doc's own example values) and
    // rely on Step 3's UPDATE to overwrite them before the area is used for
    // real. Flagged: if a person exits the wizard between Step 2 and Step
    // 3, the area is left with these placeholder values, not an empty/null
    // state — worth a UI-level "incomplete area" affordance, not something
    // this state layer alone can fix.
    //
    // An area is now a NAMED round with N villages in
    // `operating_area_locations`, so this is two writes, not one. The
    // wizard only collects a single village, so the area is named after it
    // — the Owner can rename it and attach more villages later from
    // OW-012. Not a placeholder: for a one-village round the village name
    // IS the right name.
    final village = await _db
        .from('locations')
        .select('village_town_name')
        .eq('location_id', villageId)
        .single();
    final villageName = (village['village_town_name'] as String?) ?? '';

    final row = await _db
        .from('operating_areas')
        .insert({
          'business_id': businessId,
          'name': villageName,
          'status': 'Active',
          'account_cycle_duration': 3,
          'account_cycle_unit': 'Days',
          'submission_time': '21:00:00',
        })
        .select('operating_area_id')
        .single();
    final operatingAreaId = row['operating_area_id'] as String;

    await _db.from('operating_area_locations').insert({
      'operating_area_id': operatingAreaId,
      'location_id': villageId,
      'business_id': businessId,
    });

    return OperatingAreaResult(
      operatingAreaId: operatingAreaId,
      pinCode: pinCode, // caller-supplied, not re-read from locations (locations.pin_code may differ if villageId spans multiple pins — kept as given)
      villageName: villageName,
    );
  }

  // --- OW-000 Step 3 — Configure Account Cycle per Operating Area ---------
  //
  // SIGNATURE GAP FOUND: `operating_areas.account_cycle_unit` is a
  // required ENUM ('Days','Weeks','Months') but this method only accepts
  // `durationDays` (no unit param) — the name itself assumes Days. Rather
  // than silently guessing, this hardcodes 'Days' AND flags it: if the
  // OW-000 screen actually offers Weeks/Months in its UI, this method's
  // signature needs a `unit` param added, which is a real interface change
  // outside this session's "don't touch screens" boundary to discover on
  // its own — needs confirmation from whoever owns the OW-000 screen file.
  Future<void> setAccountCycleConfig({
    required String operatingAreaId,
    required int durationDays,
    required String submissionTime, // HH:mm, business-local
  }) async {
    await _db.from('operating_areas').update({
      'account_cycle_duration': durationDays,
      'account_cycle_unit': 'Days',
      'submission_time': '$submissionTime:00',
    }).eq('operating_area_id', operatingAreaId);
  }

  // --- OW-000 Step 5 (optional) — Create Business Agreement ---------------
  Future<void> createAgreement({
    required String businessId,
    required String agreementType, // Customer | Agent | Investor
    required String documentUrl,
  }) async {
    await _db.from('business_agreements').insert({
      'business_id': businessId,
      'agreement_type': agreementType,
      'source_type': 'Uploaded PDF',
      'content_url_or_text': documentUrl,
      'version': 1,
      'effective_date': DateTime.now().toIso8601String().split('T').first,
    });
  }

  // --- OW-000 Step 6 — Assign Operating Area to Agent, or mark Owner-run --
  Future<void> assignAreaToAgent({
    required String operatingAreaId,
    required String agentId,
  }) async {
    await _db.from('agent_area_assignments').insert({
      'agent_id': agentId,
      'operating_area_id': operatingAreaId,
    });
  }

  // SCHEMA GAP FOUND: `operating_areas` has no `owner_run` (or similar)
  // boolean column anywhere in the locked schema — "Owner-run" area status
  // is not a stored flag at all, it is simply the ABSENCE of any
  // `agent_area_assignments` row for that area. This method is therefore a
  // correct no-op against the real schema (an area with zero assignment
  // rows already reads as Owner-run under that definition) rather than an
  // unimplemented gap — kept as an explicit method (not deleted) so the
  // OW-000 screen's call site keeps compiling and its intent stays
  // documented in one place.
  Future<void> markAreaOwnerRun({required String operatingAreaId}) async {
    return; // intentionally a no-op — see SCHEMA GAP note above.
  }

  // --- OW-000 Completion — Start Business ---------------------------------
  Future<void> startBusiness({required String businessId}) async {
    await _db.from('businesses').update({
      'migration_locked': true,
      'business_started_at': DateTime.now().toIso8601String(),
      'business_status': 'Active',
    }).eq('business_id', businessId);
  }

  // --- OW-001 Owner Home Dashboard ----------------------------------------
  //
  // KNOWN SIMPLIFICATION (flagged, not silently cut): the real endpoint
  // this replaces was documented as ONE server-side pre-aggregated call.
  // Here it's rebuilt from several direct table reads, which is fine for
  // straightforward counts (workforce/investor headcounts, business
  // metadata) but NOT fine for figures that depend on the Calculation
  // Engine (Line Score-adjacent numbers, interest accrual, BF Cash
  // reconciliation) — those are left at 0 rather than approximated with
  // ad hoc Dart math, per the briefing's instruction not to reimplement
  // that engine client-side. Fields defaulted to 0 below are marked inline.
  // Recommend a Postgres VIEW or RPC (e.g. `get_owner_dashboard`) as the
  // real fix, same as the collection-due-list gap in
  // collection_mode_state.dart.
  Future<OwnerDashboardData> fetchDashboard({required String businessId}) async {
    // PERF: these five reads are mutually independent, so they go out
    // together rather than one after another. This is the first screen after
    // login and it was previously five sequential round trips — roughly five
    // times the latency for no reason.
    //
    // Future.wait is required, not stylistic: PostgrestBuilder implements
    // Future and only issues the request when `then` is called (see
    // postgrest_builder.dart), so assigning builders to variables and
    // awaiting them one by one would still run them serially. Future.wait
    // subscribes to all of them immediately.
    final results = await Future.wait<dynamic>([
      _db.from('businesses').select('business_name, logo_url, business_status').eq('business_id', businessId).single(),
      _db.from('business_members').select('role, membership_status').eq('business_id', businessId),
      _db.from('loans').select('loan_status, remaining_balance').eq('business_id', businessId),
      _db.from('investments').select('principal_amount, status').eq('business_id', businessId),
      _db
          .from('notifications')
          .select('notification_type, message, created_at, is_read')
          .eq('business_id', businessId)
          .order('created_at', ascending: false)
          .limit(20),
    ]);

    final business = results[0] as Map<String, dynamic>;
    final members = results[1] as List;
    final loans = results[2] as List;
    final investments = results[3] as List;
    final notificationsRaw = results[4] as List;

    int countWhere(String role, String status) =>
        members.where((m) => m['role'] == role && m['membership_status'] == status).length;
    int countRole(String role) => (members).where((m) => m['role'] == role).length;

    final activeLoanStatuses = {'Active', 'Grace Period', 'Penalty'};
    final activeLoansList = loans.where((l) => activeLoanStatuses.contains(l['loan_status']));
    final penaltyCount = (loans).where((l) => l['loan_status'] == 'Penalty').length;
    final graceCount = (loans).where((l) => l['loan_status'] == 'Grace Period').length;
    final outstandingSum = activeLoansList.fold<double>(0, (sum, l) => sum + (l['remaining_balance'] as num).toDouble());

    final activeInvestmentSum = investments
        .where((i) => i['status'] == 'Active')
        .fold<double>(0, (sum, i) => sum + (i['principal_amount'] as num).toDouble());

    // customers has no direct business_id column (reached via
    // membership_id -> business_members.business_id) — computed from the
    // members list already fetched above instead of a second round trip.
    final activeCustomerMembershipIds = (members)
        .where((m) => m['role'] == 'Customer' && m['membership_status'] == 'Active')
        .length;
    final totalCustomerMembershipIds = (members).where((m) => m['role'] == 'Customer').length;

    return OwnerDashboardData(
      businessName: business['business_name'] as String,
      logoUrl: business['logo_url'] as String?,
      businessOpen: business['business_status'] == 'Active',
      pendingApprovals: countWhere('Customer', 'Pending Approval'),
      pendingInvitations: (members).where((m) => m['membership_status'] == 'Pending Invitation').length,
      pendingAcceptances: (members).where((m) => m['membership_status'] == 'Pending Acceptance').length,
      pendingDayClosure: false, // requires day_ledger/day_closures reconciliation — left for day_closure_state.dart (Priority 3), not duplicated here
      openingBalance: 0, // requires today's day_ledger row — Priority 3 (day_closure_state.dart) owns this read
      todaysCollections: 0, // ditto — day-scoped aggregate, not duplicated here to avoid two different "today" computations drifting apart
      todaysLoanDistribution: 0,
      todaysInvestments: 0,
      todaysWithdrawals: 0,
      todaysExpenses: 0,
      todaysOutstanding: outstandingSum,
      todaysDifference: 0, // Calculation Engine territory — not reimplemented client-side
      liveClosingBalance: 0,
      totalCustomers: totalCustomerMembershipIds,
      activeCustomers: activeCustomerMembershipIds,
      activeLoans: activeLoansList.length,
      todaysDueCustomers: 0, // requires loan_schedule due-date join — see collection_mode_state.dart's identical flag
      collectedToday: 0,
      pendingCollections: outstandingSum,
      penaltyCustomers: penaltyCount,
      gracePeriodCustomers: graceCount,
      activeAgents: countWhere('Agent', 'Active'),
      activeInvestors: countWhere('Investor', 'Active'),
      businessMemberships: (members).length,
      totalInvestment: activeInvestmentSum,
      interestPayable: 0, // Calculation Engine formula — not reimplemented client-side
      workforceTotalAgents: countRole('Agent'),
      workforceActiveToday: countWhere('Agent', 'Active'),
      workforcePendingInvitations: (members).where((m) => m['role'] == 'Agent' && m['membership_status'] == 'Pending Invitation').length,
      workforcePendingAcceptance: (members).where((m) => m['role'] == 'Agent' && m['membership_status'] == 'Pending Acceptance').length,
      workforceDisabled: (members).where((m) => m['role'] == 'Agent' && m['membership_status'] == 'Temporarily Disabled').length,
      workforceSuspended: (members).where((m) => m['role'] == 'Agent' && m['membership_status'] == 'Suspended').length,
      investorTotal: countRole('Investor'),
      investorActive: countWhere('Investor', 'Active'),
      investorPendingInvitations: (members).where((m) => m['role'] == 'Investor' && m['membership_status'] == 'Pending Invitation').length,
      investorPendingAcceptance: (members).where((m) => m['role'] == 'Investor' && m['membership_status'] == 'Pending Acceptance').length,
      investorBalance: activeInvestmentSum,
      liveActivity: const [], // audit_log/collections-derived feed — needs its own query design, deferred (Priority 4-adjacent, not attempted this pass)
      attentionRequired: const [],
      notifications: notificationsRaw
          .map((n) => NotificationItem(
                type: n['notification_type'] as String,
                label: n['message'] as String,
                timestamp: DateTime.parse(n['created_at'] as String),
                read: n['is_read'] as bool? ?? false,
              ))
          .toList(),
    );
  }

  // --- OW-002 Workforce Management ----------------------------------------
  Future<List<AgentSummary>> fetchAgents({required String businessId, String? status}) async {
    var query = _db
        .from('business_members')
        .select('''
          membership_id, membership_status, joined_at,
          persons!business_members_person_id_fkey(full_name, mlid, mobile_number),
          agents!inner(agent_id, current_status, joined_date)
        ''')
        .eq('business_id', businessId)
        .eq('role', 'Agent');
    if (status != null) query = query.eq('membership_status', status);
    final rows = await query;

    return (rows as List).map((r) {
      final person = r['persons'] as Map<String, dynamic>?;
      final agent = r['agents'] as Map<String, dynamic>;
      return AgentSummary(
        agentId: agent['agent_id'] as String,
        membershipId: r['membership_id'] as String,
        fullName: titleCaseName(person?['full_name'] as String? ?? ''),
        mlid: person?['mlid'] as String? ?? '',
        phoneNumber: (person?['mobile_number'] as String?) ?? '',
        status: r['membership_status'] as String,
        businessAccess: 'Full Access', // derived from agent_permissions in fetchAgentProfile, not duplicated per-row here (would be N extra queries for a list screen)
        currentRoute: null, // requires routes.default_agent_id reverse lookup — deferred
        todaysCollections: 0, // day-scoped aggregate — deferred, same reasoning as fetchDashboard's "today" fields
        todaysLoans: 0,
        joinedDate: DateTime.parse((agent['joined_date'] as String)),
        lastLogin: null, // devices.last_login_at — self-only per RLS (rls_role_matrix.md: "devices: Self only, full access... literally everyone else, including Owner"); an Owner CANNOT read this column at all, so it is correctly left null here, not a gap
      );
    }).toList();
  }

  // POST — Register New Agent. Deterministic MLPI per BR-181/182: "MLPI" +
  // genderDigit + last 8 digits of Aadhaar. RESOLVED (independent review):
  // the original raw client-side multi-insert (persons + business_members +
  // agents + agent_permissions) always failed — persons has no client
  // INSERT policy for any role (0012_rls_module0_identity.sql). Moved to
  // app.register_new_agent (0035), a SECURITY DEFINER RPC doing all four
  // inserts atomically server-side, same pattern as 0034's
  // create_business_with_owner.
  Future<String> registerNewAgent({
    required String businessId,
    required String fullName,
    required String fatherHusbandName,
    required String genderDigit,
    required String mobileNumber,
    required String aadhaarNumber,
  }) async {
    final rows = await _db.schema('app').rpc('register_new_agent', params: {
      'p_business_id': businessId,
      'p_full_name': fullName,
      'p_father_husband_name': fatherHusbandName,
      'p_gender_digit': genderDigit,
      'p_mobile_number': mobileNumber,
      'p_aadhaar_number': aadhaarNumber,
    });
    // RETURNS UUID (agent_id) — a scalar return, not a row set.
    return rows as String;
  }

  // GET /persons?mlid= — search by MLID (C5 Add Existing Agent). Note this
  // is NOT scoped to a business (persons is global, BR-178) — the caller
  // decides what to do with a match (offer "Add" if not already a member).
  Future<AgentSummary?> searchByMlid({required String mlid}) async {
    final rows = await _db.schema('app').rpc('owner_search_person_by_mlid', params: {'p_mlid': mlid});
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final p = list.first;
    return AgentSummary(
      agentId: '', // no agents.agent_id exists yet — this person may not have an Agent role/business membership at all until addExistingAgent runs
      personId: p['person_id']?.toString(),
      fullName: titleCaseName(p['full_name'] as String),
      mlid: p['mlid'] as String,
      phoneNumber: (p['mobile_number'] as String?) ?? '',
      status: 'Pending Invitation',
      businessAccess: '—',
      todaysCollections: 0,
      todaysLoans: 0,
      joinedDate: DateTime.now(),
    );
  }

  Future<void> addExistingAgent({required String businessId, required String personId}) async {
    final membership = await _db
        .from('business_members')
        .insert({
          'person_id': int.parse(personId),
          'business_id': businessId,
          'role': 'Agent',
          'membership_status': 'Pending Invitation',
          'verification_status': 'Pending Verification',
          'onboarding_method': 'ID Lookup',
          'invited_by_person_id': _personId,
        })
        .select('membership_id')
        .single();
    final membershipId = membership['membership_id'] as String;
    final agent = await _db
        .from('agents')
        .insert({'membership_id': membershipId, 'person_id': int.parse(personId), 'joined_date': DateTime.now().toIso8601String().split('T').first})
        .select('agent_id')
        .single();
    final permProfile = await _db.from('agent_permissions').insert({'agent_id': agent['agent_id']}).select('permission_profile_id').single();
    await _db.from('business_members').update({'permission_profile_id': permProfile['permission_profile_id']}).eq('membership_id', membershipId);
  }

  // PATCH /agents/{agent_id} — status change. `status` here is the SCREEN's
  // notion of status (Disable/Suspend/Remove/Reactivate as an action verb);
  // mapped to `agents.current_status` (a state noun: Active/Disabled/
  // Suspended/Removed) — kept intentionally permissive (pass-through) since
  // the exact verb->state mapping is the screen's own vocabulary, not
  // re-derived here to avoid silently reinterpreting it.
  Future<void> updateAgentStatus({required String agentId, required String status}) async {
    await _db.from('agents').update({'current_status': status}).eq('agent_id', agentId);
    // NOTE: does not also flip business_members.membership_status —
    // agents.current_status and business_members.membership_status are
    // separate columns with overlapping-looking value sets (Suspended
    // appears on both). Flagged: whether both need updating together, or
    // whether one is derived from the other, isn't specified in the schema
    // doc — a judgment call, not silently resolved as "obviously both."
  }

  Future<void> updateAgentPermissions({
    required String agentId,
    required Map<String, bool> permissions,
  }) async {
    await _db.from('agent_permissions').update(permissions).eq('agent_id', agentId);
  }

  Future<void> setCompensation({
    required String agentId,
    required double fixedSalary,
    required String salaryCycle,
    double? dailyAllowance,
    double? profitSharePercent,
    String? profitShareEffectiveDate,
  }) async {
    // Effective-dated history table (schema §4.2) — supersede the previous
    // row rather than delete it, per the "no UPDATE that erases the prior
    // value invisibly" convention used throughout the schema.
    final today = DateTime.now().toIso8601String().split('T').first;
    await _db
        .from('agent_compensation_history')
        .update({'superseded_at': DateTime.now().toIso8601String()})
        .eq('agent_id', agentId)
        .isFilter('superseded_at', null);
    await _db.from('agent_compensation_history').insert({
      'agent_id': agentId,
      'fixed_salary_amount': fixedSalary,
      'salary_cycle': salaryCycle,
      'daily_allowance': dailyAllowance,
      'profit_share_percent': profitSharePercent,
      'effective_date': profitShareEffectiveDate ?? today,
    });
  }

  Future<List<CompensationRecord>> fetchCompensationHistory({required String agentId}) async {
    final rows = await _db
        .from('agent_compensation_history')
        .select('fixed_salary_amount, salary_cycle, daily_allowance, profit_share_percent, effective_date')
        .eq('agent_id', agentId)
        .order('effective_date', ascending: false);
    return (rows as List)
        .map((r) => CompensationRecord(
              fixedSalary: (r['fixed_salary_amount'] as num).toDouble(),
              salaryCycle: r['salary_cycle'] as String,
              dailyAllowance: (r['daily_allowance'] as num?)?.toDouble(),
              profitSharePercent: (r['profit_share_percent'] as num?)?.toDouble(),
              effectiveDate: DateTime.parse(r['effective_date'] as String),
            ))
        .toList();
  }

  // BUG FIXED this pass: OW-002's Agent Profile Documents tab was a
  // static label list with onTap: () {} — agent_documents has a real
  // insert path (registration/profile flows) but nothing ever read it
  // back for display. This closes that.
  Future<List<DocumentSummary>> fetchAgentDocuments({required String agentId}) async {
    final rows = await _db
        .from('agent_documents')
        .select('document_type, file_url, uploaded_at')
        .eq('agent_id', agentId)
        .eq('is_archived', false)
        .order('uploaded_at', ascending: false);
    return (rows as List)
        .map((r) => DocumentSummary(
              documentType: r['document_type'] as String,
              fileUrl: r['file_url'] as String,
              uploadedAt: DateTime.parse(r['uploaded_at'] as String),
            ))
        .toList();
  }

  Future<AgentProfile> fetchAgentProfile({required String agentId}) async {
    final agentRow = await _db
        .from('agents')
        .select('''
          agent_id, current_status, joined_date, membership_id,
          persons(full_name, mlid, mobile_number),
          business_members!inner(membership_status)
        ''')
        .eq('agent_id', agentId)
        .single();
    final person = agentRow['persons'] as Map<String, dynamic>?;
    final membership = agentRow['business_members'] as Map<String, dynamic>;

    final permRow = await _db
        .from('agent_permissions')
        .select()
        .eq('agent_id', agentId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final permissions = <String, bool>{};
    if (permRow != null) {
      for (final entry in permRow.entries) {
        if (entry.value is bool) permissions[entry.key] = entry.value as bool;
      }
    }

    final areaRows = await _db
        .from('agent_area_assignments')
        .select('operating_areas!inner(name)')
        .eq('agent_id', agentId)
        .isFilter('removed_at', null);
    final assignedAreas = (areaRows as List)
        .map((r) => ((r['operating_areas'] as Map<String, dynamic>)['name'] as String?) ?? '')
        .where((v) => v.isNotEmpty)
        .toList();

    final compensationHistory = await fetchCompensationHistory(agentId: agentId);

    return AgentProfile(
      summary: AgentSummary(
        agentId: agentId,
        fullName: titleCaseName(person?['full_name'] as String? ?? ''),
        mlid: person?['mlid'] as String? ?? '',
        phoneNumber: (person?['mobile_number'] as String?) ?? '',
        status: membership['membership_status'] as String,
        businessAccess: permissions.values.every((v) => v) ? 'Full Access' : 'Restricted',
        todaysCollections: 0,
        todaysLoans: 0,
        joinedDate: DateTime.parse(agentRow['joined_date'] as String),
      ),
      permissions: permissions,
      assignedAreas: assignedAreas,
      currentCompensation: compensationHistory.isNotEmpty ? compensationHistory.first : null,
      compensationHistory: compensationHistory,
    );
  }
}

// --- Result / model types --------------------------------------------------

class CreateBusinessResult {
  final String businessId;
  final String mlbi; // MANA LINE Business ID, server-generated
  CreateBusinessResult({required this.businessId, required this.mlbi});
}

class OperatingAreaResult {
  final String operatingAreaId;
  final String pinCode;
  final String villageName;
  OperatingAreaResult({
    required this.operatingAreaId,
    required this.pinCode,
    required this.villageName,
  });
}

/// Mirrors GET .../owner-dashboard's single pre-aggregated response —
/// Business Status Bar + Today's Summary + Overview + Snapshots in one call,
/// per OW-001 API BINDING.
class OwnerDashboardData {
  final String businessName;
  final String? logoUrl;
  final bool businessOpen;
  final String? currentCollectionSessionLabel;
  final int pendingApprovals;
  final int pendingInvitations;
  final int pendingAcceptances;
  final bool pendingDayClosure;

  final double openingBalance;
  final double todaysCollections;
  final double todaysLoanDistribution;
  final double todaysInvestments;
  final double todaysWithdrawals;
  final double todaysExpenses;
  final double todaysOutstanding;
  final double todaysDifference;
  final double liveClosingBalance;

  final int totalCustomers;
  final int activeCustomers;
  final int activeLoans;
  final int todaysDueCustomers;
  final double collectedToday;
  final double pendingCollections;
  final int penaltyCustomers;
  final int gracePeriodCustomers;
  final int activeAgents;
  final int activeInvestors;
  final int businessMemberships;
  final double totalInvestment;
  final double interestPayable;

  final int workforceTotalAgents;
  final int workforceActiveToday;
  final int workforcePendingInvitations;
  final int workforcePendingAcceptance;
  final int workforceDisabled;
  final int workforceSuspended;

  final int investorTotal;
  final int investorActive;
  final int investorPendingInvitations;
  final int investorPendingAcceptance;
  final double investorBalance;

  final List<ActivityItem> liveActivity;
  final List<AttentionCard> attentionRequired;
  final List<NotificationItem> notifications;

  OwnerDashboardData({
    required this.businessName,
    this.logoUrl,
    required this.businessOpen,
    this.currentCollectionSessionLabel,
    required this.pendingApprovals,
    required this.pendingInvitations,
    required this.pendingAcceptances,
    required this.pendingDayClosure,
    required this.openingBalance,
    required this.todaysCollections,
    required this.todaysLoanDistribution,
    required this.todaysInvestments,
    required this.todaysWithdrawals,
    required this.todaysExpenses,
    required this.todaysOutstanding,
    required this.todaysDifference,
    required this.liveClosingBalance,
    required this.totalCustomers,
    required this.activeCustomers,
    required this.activeLoans,
    required this.todaysDueCustomers,
    required this.collectedToday,
    required this.pendingCollections,
    required this.penaltyCustomers,
    required this.gracePeriodCustomers,
    required this.activeAgents,
    required this.activeInvestors,
    required this.businessMemberships,
    required this.totalInvestment,
    required this.interestPayable,
    required this.workforceTotalAgents,
    required this.workforceActiveToday,
    required this.workforcePendingInvitations,
    required this.workforcePendingAcceptance,
    required this.workforceDisabled,
    required this.workforceSuspended,
    required this.investorTotal,
    required this.investorActive,
    required this.investorPendingInvitations,
    required this.investorPendingAcceptance,
    required this.investorBalance,
    this.liveActivity = const [],
    this.attentionRequired = const [],
    this.notifications = const [],
  });

  /// Zero-state factory — S3 (brand-new business right after OW-000):
  /// sections show zero counts, never hidden (per OW-001 STATES).
  factory OwnerDashboardData.zero({required String businessName}) => OwnerDashboardData(
        businessName: businessName,
        businessOpen: true,
        pendingApprovals: 0,
        pendingInvitations: 0,
        pendingAcceptances: 0,
        pendingDayClosure: false,
        openingBalance: 0,
        todaysCollections: 0,
        todaysLoanDistribution: 0,
        todaysInvestments: 0,
        todaysWithdrawals: 0,
        todaysExpenses: 0,
        todaysOutstanding: 0,
        todaysDifference: 0,
        liveClosingBalance: 0,
        totalCustomers: 0,
        activeCustomers: 0,
        activeLoans: 0,
        todaysDueCustomers: 0,
        collectedToday: 0,
        pendingCollections: 0,
        penaltyCustomers: 0,
        gracePeriodCustomers: 0,
        activeAgents: 0,
        activeInvestors: 0,
        businessMemberships: 1,
        totalInvestment: 0,
        interestPayable: 0,
        workforceTotalAgents: 0,
        workforceActiveToday: 0,
        workforcePendingInvitations: 0,
        workforcePendingAcceptance: 0,
        workforceDisabled: 0,
        workforceSuspended: 0,
        investorTotal: 0,
        investorActive: 0,
        investorPendingInvitations: 0,
        investorPendingAcceptance: 0,
        investorBalance: 0,
      );
}

class ActivityItem {
  final String type; // Loan Created, Collection Received, Agent Joined, ...
  final String label;
  final DateTime timestamp;
  ActivityItem({required this.type, required this.label, required this.timestamp});
}

class AttentionCard {
  final String type; // Pending Customer Approval, Pending Loan Approval, ...
  final int count;
  final String priority; // High | Medium | Low
  final DateTime lastUpdated;
  AttentionCard({
    required this.type,
    required this.count,
    required this.priority,
    required this.lastUpdated,
  });
}

class NotificationItem {
  final String type;
  final String label;
  final DateTime timestamp;
  final bool read;
  NotificationItem({
    required this.type,
    required this.label,
    required this.timestamp,
    this.read = false,
  });
}

/// C3 Agent List row shape (OW-002).
class AgentSummary {
  final String agentId;
  final String? personId; // populated for pre-membership search results (searchByMlid); agentId is empty in that case
  final String? membershipId; // business_members.membership_id — needed wherever an agent's OWN membership row must be referenced (e.g. account_periods.agent_membership_id), not just their agents.agent_id
  final String fullName;
  final String mlid;
  final String phoneNumber;
  final String status; // Pending Invitation | Pending Acceptance | Active | Temporarily Disabled | Suspended | Removed
  final String businessAccess; // summary label, e.g. "Full Access" / "Restricted"
  final String? currentRoute;
  final double todaysCollections;
  final double todaysLoans;
  final DateTime joinedDate;
  final DateTime? lastLogin;

  AgentSummary({
    required this.agentId,
    this.personId,
    this.membershipId,
    required this.fullName,
    required this.mlid,
    required this.phoneNumber,
    required this.status,
    required this.businessAccess,
    this.currentRoute,
    required this.todaysCollections,
    required this.todaysLoans,
    required this.joinedDate,
    this.lastLogin,
  });
}

class CompensationRecord {
  final double fixedSalary;
  final String salaryCycle;
  final double? dailyAllowance;
  final double? profitSharePercent;
  final DateTime effectiveDate;
  CompensationRecord({
    required this.fixedSalary,
    required this.salaryCycle,
    this.dailyAllowance,
    this.profitSharePercent,
    required this.effectiveDate,
  });
}

/// C6 Agent Profile (tabbed) — full detail shape.
class AgentProfile {
  final AgentSummary summary;
  final Map<String, bool> permissions; // can_collect_payments, can_apply_penalty, can_record_expenses, ...
  final List<String> assignedAreas;
  final CompensationRecord? currentCompensation;
  final List<CompensationRecord> compensationHistory;

  AgentProfile({
    required this.summary,
    required this.permissions,
    required this.assignedAreas,
    this.currentCompensation,
    this.compensationHistory = const [],
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../login_registration/state/auth_api_service.dart';
import '../../../shared/text_utils.dart';
import '../../../shared/mana_time.dart';

/// OW-012 — Business Management. Real Supabase wiring.
class BusinessManagementApiService {
  final Ref ref;
  BusinessManagementApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  int get _personId {
    final id = ref.read(authFlowProvider).personId;
    if (id == null) throw StateError('No logged-in person_id available.');
    return int.parse(id);
  }

  Future<BusinessSummary> _summaryFor(String businessId) async {
    // PERF: three independent reads. Future.wait rather than assign-then-await
    // because a PostgrestBuilder only issues its request when `then` is
    // called, so awaiting them in sequence would still be three serial trips.
    final results = await Future.wait<dynamic>([
      _db.from('businesses').select('business_id, mlbi, business_name, logo_url, business_status').eq('business_id', businessId).single(),
      _db.from('business_members').select('role, membership_status').eq('business_id', businessId),
      _db.from('operating_areas').select('operating_area_id').eq('business_id', businessId),
    ]);
    final b = results[0] as Map<String, dynamic>;
    final members = results[1] as List;
    final areas = results[2] as List;
    int count(String role) => members.where((m) => m['role'] == role && m['membership_status'] == 'Active').length;
    return BusinessSummary(
      businessId: b['business_id'] as String,
      mlbi: b['mlbi'] as String,
      businessName: b['business_name'] as String,
      logoUrl: b['logo_url'] as String?,
      businessStatus: b['business_status'] as String,
      operatingAreaCount: areas.length,
      activeCustomers: count('Customer'),
      activeAgents: count('Agent'),
      activeInvestors: count('Investor'),
    );
  }

  Future<BusinessSummary> createBusiness({
    required String businessName,
    required String registeredFinanceName,
    String? logoUrl,
    String? businessType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
  }) async {
    final mlbi = 'MLBI-${DateTime.now().microsecondsSinceEpoch % 100000000}';
    final rows = await _db.schema('app').rpc('create_business_with_owner', params: {
      'p_mlbi': mlbi,
      'p_business_name': businessName,
      'p_registered_finance_name': registeredFinanceName,
      'p_logo_url': logoUrl,
      'p_business_type': businessType,
      'p_business_address': businessAddress,
      'p_business_phone': businessPhone,
      'p_business_email': businessEmail,
    });
    final businessId = (rows as List).first['business_id'] as String;
    return _summaryFor(businessId);
  }

  Future<List<BusinessSummary>> fetchOwnedBusinesses() async {
    final rows = await _db.from('businesses').select('business_id').eq('owner_person_id', _personId);
    final result = <BusinessSummary>[];
    for (final r in (rows as List)) {
      result.add(await _summaryFor(r['business_id'] as String));
    }
    return result;
  }

  Future<BusinessDetail> fetchBusinessDetail({required String businessId}) async {
    final b = await _db
        .from('businesses')
        .select('registered_finance_name, business_type, business_address, business_phone, business_email, '
            'accepting_new_customers, accepting_new_investors, customer_loan_requests_allowed, migration_locked, '
            'max_investors, max_agents, max_customers')
        .eq('business_id', businessId)
        .single();
    return BusinessDetail(
      summary: await _summaryFor(businessId),
      registeredFinanceName: b['registered_finance_name'] as String,
      businessType: b['business_type'] as String?,
      businessAddress: b['business_address'] as String?,
      businessPhone: b['business_phone'] as String?,
      businessEmail: b['business_email'] as String?,
      acceptingNewCustomers: b['accepting_new_customers'] as bool,
      acceptingNewInvestors: b['accepting_new_investors'] as bool,
      customerLoanRequestsAllowed: b['customer_loan_requests_allowed'] as bool,
      migrationLocked: b['migration_locked'] as bool,
      maxInvestors: b['max_investors'] as int?,
      maxAgents: b['max_agents'] as int?,
      maxCustomers: b['max_customers'] as int?,
    );
  }

  Future<void> updateBusiness({
    required String businessId,
    String? businessName,
    String? logoUrl,
    String? businessType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    bool? acceptingNewCustomers,
    bool? acceptingNewInvestors,
    bool? customerLoanRequestsAllowed,
    int? maxInvestors,
    int? maxAgents,
    int? maxCustomers,
  }) async {
    final patch = <String, dynamic>{};
    if (businessName != null) patch['business_name'] = businessName;
    if (logoUrl != null) patch['logo_url'] = logoUrl;
    if (businessType != null) patch['business_type'] = businessType;
    if (businessAddress != null) patch['business_address'] = businessAddress;
    if (businessPhone != null) patch['business_phone'] = businessPhone;
    if (businessEmail != null) patch['business_email'] = businessEmail;
    if (acceptingNewCustomers != null) patch['accepting_new_customers'] = acceptingNewCustomers;
    if (acceptingNewInvestors != null) patch['accepting_new_investors'] = acceptingNewInvestors;
    if (customerLoanRequestsAllowed != null) patch['customer_loan_requests_allowed'] = customerLoanRequestsAllowed;
    if (maxInvestors != null) patch['max_investors'] = maxInvestors;
    if (maxAgents != null) patch['max_agents'] = maxAgents;
    if (maxCustomers != null) patch['max_customers'] = maxCustomers;
    if (patch.isEmpty) return;
    await _db.from('businesses').update(patch).eq('business_id', businessId);
  }

  Future<List<LocationOption>> searchLocations({String? pinCode, String? search}) async {
    var query = _db.from('locations').select('location_id, pin_code, village_town_name').eq('status', 'Active');
    if (pinCode != null && pinCode.isNotEmpty) query = query.eq('pin_code', pinCode);
    if (search != null && search.isNotEmpty) query = query.ilike('village_town_name', '%$search%');
    final rows = await query.limit(50);
    return (rows as List)
        .map((r) => LocationOption(locationId: r['location_id'] as String, pinCode: r['pin_code'] as String, villageTownName: r['village_town_name'] as String))
        .toList();
  }

  /// Creates a NAMED area and attaches its first village. An area with no
  /// villages is not a thing an Owner can act on, so both writes happen
  /// here rather than leaving an empty area behind if the second fails.
  Future<OperatingAreaSummary> addOperatingArea({
    required String businessId,
    required String name,
    required String locationId,
    int? accountCycleDuration,
    String? accountCycleUnit,
    String? submissionTime,
  }) async {
    final row = await _db
        .from('operating_areas')
        .insert({
          'business_id': businessId,
          'name': name,
          'status': 'Active',
          'account_cycle_duration': accountCycleDuration ?? 3,
          'account_cycle_unit': accountCycleUnit ?? 'Days',
          'submission_time': submissionTime != null ? '$submissionTime:00' : '21:00:00',
        })
        .select('operating_area_id, name, status, account_cycle_duration, account_cycle_unit, submission_time')
        .single();
    final operatingAreaId = row['operating_area_id'] as String;
    final villages = await addVillageToArea(
      businessId: businessId,
      operatingAreaId: operatingAreaId,
      locationId: locationId,
    );
    return OperatingAreaSummary(
      operatingAreaId: operatingAreaId,
      name: row['name'] as String,
      villages: villages,
      status: row['status'] as String,
      accountCycleDuration: row['account_cycle_duration'] as int?,
      accountCycleUnit: row['account_cycle_unit'] as String?,
      submissionTime: row['submission_time'] as String?,
    );
  }

  /// Attaches one more village. Returns the area's full village list so the
  /// caller can replace rather than reconcile.
  ///
  /// The partial unique index `uq_oal_business_location` rejects a village
  /// already live in ANOTHER area of this business — that PostgrestException
  /// is deliberately allowed to reach NetworkErrorHandler rather than being
  /// swallowed, because "this village is already covered" is exactly what
  /// the Owner needs to be told.
  Future<List<AreaVillage>> addVillageToArea({
    required String businessId,
    required String operatingAreaId,
    required String locationId,
  }) async {
    await _db.from('operating_area_locations').insert({
      'operating_area_id': operatingAreaId,
      'location_id': locationId,
      'business_id': businessId,
    });
    final byArea = await fetchAreaVillages(operatingAreaIds: [operatingAreaId]);
    return byArea[operatingAreaId] ?? const [];
  }

  /// Soft-detaches a village — `removed_at`, per the schema's own "nothing
  /// is ever hard deleted" convention, which also frees the village to be
  /// attached to a different area later.
  Future<void> removeVillageFromArea({required String operatingAreaLocationId}) async {
    await _db
        .from('operating_area_locations')
        .update({'removed_at': manaTimestamp()})
        .eq('operating_area_location_id', operatingAreaLocationId);
  }

  /// The "delete area" action OW-012 never had. Sets status Inactive rather
  /// than deleting: account_periods and agent_area_assignments reference
  /// this row, and `operating_areas_agent_select` already treats non-Active
  /// as disabled for the agent.
  /// Removing an area also frees its villages and releases its agents.
  ///
  /// BUG FIXED: this used to flip status only. The village rows stayed
  /// live, so uq_oal_business_location kept holding their slot and adding
  /// one of those villages to another round failed with "already covered
  /// by one of your operating areas" — naming an area the Owner had
  /// already removed. Server-side so the three writes cannot half-apply.
  Future<void> deactivateOperatingArea({required String operatingAreaId}) async {
    await _db.schema('app').rpc('deactivate_operating_area', params: {
      'p_operating_area_id': operatingAreaId,
    });
  }

  Future<void> renameOperatingArea({
    required String operatingAreaId,
    required String name,
  }) async {
    await _db.from('operating_areas').update({'name': name}).eq('operating_area_id', operatingAreaId);
  }

  /// Live villages per area, keyed by area id.
  ///
  /// A separate query rather than an embed on operating_areas: the
  /// `removed_at IS NULL` filter has to apply to the CHILD rows, and
  /// PostgREST's nested-embed filter semantics are a sharp edge this file
  /// already avoids for the agent-assignment lookup below. Same reasoning,
  /// same shape.
  Future<Map<String, List<AreaVillage>>> fetchAreaVillages({
    required List<String> operatingAreaIds,
  }) async {
    if (operatingAreaIds.isEmpty) return {};
    final rows = await _db
        .from('operating_area_locations')
        .select('operating_area_location_id, operating_area_id, location_id, '
            'locations!inner(pin_code, village_town_name)')
        .inFilter('operating_area_id', operatingAreaIds)
        .isFilter('removed_at', null);
    final byArea = <String, List<AreaVillage>>{};
    for (final r in (rows as List)) {
      final location = r['locations'] as Map<String, dynamic>;
      byArea.putIfAbsent(r['operating_area_id'] as String, () => []).add(
            AreaVillage(
              operatingAreaLocationId: r['operating_area_location_id'] as String,
              locationId: r['location_id'] as String,
              pinCode: location['pin_code'] as String,
              villageTownName: location['village_town_name'] as String,
            ),
          );
    }
    for (final list in byArea.values) {
      list.sort((a, b) => a.villageTownName.compareTo(b.villageTownName));
    }
    return byArea;
  }

  Future<List<OperatingAreaSummary>> fetchOperatingAreas({required String businessId}) async {
    final rows = await _db
        .from('operating_areas')
        .select('operating_area_id, name, status, account_cycle_duration, account_cycle_unit, submission_time')
        .eq('business_id', businessId);
    final areas = (rows as List)
        .map((r) => OperatingAreaSummary(
              operatingAreaId: r['operating_area_id'] as String,
              name: r['name'] as String,
              villages: const [],
              status: r['status'] as String,
              accountCycleDuration: r['account_cycle_duration'] as int?,
              accountCycleUnit: r['account_cycle_unit'] as String?,
              submissionTime: r['submission_time'] as String?,
            ))
        .toList();
    if (areas.isEmpty) return areas;

    final areaIds = areas.map((a) => a.operatingAreaId).toList();
    // Villages and agent assignments are independent reads — Future.wait,
    // not assign-then-await, since a PostgrestBuilder is lazy and would
    // otherwise make these two serial round trips.
    final results = await Future.wait<dynamic>([
      fetchAreaVillages(operatingAreaIds: areaIds),
      // Current (non-removed) agent assignment per area — a separate query
      // rather than embedding through agent_area_assignments, so this
      // doesn't need to lean on nested-embed filter semantics for something
      // this simple: which areas are unassigned (no row here) vs assigned.
      _db
          .from('agent_area_assignments')
          .select('operating_area_id, agents!inner(agent_id, membership_id, persons!inner(full_name))')
          .inFilter('operating_area_id', areaIds)
          .isFilter('removed_at', null),
    ]);
    final villagesByArea = results[0] as Map<String, List<AreaVillage>>;
    final assignmentRows = results[1] as List;

    for (final area in areas) {
      area.villages = villagesByArea[area.operatingAreaId] ?? const [];
    }
    // Accumulate rather than overwrite — an area can carry several agents.
    for (final area in areas) {
      area.assignedAgents = [];
    }
    for (final row in assignmentRows) {
      final area = areas.firstWhere((a) => a.operatingAreaId == row['operating_area_id']);
      final agent = row['agents'] as Map<String, dynamic>;
      area.assignedAgents = [
        ...area.assignedAgents,
        AreaAgent(
          agentId: agent['agent_id'] as String,
          membershipId: agent['membership_id'] as String,
          fullName: titleCaseName((agent['persons'] as Map<String, dynamic>)['full_name'] as String),
        ),
      ];
    }
    return areas;
  }

  /// Assigns an Operating Area to an Agent (M4: one atomic, Owner-gated
  /// RPC — app.assign_agent_area — reused by OW-000 Step 6 and OW-012).
  /// The window is time-bounded (valid_from/valid_to); adding an agent
  /// never disturbs other agents on the area (BR-065 shared route), and
  /// re-assigning the same agent refreshes their window. The RPC seeds the
  /// area's first Running Account Period, so Account Periods no longer sit
  /// empty for assigned areas.
  Future<void> assignOperatingAreaToAgent({
    required String businessId,
    required String operatingAreaId,
    required String agentId,
    required String agentMembershipId,
  }) async {
    // M4: the time-bounded assignment and its account-period seed are one
    // atomic, Owner-gated RPC (app.assign_agent_area). It ADDS an agent
    // without touching anyone else on the area (BR-065 shared route); for
    // the same (agent, area) pair it back-dates the prior open window and
    // opens a fresh one (a repeat assign refreshes the window instead of
    // erroring on uq_area_assignment_live).
    await _db.schema('app').rpc('assign_agent_area', params: {
      'p_agent_id': agentId,
      'p_operating_area_id': operatingAreaId,
      'p_frequency': 'Once',
      'p_valid_from': manaBusinessDate(),
    });
  }

  /// Takes ONE named agent off an area, leaving any others in place.
  ///
  /// "Owner-run" is not a thing: an Owner who works a round holds an Agent
  /// membership and is assigned like any other agent. That also removes
  /// the account-period gap the old mode had — agent_membership_id is NOT
  /// NULL, and an Owner-run area could never populate it.
  Future<void> unassignAgentFromArea({
    required String operatingAreaId,
    required String agentId,
  }) async {
    await _db
        .from('agent_area_assignments')
        .update({'removed_at': manaTimestamp()})
        .eq('operating_area_id', operatingAreaId)
        .eq('agent_id', agentId)
        .isFilter('removed_at', null);
  }

  Future<void> createAgreement({
    required String businessId,
    required String agreementType,
    required String sourceType,
    required String contentUrlOrText,
    required String effectiveDate,
  }) async {
    final existing = await _db.from('business_agreements').select('version').eq('business_id', businessId).eq('agreement_type', agreementType).order('version', ascending: false).limit(1).maybeSingle();
    final nextVersion = ((existing?['version'] as int?) ?? 0) + 1;
    await _db.from('business_agreements').insert({
      'business_id': businessId,
      'agreement_type': agreementType,
      'source_type': sourceType,
      'content_url_or_text': contentUrlOrText,
      'version': nextVersion,
      'effective_date': effectiveDate,
    });
  }

  Future<List<AgreementSummary>> fetchAgreements({required String businessId}) async {
    final rows = await _db
        .from('business_agreements')
        .select('agreement_id, agreement_type, source_type, version, effective_date')
        .eq('business_id', businessId)
        .order('version', ascending: false);
    return (rows as List)
        .map((r) => AgreementSummary(
              agreementId: r['agreement_id'] as String,
              agreementType: r['agreement_type'] as String,
              sourceType: r['source_type'] as String,
              version: r['version'] as int,
              effectiveDate: r['effective_date'] as String,
            ))
        .toList();
  }

  Future<List<MemberSummary>> fetchMembers({required String businessId, String? role, String? status}) async {
    // FK hint required: business_members has TWO FKs to persons
    // (person_id AND invited_by_person_id) — an unqualified persons!inner
    // embed is ambiguous and PostgREST throws PGRST201 ("more than one
    // relationship was found") rather than guessing, on every single call.
    var query = _db.from('business_members').select('membership_id, person_id, role, membership_status, persons!business_members_person_id_fkey(full_name)').eq('business_id', businessId);
    if (role != null) query = query.eq('role', role);
    if (status != null) query = query.eq('membership_status', status);
    final rows = await query;
    return (rows as List)
        .map((r) => MemberSummary(
              membershipId: r['membership_id'] as String,
              personId: (r['person_id'] as int).toString(),
              fullName: titleCaseName((r['persons'] as Map<String, dynamic>)['full_name'] as String),
              role: r['role'] as String,
              membershipStatus: r['membership_status'] as String,
            ))
        .toList();
  }

  Future<void> addExistingMember({
    required String businessId,
    required String personId,
    required String role,
    required String onboardingMethod,
  }) async {
    // personId here is actually the MLID typed by the Owner (field is
    // labeled "Person ID / MLID" but no raw person_id is ever realistically
    // typed by a human) — resolve to the real person_id first via the same
    // RPC used by OW-002's "Add Existing Agent," rather than assuming the
    // string is already parseable as an integer (it never was, per
    // independent review — every real MLID input threw FormatException).
    final matches = await _db.schema('app').rpc('owner_search_person_by_mlid', params: {'p_mlid': personId});
    final list = (matches as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      throw StateError('No person found with MLID "$personId".');
    }
    final resolvedPersonId = list.first['person_id'];

    await _db.from('business_members').insert({
      'person_id': resolvedPersonId,
      'business_id': businessId,
      'role': role,
      'membership_status': 'Pending Invitation',
      'verification_status': role == 'Customer' ? 'Not Required' : 'Pending Verification',
      'onboarding_method': onboardingMethod,
      'invited_by_person_id': _personId,
    });
  }

  Future<void> updateMembershipStatus({required String membershipId, required String membershipStatus}) async {
    final patch = <String, dynamic>{'membership_status': membershipStatus};
    if (membershipStatus == 'Active') patch['joined_at'] = manaTimestamp();
    if (membershipStatus == 'Removed') patch['removed_at'] = manaTimestamp();
    await _db.from('business_members').update(patch).eq('membership_id', membershipId);
  }

  Future<List<MembershipRequestSummary>> fetchMembershipRequests({required String businessId}) async {
    final rows = await _db
        .from('membership_requests')
        // FK hint required: membership_requests has TWO FKs to persons
        // (person_id AND reviewed_by_person_id) — same ambiguous-embed
        // shape as business_members above.
        .select('request_id, person_id, requested_role, proposed_investment_amount, remarks, persons!membership_requests_person_id_fkey(full_name)')
        .eq('business_id', businessId)
        .eq('status', 'Pending');
    return (rows as List)
        .map((r) => MembershipRequestSummary(
              requestId: r['request_id'] as String,
              personId: (r['person_id'] as int).toString(),
              fullName: titleCaseName((r['persons'] as Map<String, dynamic>)['full_name'] as String),
              requestedRole: r['requested_role'] as String,
              proposedInvestmentAmount: (r['proposed_investment_amount'] as num?)?.toInt(),
              remarks: r['remarks'] as String?,
            ))
        .toList();
  }

  Future<void> decideMembershipRequest({required String requestId, required String status, String? rejectionReason}) async {
    final req = await _db.from('membership_requests').select('person_id, business_id, requested_role, proposed_investment_amount').eq('request_id', requestId).single();
    await _db.from('membership_requests').update({
      'status': status,
      'reviewed_by_person_id': _personId,
      'reviewed_at': manaTimestamp(),
      'rejection_reason': rejectionReason,
      if (status == 'Rejected') 'cooldown_until': manaTimestampPlus(const Duration(hours: 24)),
    }).eq('request_id', requestId);

    if (status == 'Approved') {
      final role = req['requested_role'] as String;
      final membership = await _db
          .from('business_members')
          .insert({
            'person_id': req['person_id'],
            'business_id': req['business_id'],
            'role': role,
            'membership_status': 'Pending Invitation',
            'verification_status': role == 'Customer' ? 'Not Required' : 'Pending Verification',
            'onboarding_method': 'Direct Registration',
            'invited_by_person_id': _personId,
          })
          .select('membership_id')
          .single();
      if (role == 'Investor') {
        await _db.from('investors').insert({'membership_id': membership['membership_id'], 'person_id': req['person_id']});
      }
    }
  }

  // --- Pre-existing business migration (BR-159) ---------------------------
  //
  // BF for a migrated book is CASH IN HAND:
  //   BF = investment principal - amount given out + already collected
  // and the money still on the line is a separate figure. Confirmed with
  // the Owner 2026-07-31. Every write is server-side so the loan, its
  // schedule and the cash movement cannot half-apply.

  Future<MigrationSummary> fetchMigrationSummary({required String businessId}) async {
    final rows = await _db.schema('app').rpc('migration_summary', params: {
      'p_business_id': businessId,
    });
    final r = ((rows as List).first) as Map<String, dynamic>;
    return MigrationSummary(
      migrationLocked: r['migration_locked'] as bool? ?? true,
      businessStartedAt: r['business_started_at'] == null
          ? null
          : DateTime.parse(r['business_started_at'] as String),
      investmentPrincipal: (r['investment_principal'] as num?)?.toInt() ?? 0,
      migratedLoanCount: (r['migrated_loan_count'] as num?)?.toInt() ?? 0,
      totalGiven: (r['total_given'] as num?)?.toInt() ?? 0,
      totalCollected: (r['total_collected'] as num?)?.toInt() ?? 0,
      lineBalance: (r['line_balance'] as num?)?.toInt() ?? 0,
      bf: (r['bf'] as num?)?.toInt() ?? 0,
      openingBfDeclaredAmount:
          (r['opening_bf_declared_amount'] as num?)?.toInt(),
      openingBfDeclaredOn: r['opening_bf_declared_on'] == null
          ? null
          : DateTime.parse(r['opening_bf_declared_on'] as String),
    );
  }

  /// Declares the cash in hand on migration day.
  ///
  /// The app assumed capital arrives through investors, so BF could only ever
  /// be MOVED, never set. A business running on its own retained profit had no
  /// way in — BF started at 0 and every migrated loan drove it negative.
  ///
  /// Rejected server-side once migration is locked. That is not tidiness:
  /// day_ledger takes its opening balance from this figure and cascades any
  /// change forward, so re-declaring later would rewrite months of closings.
  Future<void> setOpeningBf({
    required String businessId,
    required int amount, // whole rupees (M8)
  }) async {
    await _db.schema('app').rpc('set_opening_bf', params: {
      'p_business_id': businessId,
      'p_amount': amount,
    });
  }

  Future<void> reopenMigration({required String businessId, required String reason}) async {
    await _db.schema('app').rpc('reopen_migration', params: {
      'p_business_id': businessId,
      'p_reason': reason,
    });
  }

  Future<void> lockMigration({required String businessId}) async {
    await _db.schema('app').rpc('lock_migration', params: {'p_business_id': businessId});
  }

  Future<void> migrateLoan({
    required String businessId,
    required String customerId,
    required int amountGiven, // whole rupees (M8)
    required int repaymentAmount,
    required int remainingBalance,
    required DateTime effectiveDate,
    required String repaymentType,
    required int installmentAmount,
    int gracePeriodDays = 0,
    int processingFee = 0,
  }) async {
    await _db.schema('app').rpc('migrate_loan', params: {
      'p_customer_id': customerId,
      'p_business_id': businessId,
      'p_amount_given': amountGiven,
      'p_repayment_amount': repaymentAmount,
      'p_remaining_balance': remainingBalance,
      'p_effective_date': effectiveDate.toIso8601String().split('T').first,
      'p_repayment_type': repaymentType,
      'p_installment_amount': installmentAmount,
      'p_grace_period_days': gracePeriodDays,
      'p_processing_fee': processingFee,
    });
  }

  Future<List<AccountPeriodSummary>> fetchAccountPeriods({required String businessId, String? status, String? operatingAreaId}) async {
    var query = _db
        .from('account_periods')
        .select('account_period_id, operating_area_id, business_start_date, planned_business_end_date, status, '
            'operating_areas(name), business_members(persons!business_members_person_id_fkey(full_name))')
        .eq('business_id', businessId);
    if (status != null) query = query.eq('status', status);
    if (operatingAreaId != null) query = query.eq('operating_area_id', operatingAreaId);
    final rows = await query.order('business_start_date', ascending: false);
    return (rows as List).map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>?;
      final member = r['business_members'] as Map<String, dynamic>?;
      final person = member?['persons'] as Map<String, dynamic>?;
      return AccountPeriodSummary(
        accountPeriodId: r['account_period_id'] as String,
        operatingAreaId: r['operating_area_id'] as String,
        operatingAreaLabel: area?['name'] as String? ?? '',
        agentName: person?['full_name'] as String? ?? 'Unassigned',
        businessStartDate: DateTime.parse(r['business_start_date'] as String),
        plannedBusinessEndDate: DateTime.parse(r['planned_business_end_date'] as String),
        status: r['status'] as String,
      );
    }).toList();
  }

  Future<void> createAccountPeriod({
    required String businessId,
    required String operatingAreaId,
    required String agentMembershipId,
    required String businessStartDate,
  }) async {
    final area = await _db.from('operating_areas').select('account_cycle_duration, account_cycle_unit').eq('operating_area_id', operatingAreaId).single();
    final start = DateTime.parse(businessStartDate);
    final duration = area['account_cycle_duration'] as int;
    final unit = area['account_cycle_unit'] as String;
    final end = switch (unit) {
      'Weeks' => start.add(Duration(days: duration * 7)),
      'Months' => DateTime(start.year, start.month + duration, start.day),
      _ => start.add(Duration(days: duration)),
    };
    await _db.from('account_periods').insert({
      'business_id': businessId,
      'operating_area_id': operatingAreaId,
      'agent_membership_id': agentMembershipId,
      'business_start_date': start.toIso8601String(),
      'planned_business_end_date': end.toIso8601String(),
      'status': 'Running',
    });
  }

  Future<void> approveAccountPeriod({required String accountPeriodId, String? actualEndDate, String? earlyClosureReason}) async {
    await _db.from('account_periods').update({
      'status': 'Approved',
      'approved_by_person_id': _personId,
      'approved_at': manaTimestamp(),
      if (actualEndDate != null) 'actual_end_date': actualEndDate,
      if (earlyClosureReason != null) 'early_closure_reason': earlyClosureReason,
    }).eq('account_period_id', accountPeriodId);
  }

  Future<void> configureAccountCycle({
    required String operatingAreaId,
    required int durationDays,
    required String cycleUnit,
    required String submissionTime,
  }) async {
    await _db.from('operating_areas').update({
      'account_cycle_duration': durationDays,
      'account_cycle_unit': cycleUnit,
      'submission_time': '$submissionTime:00',
    }).eq('operating_area_id', operatingAreaId);
  }
}

final businessManagementApiServiceProvider = Provider<BusinessManagementApiService>((ref) {
  return BusinessManagementApiService(ref: ref);
});

// ============================================================================
// Result / model types
// ============================================================================

/// Business Summary Card row (S1 — Business List).
class BusinessSummary {
  final String businessId;
  final String mlbi;
  final String businessName;
  final String? logoUrl;
  final String businessStatus; // 'Active' | 'Not Started' | 'Suspended'
  final int operatingAreaCount;
  final int activeCustomers;
  final int activeAgents;
  final int activeInvestors;

  BusinessSummary({
    required this.businessId,
    required this.mlbi,
    required this.businessName,
    this.logoUrl,
    required this.businessStatus,
    required this.operatingAreaCount,
    required this.activeCustomers,
    required this.activeAgents,
    required this.activeInvestors,
  });
}

/// Full Business Detail (S3 — tabs for Operating Areas / Agreements /
/// Members / Account Periods).
class BusinessDetail {
  final BusinessSummary summary;
  final String registeredFinanceName;
  final String? businessType;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessEmail;
  final bool acceptingNewCustomers;
  final bool acceptingNewInvestors;
  final bool customerLoanRequestsAllowed;
  final bool migrationLocked; // BR-159 — Business Started, migration mode locked
  final int? maxInvestors;
  final int? maxAgents;
  final int? maxCustomers;

  BusinessDetail({
    required this.summary,
    required this.registeredFinanceName,
    this.businessType,
    this.businessAddress,
    this.businessPhone,
    this.businessEmail,
    required this.acceptingNewCustomers,
    required this.acceptingNewInvestors,
    required this.customerLoanRequestsAllowed,
    required this.migrationLocked,
    this.maxInvestors,
    this.maxAgents,
    this.maxCustomers,
  });
}

class LocationOption {
  final String locationId;
  final String pinCode;
  final String villageTownName;
  LocationOption({required this.locationId, required this.pinCode, required this.villageTownName});
}

/// Migration position for a pre-existing business.
///
/// [bf] is cash in hand. It is now DECLARED by the Owner counting the cash box
/// on migration day, not reconstructed from investment principal and the old
/// book — a business running ten years on its own retained profit has no
/// investment principal to reconstruct from.
///
/// [lineBalance] is the money still with customers and is deliberately NOT
/// inside BF: BF everywhere else in this app means a figure you can physically
/// count.
class MigrationSummary {
  final bool migrationLocked;
  final DateTime? businessStartedAt;
  final int investmentPrincipal;
  final int migratedLoanCount;
  final int totalGiven;
  final int totalCollected;
  final int lineBalance;
  final int bf;

  /// What the Owner declared, and when. Null means never declared — which is
  /// the state that must block finishing migration, since BF would otherwise
  /// go live at whatever happened to be in the column.
  final int? openingBfDeclaredAmount;
  final DateTime? openingBfDeclaredOn;

  MigrationSummary({
    required this.migrationLocked,
    required this.businessStartedAt,
    required this.investmentPrincipal,
    required this.migratedLoanCount,
    required this.totalGiven,
    required this.totalCollected,
    required this.lineBalance,
    required this.bf,
    this.openingBfDeclaredAmount,
    this.openingBfDeclaredOn,
  });

  bool get hasDeclaredBf => openingBfDeclaredAmount != null;
}

/// One agent working an operating area. A round may have several
/// (GLOBAL BR-065 — shared route, individual accountability).
class AreaAgent {
  final String agentId;
  final String membershipId;
  final String fullName;
  AreaAgent({required this.agentId, required this.membershipId, required this.fullName});
}

/// One village attached to an operating area. Carries the join-row id,
/// because detaching addresses the attachment, not the village.
class AreaVillage {
  final String operatingAreaLocationId;
  final String locationId;
  final String pinCode;
  final String villageTownName;
  AreaVillage({
    required this.operatingAreaLocationId,
    required this.locationId,
    required this.pinCode,
    required this.villageTownName,
  });
}

class OperatingAreaSummary {
  final String operatingAreaId;
  /// The round's own name, e.g. "Srikalahasti round". Was implicitly the
  /// single village's name before areas went multi-village.
  final String name;
  /// Live (non-removed) villages. Mutable so fetchOperatingAreas can fill
  /// it in a second pass, same as the assigned-agent fields below.
  List<AreaVillage> villages;
  final String status; // 'Active' | 'Inactive'
  int? accountCycleDuration;
  String? accountCycleUnit;
  String? submissionTime;
  // Empty = nobody is working this area yet. That is an INCOMPLETE area,
  // not a valid configuration: an Owner who works a round themselves does
  // it by holding an Agent membership and being assigned like anyone else.
  // There is no "Owner-run" mode.
  //
  // A LIST, not one agent: GLOBAL BR-065 is explicit that a route may be
  // shared — "Shared route but individual transaction accountability".
  // This used to hold a single agent and every assign superseded the
  // previous one, so a second agent silently unassigned the first.
  List<AreaAgent> assignedAgents;

  OperatingAreaSummary({
    required this.operatingAreaId,
    required this.name,
    required this.villages,
    required this.status,
    this.accountCycleDuration,
    this.accountCycleUnit,
    this.submissionTime,
    this.assignedAgents = const [],
  });

  bool get cycleConfigured => accountCycleDuration != null && accountCycleUnit != null && submissionTime != null;
  /// No agent assigned yet — an area in this state is not being worked and
  /// cannot open an account period.
  bool get isUnassigned => assignedAgents.isEmpty;

  /// "Ravi, Suresh" — every agent working this round.
  String get assignedAgentsLabel => assignedAgents.map((a) => a.fullName).join(', ');

  /// "Srikalahasti, Uranduru" — the villages this round actually covers.
  String get villagesLabel => villages.map((v) => v.villageTownName).join(', ');
}

class AgreementSummary {
  final String agreementId;
  final String agreementType; // 'Customer' | 'Agent' | 'Investor'
  final String sourceType; // 'Uploaded PDF' | 'In-App'
  final int version;
  final String effectiveDate;
  AgreementSummary({
    required this.agreementId,
    required this.agreementType,
    required this.sourceType,
    required this.version,
    required this.effectiveDate,
  });
}

class MemberSummary {
  final String membershipId;
  final String personId;
  final String fullName;
  final String role; // 'Agent' | 'Investor' | 'Customer'
  final String membershipStatus;
  MemberSummary({
    required this.membershipId,
    required this.personId,
    required this.fullName,
    required this.role,
    required this.membershipStatus,
  });
}

class MembershipRequestSummary {
  final String requestId;
  final String personId;
  final String fullName;
  final String requestedRole; // 'Customer' | 'Investor'
  final int? proposedInvestmentAmount;
  final String? remarks;
  MembershipRequestSummary({
    required this.requestId,
    required this.personId,
    required this.fullName,
    required this.requestedRole,
    this.proposedInvestmentAmount,
    this.remarks,
  });
}

class AccountPeriodSummary {
  final String accountPeriodId;
  final String operatingAreaId;
  final String operatingAreaLabel;
  final String agentName;
  final DateTime businessStartDate;
  final DateTime plannedBusinessEndDate;
  final String status; // 'Running' | 'Overdue' | 'Submitted' | 'Approved' | 'Locked'
  AccountPeriodSummary({
    required this.accountPeriodId,
    required this.operatingAreaId,
    required this.operatingAreaLabel,
    required this.agentName,
    required this.businessStartDate,
    required this.plannedBusinessEndDate,
    required this.status,
  });
}

// ============================================================================
// S1 — Business List
// ============================================================================

class BusinessListState {
  final List<BusinessSummary> businesses;
  final bool loading;
  final String? error;

  const BusinessListState({this.businesses = const [], this.loading = false, this.error});

  BusinessListState copyWith({List<BusinessSummary>? businesses, bool? loading, String? error, bool clearError = false}) {
    return BusinessListState(
      businesses: businesses ?? this.businesses,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BusinessListNotifier extends Notifier<BusinessListState> {
  @override
  BusinessListState build() => const BusinessListState();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final businesses = await api.fetchOwnedBusinesses();
      state = state.copyWith(businesses: businesses, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final businessListProvider = NotifierProvider<BusinessListNotifier, BusinessListState>(
  BusinessListNotifier.new,
);

// ============================================================================
// S2 — Create Business (a fresh, standalone form here — distinct from the
// OW-000 wizard notifier, since OW-012's Create Business is a single-step
// action for an *additional* business, not a multi-step first-run wizard)
// ============================================================================

class CreateBusinessFormState {
  final bool submitting;
  final String? error;
  final String? createdBusinessId;

  const CreateBusinessFormState({this.submitting = false, this.error, this.createdBusinessId});

  CreateBusinessFormState copyWith({bool? submitting, String? error, bool clearError = false, String? createdBusinessId}) {
    return CreateBusinessFormState(
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
      createdBusinessId: createdBusinessId ?? this.createdBusinessId,
    );
  }
}

class CreateBusinessFormNotifier extends Notifier<CreateBusinessFormState> {
  @override
  CreateBusinessFormState build() => const CreateBusinessFormState();

  Future<bool> submit({
    required String businessName,
    required String registeredFinanceName,
    String? logoUrl,
    String? businessType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final result = await api.createBusiness(
        businessName: businessName,
        registeredFinanceName: registeredFinanceName,
        logoUrl: logoUrl,
        businessType: businessType,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        businessEmail: businessEmail,
      );
      state = state.copyWith(submitting: false, createdBusinessId: result.businessId);
      // Refresh the list so the new card appears without a manual reload.
      await ref.read(businessListProvider.notifier).load();
      // ALSO refresh authFlowProvider's cached memberships — LR-012
      // (Business Selector / "switch workspace") reads THIS cache, not
      // businessListProvider. Without this, LR-012 kept auto-collapsing
      // back into whichever single business was cached at last login,
      // even after creating additional businesses here (same bug class
      // already fixed once for OW-000's First Business Setup — this
      // parallel "Create Business" flow never adopted it).
      final memberships = await ref.read(authApiServiceProvider).fetchMemberships(ref.read(authFlowProvider).personId!);
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  void reset() => state = const CreateBusinessFormState();
}

final createBusinessFormProvider = NotifierProvider<CreateBusinessFormNotifier, CreateBusinessFormState>(
  CreateBusinessFormNotifier.new,
);

// ============================================================================
// S3 — Business Detail (Operating Areas / Agreements / Members / Account
// Periods tabs), keyed per business via a Family notifier.
// ============================================================================

enum BusinessDetailTab { operatingAreas, agreements, members, accountPeriods }

class BusinessDetailState {
  final BusinessDetail? detail;
  final List<OperatingAreaSummary> operatingAreas;
  final List<AgreementSummary> agreements;
  final List<MemberSummary> members;
  final List<MembershipRequestSummary> membershipRequests;
  final List<AccountPeriodSummary> accountPeriods;
  final BusinessDetailTab activeTab;
  final bool loading;
  final bool submitting;
  final String? error;

  const BusinessDetailState({
    this.detail,
    this.operatingAreas = const [],
    this.agreements = const [],
    this.members = const [],
    this.membershipRequests = const [],
    this.accountPeriods = const [],
    this.activeTab = BusinessDetailTab.operatingAreas,
    this.loading = false,
    this.submitting = false,
    this.error,
  });

  // At-least-1-Operating-Area-mandatory rule (same lock as OW-000).
  bool get hasAtLeastOneOperatingArea => operatingAreas.isNotEmpty;

  BusinessDetailState copyWith({
    BusinessDetail? detail,
    List<OperatingAreaSummary>? operatingAreas,
    List<AgreementSummary>? agreements,
    List<MemberSummary>? members,
    List<MembershipRequestSummary>? membershipRequests,
    List<AccountPeriodSummary>? accountPeriods,
    BusinessDetailTab? activeTab,
    bool? loading,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return BusinessDetailState(
      detail: detail ?? this.detail,
      operatingAreas: operatingAreas ?? this.operatingAreas,
      agreements: agreements ?? this.agreements,
      members: members ?? this.members,
      membershipRequests: membershipRequests ?? this.membershipRequests,
      accountPeriods: accountPeriods ?? this.accountPeriods,
      activeTab: activeTab ?? this.activeTab,
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BusinessDetailNotifier extends FamilyNotifier<BusinessDetailState, String> {
  @override
  BusinessDetailState build(String businessId) => const BusinessDetailState();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      // PERF: six independent reads, previously awaited one at a time.
      //
      // Started here, awaited below. This works because these are `async`
      // functions: calling one runs its body synchronously until its first
      // `await`, which is where the HTTP request is issued — so all six are
      // in flight before the first `await` line below. (A raw
      // PostgrestBuilder would NOT behave this way; it only issues its
      // request when `then` is called, so those need Future.wait instead —
      // see _summaryFor above.)
      //
      // Deliberately not record `.wait`: that throws ParallelWaitError,
      // which NetworkErrorHandler doesn't recognise as a server-reached
      // error, so a real Postgres message would get masked behind the
      // generic "Something went wrong". Awaiting individually keeps the
      // original PostgrestException.
      final detailFuture = api.fetchBusinessDetail(businessId: arg);
      final areasFuture = api.fetchOperatingAreas(businessId: arg);
      final agreementsFuture = api.fetchAgreements(businessId: arg);
      final membersFuture = api.fetchMembers(businessId: arg);
      final requestsFuture = api.fetchMembershipRequests(businessId: arg);
      final periodsFuture = api.fetchAccountPeriods(businessId: arg);

      final detail = await detailFuture;
      final areas = await areasFuture;
      final agreements = await agreementsFuture;
      final members = await membersFuture;
      final requests = await requestsFuture;
      final periods = await periodsFuture;
      state = state.copyWith(
        detail: detail,
        operatingAreas: areas,
        agreements: agreements,
        members: members,
        membershipRequests: requests,
        accountPeriods: periods,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setTab(BusinessDetailTab tab) => state = state.copyWith(activeTab: tab);

  // --- Operating Areas — PIN → Village → Add flow (reuses OW-000 Step 2's
  // pattern; see ow_012_business_management.dart's _OperatingAreaAddPanel).
  Future<bool> addOperatingArea({required String name, required String locationId}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final result = await api.addOperatingArea(businessId: arg, name: name, locationId: locationId);
      state = state.copyWith(operatingAreas: [...state.operatingAreas, result], submitting: false);
      return true;
    } catch (e) {
      final isDuplicate = e is PostgrestException && e.code == '23505';
      state = state.copyWith(
        submitting: false,
        error: isDuplicate ? 'This village is already covered by one of your operating areas.' : e.toString(),
      );
      return false;
    }
  }

  /// Attaches another village to an existing area. Errors are NOT swallowed
  /// into `false` — 23505 here means "already covered by another area",
  /// which the Owner must actually see.
  Future<bool> addVillageToArea({
    required String operatingAreaId,
    required String locationId,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final villages = await api.addVillageToArea(
        businessId: arg,
        operatingAreaId: operatingAreaId,
        locationId: locationId,
      );
      state = state.copyWith(
        operatingAreas: _withVillages(operatingAreaId, villages),
        submitting: false,
      );
      return true;
    } catch (e) {
      final isDuplicate = e is PostgrestException && e.code == '23505';
      state = state.copyWith(
        submitting: false,
        error: isDuplicate
            ? 'This village is already covered by one of your operating areas.'
            : e.toString(),
      );
      return false;
    }
  }

  /// Detaches a village. Refuses to empty an area — an area with no
  /// villages is not something an Agent can be sent to, and the
  /// at-least-one-area rule would be satisfied by a round that covers
  /// nowhere. Remove the area instead.
  /// Detaches a village.
  ///
  /// BUG FIXED: this used to refuse when the area had only one village
  /// left, telling the Owner to remove the whole area instead. Since every
  /// area starts with exactly one village, that made "remove village"
  /// impossible on a fresh area — and it was paired with an add that was
  /// itself broken, so there was no way out. An area with no villages is
  /// now allowed and flagged on the card instead; it simply cannot be
  /// worked until a village is attached.
  Future<bool> removeVillageFromArea({
    required String operatingAreaId,
    required String operatingAreaLocationId,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.removeVillageFromArea(operatingAreaLocationId: operatingAreaLocationId);
      final byArea = await api.fetchAreaVillages(operatingAreaIds: [operatingAreaId]);
      state = state.copyWith(
        operatingAreas: _withVillages(operatingAreaId, byArea[operatingAreaId] ?? const []),
        submitting: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// Removes an area (status → Inactive). Refetches rather than patching
  /// locally, because deactivating can change what the Agent-side reads
  /// see and the area keeps its assignment row.
  Future<bool> removeOperatingArea({required String operatingAreaId}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.deactivateOperatingArea(operatingAreaId: operatingAreaId);
      final areas = await api.fetchOperatingAreas(businessId: arg);
      state = state.copyWith(operatingAreas: areas, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> renameOperatingArea({
    required String operatingAreaId,
    required String name,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.renameOperatingArea(operatingAreaId: operatingAreaId, name: name);
      final areas = await api.fetchOperatingAreas(businessId: arg);
      state = state.copyWith(operatingAreas: areas, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  List<OperatingAreaSummary> _withVillages(String operatingAreaId, List<AreaVillage> villages) {
    return state.operatingAreas.map((a) {
      if (a.operatingAreaId == operatingAreaId) a.villages = villages;
      return a;
    }).toList();
  }

  Future<bool> configureAccountCycle({
    required String operatingAreaId,
    required int durationDays,
    required String cycleUnit,
    required String submissionTime,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.configureAccountCycle(
        operatingAreaId: operatingAreaId,
        durationDays: durationDays,
        cycleUnit: cycleUnit,
        submissionTime: submissionTime,
      );
      final updated = state.operatingAreas.map((a) {
        if (a.operatingAreaId != operatingAreaId) return a;
        a.accountCycleDuration = durationDays;
        a.accountCycleUnit = cycleUnit;
        a.submissionTime = submissionTime;
        return a;
      }).toList();
      state = state.copyWith(operatingAreas: updated, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// Assigns an Agent to an Operating Area (or reassigns it — supersedes
  /// any existing assignment). Refetches operatingAreas AND accountPeriods
  /// together since this can seed the area's first Account Period as a
  /// side effect (see assignOperatingAreaToAgent's own doc).
  Future<bool> assignAreaToAgent({
    required String businessId,
    required String operatingAreaId,
    required String agentId,
    required String agentMembershipId,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.assignOperatingAreaToAgent(
        businessId: businessId,
        operatingAreaId: operatingAreaId,
        agentId: agentId,
        agentMembershipId: agentMembershipId,
      );
      final areas = await api.fetchOperatingAreas(businessId: businessId);
      final periods = await api.fetchAccountPeriods(businessId: businessId);
      state = state.copyWith(operatingAreas: areas, accountPeriods: periods, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> unassignAgent({
    required String businessId,
    required String operatingAreaId,
    required String agentId,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.unassignAgentFromArea(operatingAreaId: operatingAreaId, agentId: agentId);
      final areas = await api.fetchOperatingAreas(businessId: businessId);
      state = state.copyWith(operatingAreas: areas, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  // --- Business Agreements --------------------------------------------------
  Future<bool> createAgreement({
    required String agreementType,
    required String sourceType,
    required String contentUrlOrText,
    required String effectiveDate,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.createAgreement(
        businessId: arg,
        agreementType: agreementType,
        sourceType: sourceType,
        contentUrlOrText: contentUrlOrText,
        effectiveDate: effectiveDate,
      );
      final agreements = await api.fetchAgreements(businessId: arg);
      state = state.copyWith(agreements: agreements, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  // --- Business Members ------------------------------------------------------
  // "Add Existing Agent" — starts the same Owner→Agent invite flow as OW-002.
  Future<bool> addExistingAgent({required String personId}) async {
    return _addExistingMember(personId: personId, role: 'Agent');
  }

  // "Add Existing Customer" — pre-existing/migration customer pattern reused
  // from OW-000 Step 4 (register/enter existing loan handled upstream in
  // OW-004; this call just attaches the membership).
  Future<bool> addExistingCustomer({required String personId}) async {
    return _addExistingMember(personId: personId, role: 'Customer');
  }

  Future<bool> _addExistingMember({required String personId, required String role}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.addExistingMember(
        businessId: arg,
        personId: personId,
        role: role,
        onboardingMethod: 'ID Lookup',
      );
      final members = await api.fetchMembers(businessId: arg);
      state = state.copyWith(members: members, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  // Investor path is Investor-initiated: Owner here only accepts/rejects an
  // incoming request (mirrors OW-003's Owner Accepts/Rejects step).
  Future<bool> decideInvestorRequest({
    required String requestId,
    required bool approve,
    String? rejectionReason,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.decideMembershipRequest(
        requestId: requestId,
        status: approve ? 'Approved' : 'Rejected',
        rejectionReason: rejectionReason,
      );
      final requests = await api.fetchMembershipRequests(businessId: arg);
      final members = await api.fetchMembers(businessId: arg);
      state = state.copyWith(membershipRequests: requests, members: members, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> updateMembershipStatus({required String membershipId, required String status}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.updateMembershipStatus(membershipId: membershipId, membershipStatus: status);
      final members = await api.fetchMembers(businessId: arg);
      state = state.copyWith(members: members, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  // --- Account Periods --------------------------------------------------------
  // Owner Review of a Submitted Account Period — inline here, no separate
  // screen (spec NAVIGATION: "mirrors OW-005's removed separate sign-off
  // screen: Owner approves directly, no extra hop").
  Future<bool> approveAccountPeriod({
    required String accountPeriodId,
    String? actualEndDate,
    String? earlyClosureReason,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.approveAccountPeriod(
        accountPeriodId: accountPeriodId,
        actualEndDate: actualEndDate,
        earlyClosureReason: earlyClosureReason,
      );
      final periods = await api.fetchAccountPeriods(businessId: arg);
      state = state.copyWith(accountPeriods: periods, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }
}

final businessDetailProvider = NotifierProvider.family<BusinessDetailNotifier, BusinessDetailState, String>(
  BusinessDetailNotifier.new,
);

// ============================================================================
// Operating Area add-flow local draft (PIN → Village → Add) — small,
// screen-local helper state, kept separate from BusinessDetailState so the
// in-progress search/selection doesn't get wiped by a detail reload.
// ============================================================================

class OperatingAreaSearchState {
  final String pinCode;
  final List<LocationOption> matches;
  final LocationOption? selected;
  final bool searching;

  const OperatingAreaSearchState({
    this.pinCode = '',
    this.matches = const [],
    this.selected,
    this.searching = false,
  });

  OperatingAreaSearchState copyWith({
    String? pinCode,
    List<LocationOption>? matches,
    LocationOption? selected,
    bool clearSelected = false,
    bool? searching,
  }) {
    return OperatingAreaSearchState(
      pinCode: pinCode ?? this.pinCode,
      matches: matches ?? this.matches,
      selected: clearSelected ? null : (selected ?? this.selected),
      searching: searching ?? this.searching,
    );
  }
}

class OperatingAreaSearchNotifier extends Notifier<OperatingAreaSearchState> {
  @override
  OperatingAreaSearchState build() => const OperatingAreaSearchState();

  Future<void> searchByPin(String pinCode) async {
    state = state.copyWith(pinCode: pinCode, searching: true, clearSelected: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final matches = await api.searchLocations(pinCode: pinCode);
      state = state.copyWith(matches: matches, searching: false);
    } catch (_) {
      state = state.copyWith(searching: false);
    }
  }

  void selectVillage(LocationOption option) => state = state.copyWith(selected: option);

  void reset() => state = const OperatingAreaSearchState();
}

final operatingAreaSearchProvider = NotifierProvider<OperatingAreaSearchNotifier, OperatingAreaSearchState>(
  OperatingAreaSearchNotifier.new,
);

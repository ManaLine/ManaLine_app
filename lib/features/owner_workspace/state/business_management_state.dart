import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../../login_registration/state/auth_api_service.dart';
import '../../../shared/text_utils.dart';

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

  Future<OperatingAreaSummary> addOperatingArea({
    required String businessId,
    required String locationId,
    int? accountCycleDuration,
    String? accountCycleUnit,
    String? submissionTime,
  }) async {
    final row = await _db
        .from('operating_areas')
        .insert({
          'business_id': businessId,
          'location_id': locationId,
          'status': 'Active',
          'account_cycle_duration': accountCycleDuration ?? 3,
          'account_cycle_unit': accountCycleUnit ?? 'Days',
          'submission_time': submissionTime != null ? '$submissionTime:00' : '21:00:00',
        })
        .select('operating_area_id, status, account_cycle_duration, account_cycle_unit, submission_time, '
            'locations!inner(pin_code, village_town_name)')
        .single();
    final location = row['locations'] as Map<String, dynamic>;
    return OperatingAreaSummary(
      operatingAreaId: row['operating_area_id'] as String,
      pinCode: location['pin_code'] as String,
      villageTownName: location['village_town_name'] as String,
      status: row['status'] as String,
      accountCycleDuration: row['account_cycle_duration'] as int?,
      accountCycleUnit: row['account_cycle_unit'] as String?,
      submissionTime: row['submission_time'] as String?,
    );
  }

  Future<List<OperatingAreaSummary>> fetchOperatingAreas({required String businessId}) async {
    final rows = await _db
        .from('operating_areas')
        .select('operating_area_id, status, account_cycle_duration, account_cycle_unit, submission_time, '
            'locations!inner(pin_code, village_town_name)')
        .eq('business_id', businessId);
    final areas = (rows as List).map((r) {
      final location = r['locations'] as Map<String, dynamic>;
      return OperatingAreaSummary(
        operatingAreaId: r['operating_area_id'] as String,
        pinCode: location['pin_code'] as String,
        villageTownName: location['village_town_name'] as String,
        status: r['status'] as String,
        accountCycleDuration: r['account_cycle_duration'] as int?,
        accountCycleUnit: r['account_cycle_unit'] as String?,
        submissionTime: r['submission_time'] as String?,
      );
    }).toList();
    if (areas.isEmpty) return areas;

    // Current (non-removed) agent assignment per area — a separate query
    // rather than embedding through agent_area_assignments, so this
    // doesn't need to lean on nested-embed filter semantics for something
    // this simple: which areas are Owner-run (no row here) vs assigned.
    final areaIds = areas.map((a) => a.operatingAreaId).toList();
    final assignmentRows = await _db
        .from('agent_area_assignments')
        .select('operating_area_id, agents!inner(agent_id, membership_id, persons!inner(full_name))')
        .inFilter('operating_area_id', areaIds)
        .isFilter('removed_at', null);
    for (final row in (assignmentRows as List)) {
      final area = areas.firstWhere((a) => a.operatingAreaId == row['operating_area_id']);
      final agent = row['agents'] as Map<String, dynamic>;
      area.assignedAgentId = agent['agent_id'] as String;
      area.assignedAgentMembershipId = agent['membership_id'] as String;
      area.assignedAgentName = titleCaseName((agent['persons'] as Map<String, dynamic>)['full_name'] as String);
    }
    return areas;
  }

  /// Assigns an Operating Area to an Agent (mirrors OW-000 Step 6's
  /// assignAreaToAgent, reused here for post-setup reassignment/first
  /// assignment via OW-012). Supersedes any existing assignment for the
  /// area — soft-removed, not deleted, matching this schema's
  /// history-preserving convention everywhere else (agent_area_
  /// assignments.removed_at, same pattern as business_members.removed_at).
  /// Also seeds the area's first Account Period if it doesn't have a
  /// Running one yet — createAccountPeriod() existed but nothing ever
  /// called it, which is why Account Periods showed empty for every area
  /// regardless of how many were actually being worked.
  Future<void> assignOperatingAreaToAgent({
    required String businessId,
    required String operatingAreaId,
    required String agentId,
    required String agentMembershipId,
  }) async {
    await _db
        .from('agent_area_assignments')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('operating_area_id', operatingAreaId)
        .isFilter('removed_at', null);
    await _db.from('agent_area_assignments').insert({
      'agent_id': agentId,
      'operating_area_id': operatingAreaId,
    });
    await _seedFirstAccountPeriodIfNeeded(
      businessId: businessId,
      operatingAreaId: operatingAreaId,
      agentMembershipId: agentMembershipId,
    );
  }

  /// Marks an Operating Area Owner-run — per the schema's own design
  /// (see owner_api_service.dart's markAreaOwnerRun), this is really just
  /// "no agent_area_assignments row", so clearing any existing one IS the
  /// action. Deliberately does NOT auto-seed an Account Period the way
  /// assignOperatingAreaToAgent does: account_periods.agent_membership_id
  /// is NOT NULL, and nothing in the locked schema says what value an
  /// Owner-run period should carry there (the Owner's own membership_id?
  /// a sentinel?) — flagged rather than guessed, same as the schema gaps
  /// already flagged elsewhere in this file.
  Future<void> markOperatingAreaOwnerRun({required String operatingAreaId}) async {
    await _db
        .from('agent_area_assignments')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('operating_area_id', operatingAreaId)
        .isFilter('removed_at', null);
  }

  Future<void> _seedFirstAccountPeriodIfNeeded({
    required String businessId,
    required String operatingAreaId,
    required String agentMembershipId,
  }) async {
    final existing = await _db
        .from('account_periods')
        .select('account_period_id')
        .eq('operating_area_id', operatingAreaId)
        .eq('status', 'Running')
        .maybeSingle();
    if (existing != null) return;
    await createAccountPeriod(
      businessId: businessId,
      operatingAreaId: operatingAreaId,
      agentMembershipId: agentMembershipId,
      businessStartDate: DateTime.now().toIso8601String(),
    );
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
    if (membershipStatus == 'Active') patch['joined_at'] = DateTime.now().toIso8601String();
    if (membershipStatus == 'Removed') patch['removed_at'] = DateTime.now().toIso8601String();
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
              proposedInvestmentAmount: (r['proposed_investment_amount'] as num?)?.toDouble(),
              remarks: r['remarks'] as String?,
            ))
        .toList();
  }

  Future<void> decideMembershipRequest({required String requestId, required String status, String? rejectionReason}) async {
    final req = await _db.from('membership_requests').select('person_id, business_id, requested_role, proposed_investment_amount').eq('request_id', requestId).single();
    await _db.from('membership_requests').update({
      'status': status,
      'reviewed_by_person_id': _personId,
      'reviewed_at': DateTime.now().toIso8601String(),
      'rejection_reason': rejectionReason,
      if (status == 'Rejected') 'cooldown_until': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
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

  Future<List<AccountPeriodSummary>> fetchAccountPeriods({required String businessId, String? status, String? operatingAreaId}) async {
    var query = _db
        .from('account_periods')
        .select('account_period_id, operating_area_id, business_start_date, planned_business_end_date, status, '
            'operating_areas(locations(village_town_name)), business_members(persons!business_members_person_id_fkey(full_name))')
        .eq('business_id', businessId);
    if (status != null) query = query.eq('status', status);
    if (operatingAreaId != null) query = query.eq('operating_area_id', operatingAreaId);
    final rows = await query.order('business_start_date', ascending: false);
    return (rows as List).map((r) {
      final area = r['operating_areas'] as Map<String, dynamic>?;
      final location = area?['locations'] as Map<String, dynamic>?;
      final member = r['business_members'] as Map<String, dynamic>?;
      final person = member?['persons'] as Map<String, dynamic>?;
      return AccountPeriodSummary(
        accountPeriodId: r['account_period_id'] as String,
        operatingAreaId: r['operating_area_id'] as String,
        operatingAreaLabel: location?['village_town_name'] as String? ?? '',
        agentName: person?['full_name'] as String? ?? 'Owner-run',
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
      'approved_at': DateTime.now().toIso8601String(),
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

class OperatingAreaSummary {
  final String operatingAreaId;
  final String pinCode;
  final String villageTownName;
  final String status; // 'Active' | 'Inactive'
  int? accountCycleDuration;
  String? accountCycleUnit;
  String? submissionTime;
  // Null on all three = Owner-run (absence of an agent_area_assignments
  // row IS "Owner-run" per this schema — there's no separate flag).
  String? assignedAgentId;
  String? assignedAgentMembershipId;
  String? assignedAgentName;

  OperatingAreaSummary({
    required this.operatingAreaId,
    required this.pinCode,
    required this.villageTownName,
    required this.status,
    this.accountCycleDuration,
    this.accountCycleUnit,
    this.submissionTime,
    this.assignedAgentId,
    this.assignedAgentMembershipId,
    this.assignedAgentName,
  });

  bool get cycleConfigured => accountCycleDuration != null && accountCycleUnit != null && submissionTime != null;
  bool get isOwnerRun => assignedAgentId == null;
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
  final double? proposedInvestmentAmount;
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
  Future<bool> addOperatingArea({required String locationId}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final result = await api.addOperatingArea(businessId: arg, locationId: locationId);
      state = state.copyWith(operatingAreas: [...state.operatingAreas, result], submitting: false);
      return true;
    } catch (e) {
      final isDuplicate = e is PostgrestException && e.code == '23505';
      state = state.copyWith(
        submitting: false,
        error: isDuplicate ? 'This village is already one of your operating areas.' : e.toString(),
      );
      return false;
    }
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

  Future<bool> markAreaOwnerRun({required String businessId, required String operatingAreaId}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      await api.markOperatingAreaOwnerRun(operatingAreaId: operatingAreaId);
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

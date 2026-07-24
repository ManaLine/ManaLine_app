import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/agent_dashboard_state.dart' show AgentAreaAssignment;

/// AG-009 Profile — real Supabase wiring.
///
/// INTERFACE GAP RESOLVED (this session): the original stub flagged that
/// `AgentDashboardData` (agent_dashboard_state.dart) had no compensation
/// fields to link out to. That gap is closed — the version of
/// agent_dashboard_state.dart already delivered this session DOES define
/// fixedSalary/salaryCycleStatus (sourced from agent_compensation_history)
/// on AgentDashboardData. fetchCompensationSummary below queries the same
/// table directly with the same minimal single-row shape this file's own
/// AgentCompensationSummary already expects, rather than depending on
/// agent_dashboard_state.dart's full dashboard fetch just for two fields.
class AgentProfileApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<AgentProfileSummary> fetchProfile({required String personId}) async {
    final row = await _db
        .from('persons')
        .select('full_name, mlid, mobile_number, profile_photo_url')
        .eq('person_id', int.parse(personId))
        .single();
    final agentRow = await _db
        .from('agents')
        .select('joined_date, current_status')
        .eq('person_id', int.parse(personId))
        .limit(1)
        .maybeSingle();

    return AgentProfileSummary(
      fullName: row['full_name'] as String? ?? '',
      mlid: row['mlid'] as String? ?? '',
      phoneNumber: row['mobile_number'] as String?,
      profilePhotoUrl: row['profile_photo_url'] as String?,
      joinedDate: agentRow != null ? DateTime.parse(agentRow['joined_date'] as String) : DateTime.now(),
      currentStatus: agentRow?['current_status'] as String? ?? 'Active',
    );
  }

  Future<List<AgentBusinessMembership>> fetchMemberships({required String personId}) async {
    final rows = await _db
        .from('business_members')
        .select('business_id, membership_status, businesses!inner(business_name)')
        .eq('person_id', int.parse(personId));
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return AgentBusinessMembership(
        businessId: m['business_id'] as String,
        businessName: (m['businesses'] as Map<String, dynamic>)['business_name'] as String? ?? '',
        membershipStatus: m['membership_status'] as String,
      );
    }).toList();
  }

  Future<List<AgentAreaAssignment>> fetchAreaAssignments({required String agentId}) async {
    final rows = await _db
        .from('agent_area_assignments')
        .select('operating_area_id, operating_areas!inner(status, locations!inner(village_town_name))')
        .eq('agent_id', agentId)
        .isFilter('removed_at', null);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final area = m['operating_areas'] as Map<String, dynamic>;
      final location = area['locations'] as Map<String, dynamic>;
      return AgentAreaAssignment(
        operatingAreaId: m['operating_area_id'] as String,
        areaName: location['village_town_name'] as String? ?? '',
        enabled: area['status'] == 'Active',
      );
    }).toList();
  }

  Future<AgentCompensationSummary> fetchCompensationSummary({required String businessId, required String agentId}) async {
    final row = await _db
        .from('agent_compensation_history')
        .select('fixed_salary_amount, salary_cycle')
        .eq('agent_id', agentId)
        .isFilter('superseded_at', null) // current/active row only
        .order('effective_date', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return AgentCompensationSummary(fixedSalary: 0, salaryCycleStatus: 'Not set');
    return AgentCompensationSummary(
      fixedSalary: (row['fixed_salary_amount'] as num).toDouble(),
      salaryCycleStatus: row['salary_cycle'] as String? ?? '',
    );
  }
}

final agentProfileApiServiceProvider = Provider<AgentProfileApiService>((ref) {
  return AgentProfileApiService();
});

// ============================================================================
// Models
// ============================================================================

class AgentProfileSummary {
  final String fullName;
  final String mlid;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final DateTime joinedDate;
  final String currentStatus;

  AgentProfileSummary({
    required this.fullName,
    required this.mlid,
    this.phoneNumber,
    this.profilePhotoUrl,
    required this.joinedDate,
    required this.currentStatus,
  });
}

enum MembershipRole { owner, agent, investor, customer }

extension MembershipRoleLabel on MembershipRole {
  String get label => switch (this) {
        MembershipRole.owner => 'Owner',
        MembershipRole.agent => 'Agent',
        MembershipRole.investor => 'Investor',
        MembershipRole.customer => 'Customer',
      };
}

class AgentBusinessMembership {
  final String businessId;
  final String businessName;
  final String membershipStatus;

  AgentBusinessMembership({
    required this.businessId,
    required this.businessName,
    required this.membershipStatus,
  });
}

class AgentCompensationSummary {
  final double fixedSalary;
  final String salaryCycleStatus;

  AgentCompensationSummary({
    required this.fixedSalary,
    required this.salaryCycleStatus,
  });
}

// ============================================================================
// State
// ============================================================================

class AgentProfileState {
  final AgentProfileSummary? profile;
  final List<AgentBusinessMembership> memberships;
  final List<AgentAreaAssignment> areaAssignments;
  final AgentCompensationSummary? compensationSummary;
  final bool loading;
  final String? error;

  const AgentProfileState({
    this.profile,
    this.memberships = const [],
    this.areaAssignments = const [],
    this.compensationSummary,
    this.loading = false,
    this.error,
  });

  List<AgentAreaAssignment> get enabledAreas => areaAssignments.where((a) => a.enabled).toList();

  AgentProfileState copyWith({
    AgentProfileSummary? profile,
    List<AgentBusinessMembership>? memberships,
    List<AgentAreaAssignment>? areaAssignments,
    AgentCompensationSummary? compensationSummary,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AgentProfileState(
      profile: profile ?? this.profile,
      memberships: memberships ?? this.memberships,
      areaAssignments: areaAssignments ?? this.areaAssignments,
      compensationSummary: compensationSummary ?? this.compensationSummary,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AgentProfileNotifier extends Notifier<AgentProfileState> {
  @override
  AgentProfileState build() => const AgentProfileState();

  Future<void> load({required String personId, required String agentId, required String businessId}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(agentProfileApiServiceProvider);
      final results = await Future.wait([
        api.fetchProfile(personId: personId),
        api.fetchMemberships(personId: personId),
        api.fetchAreaAssignments(agentId: agentId),
        api.fetchCompensationSummary(businessId: businessId, agentId: agentId),
      ]);
      state = state.copyWith(
        profile: results[0] as AgentProfileSummary,
        memberships: results[1] as List<AgentBusinessMembership>,
        areaAssignments: results[2] as List<AgentAreaAssignment>,
        compensationSummary: results[3] as AgentCompensationSummary,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final agentProfileProvider = NotifierProvider<AgentProfileNotifier, AgentProfileState>(
  AgentProfileNotifier.new,
);

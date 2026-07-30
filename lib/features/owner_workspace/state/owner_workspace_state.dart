import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'owner_api_service.dart';

/// Shared Owner Workspace API instance. Same base-URL-stub convention as
/// authApiServiceProvider would be (login_registration doesn't expose one
/// as a provider today — AuthApiService is constructed inline per screen —
/// but OW-002 needs the service across list + drill-in + sub-flows, so it's
/// providerized here rather than re-instantiated per screen).
final ownerApiServiceProvider = Provider<OwnerApiService>((ref) {
  return OwnerApiService(ref: ref);
});

// ============================================================================
// OW-000 — First Business Setup Wizard
// ============================================================================

enum BusinessSetupStep { createBusiness, operatingAreas, accountCycle, existingMembers, agreements, assignAreas }

class OperatingAreaDraft {
  final String localId; // client-side id until server confirms
  final String pinCode;
  final String villageName;
  int? accountCycleDurationDays;
  String? accountCycleSubmissionTime;
  bool ownerRun;
  String? assignedAgentId;
  String? assignedAgentName;

  OperatingAreaDraft({
    required this.localId,
    required this.pinCode,
    required this.villageName,
    this.accountCycleDurationDays,
    this.accountCycleSubmissionTime,
    this.ownerRun = false,
    this.assignedAgentId,
    this.assignedAgentName,
  });

  bool get cycleConfigured => accountCycleDurationDays != null && accountCycleSubmissionTime != null;
  bool get resolved => ownerRun || assignedAgentId != null;
}

/// Client-side draft state for the OW-000 wizard. Per spec's own NAVIGATION
/// section: "Exit without completing... in-progress wizard state persists
/// as a draft... stored client-side (local device state, not a new
/// server-side table/endpoint)." Only Step 6 completion ("Start Business")
/// writes anything beyond Steps 1-2's own create calls (business + areas
/// are created as the Owner completes each step, not batched at the end —
/// per OW-000's own per-step API BINDING).
class BusinessSetupState {
  final BusinessSetupStep currentStep;
  final bool isAdditionalBusiness; // drives header text: "First Business Setup" vs "Set Up New Business"

  // Step 1
  final String? businessId; // set once POST /businesses succeeds
  final String? mlbi;
  final String businessName;
  final String registeredFinanceName;
  final String? logoUrl;
  final String? businessType;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessEmail;

  // Step 2
  final List<OperatingAreaDraft> operatingAreas;

  // Step 4 (optional)
  final bool existingMembersStepVisited;

  // Step 5 (optional)
  final bool agreementsStepVisited;
  final List<String> agreementTypesCreated;

  final bool submitting;
  final String? error;

  const BusinessSetupState({
    this.currentStep = BusinessSetupStep.createBusiness,
    this.isAdditionalBusiness = false,
    this.businessId,
    this.mlbi,
    this.businessName = '',
    this.registeredFinanceName = '',
    this.logoUrl,
    this.businessType,
    this.businessAddress,
    this.businessPhone,
    this.businessEmail,
    this.operatingAreas = const [],
    this.existingMembersStepVisited = false,
    this.agreementsStepVisited = false,
    this.agreementTypesCreated = const [],
    this.submitting = false,
    this.error,
  });

  // Step 1 mandatory: Business Name + Registered Finance Name.
  bool get step1Complete => businessId != null;

  // Step 2 mandatory: at least 1 Operating Area (CONFIRMED — locked decision).
  bool get step2Complete => operatingAreas.isNotEmpty;

  // Step 3 gate — RELAXED per explicit product decision (same reasoning
  // as step6Complete below): unlocks once AT LEAST ONE area has its cycle
  // configured, not every area. Was previously "every area" — left as-is
  // here would have made the step6Complete relaxation pointless, since
  // the wizard couldn't have reached Step 6 with partial areas at all.
  bool get step3Complete =>
      operatingAreas.isNotEmpty && operatingAreas.any((a) => a.cycleConfigured);

  // Step 6 gate — RELAXED per explicit product decision: unlocks once AT
  // LEAST ONE area is resolved (owner-run or assigned to an agent), not
  // requiring every area. Areas left unresolved here remain reachable
  // later via Business Management (OW-012) — the Owner isn't blocked from
  // starting the business just because they haven't decided every area's
  // handling yet.
  bool get step6Complete =>
      operatingAreas.isNotEmpty && operatingAreas.any((a) => a.resolved);

  // "Start Business" enablement — Steps 1-3 + 6 mandatory; 4-5 optional.
  bool get canStartBusiness => step1Complete && step2Complete && step3Complete && step6Complete;

  BusinessSetupState copyWith({
    BusinessSetupStep? currentStep,
    bool? isAdditionalBusiness,
    String? businessId,
    String? mlbi,
    String? businessName,
    String? registeredFinanceName,
    String? logoUrl,
    String? businessType,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    List<OperatingAreaDraft>? operatingAreas,
    bool? existingMembersStepVisited,
    bool? agreementsStepVisited,
    List<String>? agreementTypesCreated,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return BusinessSetupState(
      currentStep: currentStep ?? this.currentStep,
      isAdditionalBusiness: isAdditionalBusiness ?? this.isAdditionalBusiness,
      businessId: businessId ?? this.businessId,
      mlbi: mlbi ?? this.mlbi,
      businessName: businessName ?? this.businessName,
      registeredFinanceName: registeredFinanceName ?? this.registeredFinanceName,
      logoUrl: logoUrl ?? this.logoUrl,
      businessType: businessType ?? this.businessType,
      businessAddress: businessAddress ?? this.businessAddress,
      businessPhone: businessPhone ?? this.businessPhone,
      businessEmail: businessEmail ?? this.businessEmail,
      operatingAreas: operatingAreas ?? this.operatingAreas,
      existingMembersStepVisited: existingMembersStepVisited ?? this.existingMembersStepVisited,
      agreementsStepVisited: agreementsStepVisited ?? this.agreementsStepVisited,
      agreementTypesCreated: agreementTypesCreated ?? this.agreementTypesCreated,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BusinessSetupNotifier extends Notifier<BusinessSetupState> {
  @override
  BusinessSetupState build() => const BusinessSetupState();

  void start({required bool isAdditionalBusiness}) {
    state = BusinessSetupState(isAdditionalBusiness: isAdditionalBusiness);
  }

  void goToStep(BusinessSetupStep step) => state = state.copyWith(currentStep: step, clearError: true);

  Future<bool> submitStep1({
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
      final api = ref.read(ownerApiServiceProvider);
      final result = await api.createBusiness(
        businessName: businessName,
        registeredFinanceName: registeredFinanceName,
        logoUrl: logoUrl,
        businessType: businessType,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        businessEmail: businessEmail,
      );
      state = state.copyWith(
        businessId: result.businessId,
        mlbi: result.mlbi,
        businessName: businessName,
        registeredFinanceName: registeredFinanceName,
        logoUrl: logoUrl,
        businessType: businessType,
        businessAddress: businessAddress,
        businessPhone: businessPhone,
        businessEmail: businessEmail,
        submitting: false,
        currentStep: BusinessSetupStep.operatingAreas,
      );
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> addOperatingArea({required String pinCode, required String villageId, required String villageName}) async {
    if (state.businessId == null) return false;
    if (state.operatingAreas.any((a) => a.pinCode == pinCode && a.villageName == villageName)) {
      state = state.copyWith(error: '"$villageName" is already one of your operating areas.');
      return false;
    }
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      final result = await api.addOperatingArea(
        businessId: state.businessId!,
        pinCode: pinCode,
        villageId: villageId,
      );
      final updated = [
        ...state.operatingAreas,
        OperatingAreaDraft(
          localId: result.operatingAreaId,
          pinCode: result.pinCode,
          villageName: result.villageName,
        ),
      ];
      state = state.copyWith(operatingAreas: updated, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  void removeOperatingArea(String localId) {
    state = state.copyWith(
      operatingAreas: state.operatingAreas.where((a) => a.localId != localId).toList(),
    );
  }

  Future<bool> configureAccountCycle({
    required String areaLocalId,
    required int durationDays,
    required String submissionTime,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.setAccountCycleConfig(
        operatingAreaId: areaLocalId,
        durationDays: durationDays,
        submissionTime: submissionTime,
      );
      final updated = state.operatingAreas.map((a) {
        if (a.localId != areaLocalId) return a;
        a.accountCycleDurationDays = durationDays;
        a.accountCycleSubmissionTime = submissionTime;
        return a;
      }).toList();
      state = state.copyWith(operatingAreas: updated, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  void markExistingMembersStepVisited() => state = state.copyWith(existingMembersStepVisited: true);

  Future<bool> createAgreement({required String agreementType, required String documentUrl}) async {
    if (state.businessId == null) return false;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.createAgreement(
        businessId: state.businessId!,
        agreementType: agreementType,
        documentUrl: documentUrl,
      );
      state = state.copyWith(
        agreementsStepVisited: true,
        agreementTypesCreated: [...state.agreementTypesCreated, agreementType],
        submitting: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> assignAreaToAgent({required String areaLocalId, required String agentId, required String agentName}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.assignAreaToAgent(operatingAreaId: areaLocalId, agentId: agentId);
      final updated = state.operatingAreas.map((a) {
        if (a.localId != areaLocalId) return a;
        a.ownerRun = false;
        a.assignedAgentId = agentId;
        a.assignedAgentName = agentName;
        return a;
      }).toList();
      state = state.copyWith(operatingAreas: updated, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  Future<bool> markAreaOwnerRun({required String areaLocalId}) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.markAreaOwnerRun(operatingAreaId: areaLocalId);
      final updated = state.operatingAreas.map((a) {
        if (a.localId != areaLocalId) return a;
        a.ownerRun = true;
        a.assignedAgentId = null;
        a.assignedAgentName = null;
        return a;
      }).toList();
      state = state.copyWith(operatingAreas: updated, submitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return false;
    }
  }

  /// "Start Business" — irreversible per BR-159. Returns the businessId on
  /// success so the caller can route to OW-001 scoped to it.
  Future<String?> startBusiness() async {
    if (!state.canStartBusiness || state.businessId == null) return null;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.startBusiness(businessId: state.businessId!);
      state = state.copyWith(submitting: false);
      return state.businessId;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return null;
    }
  }

  void reset() => state = const BusinessSetupState();
}

final businessSetupProvider = NotifierProvider<BusinessSetupNotifier, BusinessSetupState>(
  BusinessSetupNotifier.new,
);

// ============================================================================
// OW-001 — Owner Home Dashboard
// ============================================================================

class OwnerDashboardNotifier extends AsyncNotifier<OwnerDashboardData> {
  @override
  Future<OwnerDashboardData> build() async {
    // Real screen passes the active businessId in; scaffolded default keeps
    // build() side-effect-free per Riverpod convention. Screen calls
    // load(businessId) from initState/postFrame the same way LR-012 defers
    // its routing decision.
    return OwnerDashboardData.zero(businessName: '');
  }

  /// Which business the currently-held value belongs to. Needed because this
  /// same method serves both "revisit the dashboard" and "switch business" —
  /// see the guard in [load].
  String? _loadedForBusinessId;

  Future<void> load(String businessId) async {
    // PERF/UX: only blank the screen to a spinner when there is nothing
    // useful to show. The screen calls this from initState on every visit, so
    // unconditionally setting AsyncLoading meant navigating back to the
    // dashboard always flashed a full-screen spinner over data that was
    // already loaded and still valid. Keeping the previous value lets the
    // refetch happen behind the existing content — figures appear instantly
    // and update in place a moment later. Nothing goes stale: the fetch still
    // runs every visit, only the spinner is gone.
    //
    // The businessId check is not optional. This method is also the
    // "Business Switched" path, and holding the old value across a switch
    // would leave one business's outstanding balances on screen while a
    // different business loaded — actively misleading in a financial app. On
    // a switch we blank to loading as before.
    final sameBusiness = _loadedForBusinessId == businessId;
    if (!state.hasValue || !sameBusiness) state = const AsyncLoading();

    final next = await AsyncValue.guard(() async {
      final api = ref.read(ownerApiServiceProvider);
      return api.fetchDashboard(businessId: businessId);
    });
    _loadedForBusinessId = next.hasValue ? businessId : null;
    state = next;
  }
}

final ownerDashboardProvider =
    AsyncNotifierProvider<OwnerDashboardNotifier, OwnerDashboardData>(
  OwnerDashboardNotifier.new,
);

// ============================================================================
// OW-002 — Workforce Management
// ============================================================================

class WorkforceState {
  final List<AgentSummary> agents;
  final bool loading;
  final String? statusFilter;
  final String searchQuery;
  final String? error;

  const WorkforceState({
    this.agents = const [],
    this.loading = false,
    this.statusFilter,
    this.searchQuery = '',
    this.error,
  });

  List<AgentSummary> get filtered {
    var list = agents;
    if (statusFilter != null) {
      list = list.where((a) => a.status == statusFilter).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((a) => a.fullName.toLowerCase().contains(q) || a.mlid.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  int get totalActive => agents.where((a) => a.status == 'Active').length;
  int get pendingInvitations => agents.where((a) => a.status == 'Pending Invitation').length;
  int get pendingAcceptance => agents.where((a) => a.status == 'Pending Acceptance').length;
  int get disabled => agents.where((a) => a.status == 'Temporarily Disabled').length;
  int get suspended => agents.where((a) => a.status == 'Suspended').length;
  int get removed => agents.where((a) => a.status == 'Removed').length;

  WorkforceState copyWith({
    List<AgentSummary>? agents,
    bool? loading,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? searchQuery,
    String? error,
    bool clearError = false,
  }) {
    return WorkforceState(
      agents: agents ?? this.agents,
      loading: loading ?? this.loading,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class WorkforceNotifier extends Notifier<WorkforceState> {
  @override
  WorkforceState build() => const WorkforceState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(ownerApiServiceProvider);
      final agents = await api.fetchAgents(businessId: businessId);
      state = state.copyWith(agents: agents, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setStatusFilter(String? status) {
    state = status == null
        ? state.copyWith(clearStatusFilter: true)
        : state.copyWith(statusFilter: status);
  }

  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);

  Future<bool> registerNewAgent({
    required String businessId,
    required String fullName,
    required String fatherHusbandName,
    required String genderDigit,
    required String mobileNumber,
    required String aadhaarNumber,
  }) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.registerNewAgent(
        businessId: businessId,
        fullName: fullName,
        fatherHusbandName: fatherHusbandName,
        genderDigit: genderDigit,
        mobileNumber: mobileNumber,
        aadhaarNumber: aadhaarNumber,
      );
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<AgentSummary?> searchByMlid(String mlid) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      return await api.searchByMlid(mlid: mlid);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> addExistingAgent({required String businessId, required String personId}) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.addExistingAgent(businessId: businessId, personId: personId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateAgentStatus({
    required String businessId,
    required String agentId,
    required String status,
  }) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.updateAgentStatus(agentId: agentId, status: status);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final workforceProvider = NotifierProvider<WorkforceNotifier, WorkforceState>(
  WorkforceNotifier.new,
);

/// Per-agent profile fetch — separate small AsyncNotifier family so the
/// list screen doesn't refetch every profile eagerly; only the one the
/// Owner drills into.
class AgentProfileNotifier extends FamilyAsyncNotifier<AgentProfile, String> {
  @override
  Future<AgentProfile> build(String agentId) async {
    final api = ref.read(ownerApiServiceProvider);
    return api.fetchAgentProfile(agentId: agentId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final api = ref.read(ownerApiServiceProvider);
      return api.fetchAgentProfile(agentId: arg);
    });
  }

  Future<bool> updatePermissions(Map<String, bool> permissions) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.updateAgentPermissions(agentId: arg, permissions: permissions);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setCompensation({
    required double fixedSalary,
    required String salaryCycle,
    double? dailyAllowance,
    double? profitSharePercent,
    String? profitShareEffectiveDate,
  }) async {
    try {
      final api = ref.read(ownerApiServiceProvider);
      await api.setCompensation(
        agentId: arg,
        fixedSalary: fixedSalary,
        salaryCycle: salaryCycle,
        dailyAllowance: dailyAllowance,
        profitSharePercent: profitSharePercent,
        profitShareEffectiveDate: profitShareEffectiveDate,
      );
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final agentProfileProvider =
    AsyncNotifierProvider.family<AgentProfileNotifier, AgentProfile, String>(
  AgentProfileNotifier.new,
);

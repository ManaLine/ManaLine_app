import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_api_service.dart' show AuthApiService;

/// OW-014 Global Workflow — Pre-Existing Member Creation. Real Supabase
/// wiring over Modules 0/1. Registration/OTP send/verify reuse
/// AuthApiService directly (login_registration/state/auth_api_service.dart)
/// rather than re-implementing a second, parallel "blocked on Edge
/// Function" story for the exact same underlying auth-register/auth-otp-*
/// operations OW-014 also needs — same architectural decision record
/// applies here unchanged, just triggered from a different screen.
enum MemberType { customer, agent, investor }

extension MemberTypeLabel on MemberType {
  String get label => switch (this) {
        MemberType.customer => 'Customer',
        MemberType.agent => 'Agent',
        MemberType.investor => 'Investor',
      };

  String get role => label; // business_members.role uses the same string
}

class GlobalWorkflowApiService {
  SupabaseClient get _db => Supabase.instance.client;
  final AuthApiService _authApi = AuthApiService();

  Future<PersonSearchResult?> searchPerson({
    required String businessId,
    String? mobileNumber,
    String? mlid,
  }) async {
    var q = _db.from('persons').select('person_id, full_name, mlid, mobile_number');
    if (mlid != null && mlid.isNotEmpty) {
      q = q.eq('mlid', mlid);
    } else if (mobileNumber != null && mobileNumber.isNotEmpty) {
      q = q.eq('mobile_number', mobileNumber);
    } else {
      return null;
    }
    final row = await q.maybeSingle();
    if (row == null) return null;
    return PersonSearchResult(
      personId: row['person_id'].toString(),
      fullName: row['full_name'] as String? ?? '',
      mlid: row['mlid'] as String? ?? '',
      mobileNumber: row['mobile_number'] as String?,
    );
  }

  Future<String> requestBusinessMembership({
    required String businessId,
    required String personId,
    required MemberType type,
    required String invitedByPersonId,
  }) async {
    final row = await _db
        .from('business_members')
        .insert({
          'person_id': int.parse(personId),
          'business_id': businessId,
          'role': type.role,
          'membership_status': 'Pending Invitation',
          'verification_status': type == MemberType.customer ? 'Not Required' : 'Pending Verification',
          'onboarding_method': 'Migration/Pre-Existing',
          'invited_by_person_id': int.parse(invitedByPersonId),
        })
        .select('membership_id')
        .single();
    return row['membership_id'] as String;
  }

  Future<void> setMembershipStatus({required String membershipId, required String status}) async {
    await _db.from('business_members').update({'membership_status': status}).eq('membership_id', membershipId);
  }

  /// Reuses AuthApiService.register() — this IS the same operation LR-004
  /// performs (persons row creation via the `auth-register` Edge
  /// Function), just Owner-initiated instead of self-registration.
  /// BLOCKED on the same Edge Function gap flagged throughout
  /// auth_api_service.dart — not re-flagged again here, same root cause.
  Future<String> registerPreExistingPerson({
    required String fullName,
    required String fatherHusbandName,
    required String village,
    String? mobileNumber,
    String? areaLocality,
    String? remarks,
  }) async {
    final result = await _authApi.register(
      fullName: fullName,
      fatherHusbandName: fatherHusbandName,
      genderDigit: '0', // FLAGGED: this stub's own params never collected gender — same gap as the original stub, not introduced here
      mobileNumber: mobileNumber,
      address: {'village': village, 'area_locality': areaLocality},
      registrationSource: 'Migration',
      customerType: 'Migrated',
    );
    return result.personId;
  }

  Future<String> attachNewPersonToBusiness({
    required String businessId,
    required String personId,
    required MemberType type,
  }) async {
    final verificationStatus = type == MemberType.customer ? 'Not Required' : 'Pending Verification';
    final row = await _db
        .from('business_members')
        .insert({
          'person_id': int.parse(personId),
          'business_id': businessId,
          'role': type.role,
          'membership_status': 'Active',
          'verification_status': verificationStatus,
          'onboarding_method': 'Migration/Pre-Existing',
        })
        .select('membership_id')
        .single();
    return row['membership_id'] as String;
  }

  /// Cross-references business_members against persons.profile_status —
  /// no dedicated filter endpoint, matches the original stub's own note.
  Future<List<IncompleteProfileRow>> fetchIncompleteProfiles({required String businessId}) async {
    final rows = await _db
        .from('business_members')
        .select('membership_id, role, persons!business_members_person_id_fkey(person_id, full_name, profile_status)')
        .eq('business_id', businessId)
        .eq('persons.profile_status', 'Incomplete');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final person = m['persons'] as Map<String, dynamic>;
      return IncompleteProfileRow(
        personId: person['person_id'].toString(),
        membershipId: m['membership_id'] as String,
        fullName: person['full_name'] as String? ?? '',
        type: MemberType.values.firstWhere((t) => t.role == m['role'], orElse: () => MemberType.customer),
        profileStatus: person['profile_status'] as String? ?? 'Incomplete',
      );
    }).toList();
  }

  Future<void> updatePersonFields({required String personId, required Map<String, dynamic> fields}) async {
    await _db.from('persons').update(fields).eq('person_id', int.parse(personId));
  }

  Future<void> submitAddress({required String personId, required Map<String, dynamic> address}) async {
    await _db.from('person_addresses').insert({
      'person_id': int.parse(personId),
      'door_no': address['door_no'] ?? '-',
      'pin_code': address['pin_code'] ?? '000000',
      'village_id': address['village_id'],
      'mandal': address['mandal'] ?? '-',
      'district': address['district'] ?? '-',
      'state': address['state'] ?? '-',
      'from_date': DateTime.now().toIso8601String().split('T').first,
      'is_current': true,
    });
  }

  Future<void> submitDocument({required String personId, required String documentUrl}) async {
    await _db.from('identity_documents').insert({
      'person_id': int.parse(personId),
      'document_type': 'Aadhaar', // FLAGGED: stub's own signature has no document_type param — defaulted, not guessed silently
      'file_url': documentUrl,
    });
  }

  Future<void> sendOtp({required String mobileNumber}) async {
    // FLAGGED: AuthApiService.sendOtp needs personId+purpose, not a bare
    // mobile number — this stub's own signature never carried personId,
    // so it can't be forwarded correctly without a lookup first. Left
    // genuinely unimplemented rather than guessing which purpose/person.
    throw UnimplementedError(
      'sendOtp needs personId (not just mobileNumber) to call AuthApiService.sendOtp — original stub signature '
      'never carried it. Resolve the personId lookup at the call site before wiring this through.',
    );
  }

  Future<bool> verifyOtp({required String mobileNumber, required String otp}) async {
    throw UnimplementedError(
      'verifyOtp needs an otp_id (from a prior sendOtp call), not a bare mobileNumber+code pair — same gap as '
      'sendOtp above.',
    );
  }

  /// FLAGGED: agreement_acceptances requires otp_id (NOT NULL FK to
  /// otp_verifications) per the real schema — this stub's own signature
  /// only ever carried agreementId, with no OTP step modeled at all.
  /// Left genuinely unimplemented rather than inventing a bypass of a
  /// NOT NULL constraint.
  Future<void> acceptAgreement({required String agreementId}) async {
    throw UnimplementedError(
      'acceptAgreement needs an otp_id — agreement_acceptances.otp_id is NOT NULL in the real schema, but this '
      'stub\'s signature never collected one. The screen needs an OTP step before this call, not just the '
      'agreement_id.',
    );
  }

  Future<void> approveProfileComplete({required String personId, required String membershipId}) async {
    await _db.from('persons').update({'profile_status': 'Complete'}).eq('person_id', int.parse(personId));
    await _db.from('business_members').update({'verification_status': 'Verified'}).eq('membership_id', membershipId);
  }

  Future<void> submitProfileCompleteDirect({required String personId, required String membershipId}) async {
    await approveProfileComplete(personId: personId, membershipId: membershipId);
  }
}

class PersonSearchResult {
  final String personId;
  final String fullName;
  final String mlid;
  final String? mobileNumber;

  PersonSearchResult({
    required this.personId,
    required this.fullName,
    required this.mlid,
    this.mobileNumber,
  });
}

class IncompleteProfileRow {
  final String personId;
  final String membershipId;
  final String fullName;
  final MemberType type;
  final String profileStatus;

  IncompleteProfileRow({
    required this.personId,
    required this.membershipId,
    required this.fullName,
    required this.type,
    required this.profileStatus,
  });
}

// --- Riverpod state ------------------------------------------------------

final globalWorkflowApiServiceProvider = Provider<GlobalWorkflowApiService>((ref) {
  return GlobalWorkflowApiService();
});

/// Wizard states S1-S7 per OW-014 spec's STATES section.
enum WizardStage { selectType, searchMlid, found, notFound, incomplete, completionInProgress, complete }

class GlobalWorkflowState {
  final MemberType? memberType;
  final bool typeLockedByEntryPoint; // Step 1 skipped/pre-filled per entry point
  final WizardStage stage;
  final bool searching;
  final PersonSearchResult? searchResult;
  final bool searchedNotFound;
  final String? createdPersonId;
  final String? createdMembershipId;
  final bool loading;
  final String? error;

  const GlobalWorkflowState({
    this.memberType,
    this.typeLockedByEntryPoint = false,
    this.stage = WizardStage.selectType,
    this.searching = false,
    this.searchResult,
    this.searchedNotFound = false,
    this.createdPersonId,
    this.createdMembershipId,
    this.loading = false,
    this.error,
  });

  GlobalWorkflowState copyWith({
    MemberType? memberType,
    bool? typeLockedByEntryPoint,
    WizardStage? stage,
    bool? searching,
    PersonSearchResult? searchResult,
    bool clearSearchResult = false,
    bool? searchedNotFound,
    String? createdPersonId,
    String? createdMembershipId,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return GlobalWorkflowState(
      memberType: memberType ?? this.memberType,
      typeLockedByEntryPoint: typeLockedByEntryPoint ?? this.typeLockedByEntryPoint,
      stage: stage ?? this.stage,
      searching: searching ?? this.searching,
      searchResult: clearSearchResult ? null : (searchResult ?? this.searchResult),
      searchedNotFound: searchedNotFound ?? this.searchedNotFound,
      createdPersonId: createdPersonId ?? this.createdPersonId,
      createdMembershipId: createdMembershipId ?? this.createdMembershipId,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GlobalWorkflowNotifier extends Notifier<GlobalWorkflowState> {
  @override
  GlobalWorkflowState build() => const GlobalWorkflowState();

  void initWithType(MemberType? preSelected) {
    if (preSelected != null) {
      state = state.copyWith(
        memberType: preSelected,
        typeLockedByEntryPoint: true,
        stage: WizardStage.searchMlid,
      );
    }
  }

  void selectType(MemberType type) {
    state = state.copyWith(memberType: type, stage: WizardStage.searchMlid);
  }

  Future<void> search({
    required String businessId,
    String? mobileNumber,
    String? mlid,
  }) async {
    state = state.copyWith(searching: true, clearError: true, clearSearchResult: true, searchedNotFound: false);
    try {
      final result = await ref
          .read(globalWorkflowApiServiceProvider)
          .searchPerson(businessId: businessId, mobileNumber: mobileNumber, mlid: mlid);
      if (result != null) {
        state = state.copyWith(searching: false, searchResult: result, stage: WizardStage.found);
      } else {
        state = state.copyWith(searching: false, searchedNotFound: true, stage: WizardStage.notFound);
      }
    } catch (e) {
      state = state.copyWith(searching: false, error: e.toString());
    }
  }

  Future<bool> requestMembership({required String businessId, required String invitedByPersonId}) async {
    if (state.searchResult == null || state.memberType == null) return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      await ref.read(globalWorkflowApiServiceProvider).requestBusinessMembership(
            businessId: businessId,
            personId: state.searchResult!.personId,
            type: state.memberType!,
            invitedByPersonId: invitedByPersonId,
          );
      state = state.copyWith(loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> createPreExistingMember({
    required String businessId,
    required String fullName,
    required String fatherHusbandName,
    required String village,
    String? mobileNumber,
    String? areaLocality,
    String? remarks,
  }) async {
    if (state.memberType == null) return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(globalWorkflowApiServiceProvider);
      final personId = await api.registerPreExistingPerson(
        fullName: fullName,
        fatherHusbandName: fatherHusbandName,
        village: village,
        mobileNumber: mobileNumber,
        areaLocality: areaLocality,
        remarks: remarks,
      );
      final membershipId = await api.attachNewPersonToBusiness(
        businessId: businessId,
        personId: personId,
        type: state.memberType!,
      );
      state = state.copyWith(
        loading: false,
        createdPersonId: personId,
        createdMembershipId: membershipId,
        stage: WizardStage.incomplete,
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  void reset() => state = const GlobalWorkflowState();
}

final globalWorkflowProvider = NotifierProvider<GlobalWorkflowNotifier, GlobalWorkflowState>(
  GlobalWorkflowNotifier.new,
);

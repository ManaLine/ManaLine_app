import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_api_service.dart' show AuthApiService;
import '../../../shared/mana_time.dart';

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

  // --- Profile Completion sub-flow (OW-014 "Complete Profile" tile) ---------
  //
  // Every write below goes through a migration-0053 RPC rather than a raw
  // table write. Not a style choice: 0012's RLS makes persons UPDATE,
  // person_addresses INSERT and identity_documents INSERT self-only, so the
  // raw-table versions these replaced could never have succeeded for an
  // Owner acting on a member's rows — they'd have failed with a bare 42501
  // (or, on the person_addresses path, silently written nothing). See the
  // 0053 header for the full policy-by-policy account.

  Future<MemberProfileChecklist> fetchProfileChecklist({required String personId}) async {
    final rows = await _db.schema('app').rpc('owner_member_profile_checklist', params: {
      'p_person_id': int.parse(personId),
    });
    final row = (rows as List).first as Map<String, dynamic>;
    return MemberProfileChecklist(
      fullName: row['full_name'] as String? ?? '',
      mlid: row['mlid'] as String? ?? '',
      profileStatus: row['profile_status'] as String? ?? 'Incomplete',
      hasPhoto: row['has_photo'] as bool? ?? false,
      hasAddress: row['has_address'] as bool? ?? false,
      hasDocument: row['has_document'] as bool? ?? false,
      hasMobile: row['has_mobile'] as bool? ?? false,
      hasCredential: row['has_credential'] as bool? ?? false,
      termsAccepted: row['terms_accepted'] as bool? ?? false,
      addressSummary: row['address_summary'] as String?,
    );
  }

  Future<void> updateMemberIdentity({
    required String personId,
    String? mobileNumber,
    String? dob,
    String? aadhaarNumber,
    String? profilePhotoUrl,
  }) async {
    await _db.schema('app').rpc('owner_update_member_identity', params: {
      'p_person_id': int.parse(personId),
      'p_mobile_number': mobileNumber,
      'p_dob': dob,
      'p_aadhaar_number': aadhaarNumber,
      'p_profile_photo_url': profilePhotoUrl,
    });
  }

  /// Reuses `app.owner_update_customer_address` (migration 0027) unchanged —
  /// it is keyed on person_id, not customer_id, and already derives
  /// mandal/district/state from the village, so it covers an Agent's or
  /// Investor's address here just as well as a Customer's. Not duplicated
  /// into a second OW-014-specific RPC.
  Future<void> submitAddress({
    required String personId,
    required String doorNo,
    required String pinCode,
    required String villageId,
  }) async {
    await _db.schema('app').rpc('owner_update_customer_address', params: {
      'p_person_id': int.parse(personId),
      'p_door_no': doorNo,
      'p_pin_code': pinCode,
      'p_village_id': villageId,
    });
  }

  Future<void> submitDocument({
    required String personId,
    required String documentType,
    required String fileUrl,
  }) async {
    await _db.schema('app').rpc('owner_upload_member_document', params: {
      'p_person_id': int.parse(personId),
      'p_document_type': documentType,
      'p_file_url': fileUrl,
    });
  }

  // REMOVED: sendOtp, verifyOtp, acceptAgreement.
  //
  // All three were declared here, threw UnimplementedError, and were called by
  // nothing. Their signatures were also wrong for the real endpoints —
  // sendOtp took a bare mobile number where AuthApiService.sendOtp needs
  // personId + purpose, and verifyOtp took mobile+code where the real one
  // needs the otp_id returned by a prior send.
  //
  // They are deleted rather than implemented because AuthApiService already
  // does this correctly and six LR screens use it. Building these out would
  // have produced a SECOND OTP path competing with a working one, which is the
  // "two implementations drift" problem — and an auth path is the worst place
  // to have it. Anything here that needs an OTP should call
  // authApiServiceProvider directly.
  //
  // acceptAgreement went too. Terms acceptance is recorded on
  // persons.terms_accepted_at (see acceptTerms below), which is what OW-014's
  // completion check actually reads. agreement_acceptances stays unused: its
  // otp_id is NOT NULL, so writing it would force an SMS round trip every time
  // someone accepts terms, and nothing today needs a per-agreement audit row.

  /// Records that this person accepted the current Terms.
  ///
  /// THIS WAS NEVER WRITTEN BY ANYTHING. persons.terms_accepted_at is READ in
  /// two places — app.owner_member_profile's completion summary and the
  /// member-side check inside OW-014 — and both gate on it being non-null. No
  /// code anywhere set it, so that condition was permanently false and profile
  /// completion could never report the member side as done.
  ///
  /// Written directly rather than through an RPC because persons_self_update
  /// already permits exactly this: `person_id = app.current_person_id()`, on
  /// both USING and WITH CHECK. A person setting their own acceptance is the
  /// one case that policy is for.
  Future<void> acceptTerms({required String personId, int version = 1}) async {
    await _db.from('persons').update({
      // manaTimestamp, not DateTime.now: every timestamp column in this schema
      // is naive IST, and a UTC string here would record acceptance five and a
      // half hours out.
      'terms_accepted_at': manaTimestamp(),
      'terms_version': version,
      'privacy_accepted_at': manaTimestamp(),
      'privacy_version': version,
    }).eq('person_id', int.parse(personId));
  }

  /// Returns the status the server actually applied — 'Complete' only when
  /// the member-side steps (mobile, credential, terms) are done too,
  /// otherwise 'Pending Verification'. The prerequisite checks live in the
  /// RPC, so a failure here surfaces as a real exception with the missing
  /// artifact named, not as a no-op.
  Future<String> markProfileComplete({required String personId, required String membershipId}) async {
    final result = await _db.schema('app').rpc('owner_mark_member_profile_complete', params: {
      'p_person_id': int.parse(personId),
      'p_membership_id': membershipId,
    });
    return result as String;
  }
}

class MemberProfileChecklist {
  final String fullName;
  final String mlid;
  final String profileStatus;
  final bool hasPhoto;
  final bool hasAddress;
  final bool hasDocument;
  // Member-side steps — an Owner cannot perform these (see 0053 header).
  // Surfaced read-only so the screen can show what is still outstanding
  // instead of implying the Owner forgot something.
  final bool hasMobile;
  final bool hasCredential;
  final bool termsAccepted;
  final String? addressSummary;

  const MemberProfileChecklist({
    required this.fullName,
    required this.mlid,
    required this.profileStatus,
    required this.hasPhoto,
    required this.hasAddress,
    required this.hasDocument,
    required this.hasMobile,
    required this.hasCredential,
    required this.termsAccepted,
    this.addressSummary,
  });

  bool get ownerStepsDone => hasPhoto && hasAddress && hasDocument;
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

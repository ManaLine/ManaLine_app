import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../shared/widgets/language_selector.dart';

/// In-memory state carried across the LR-001..LR-013 flow.
///
/// TYPE FIX (this session): `selectedBusinessId` and `Membership.businessId`
/// were previously `int`, but every `business_id` in the real delivered
/// schema (supabase/migrations/0002_module1_tenancy.sql, confirmed against
/// live DDL this session) is `UUID` — i.e. a `String` in Dart. Both are now
/// `String`/`String?`. `personId` was already `String` here (schema has
/// persons.person_id as BIGINT, so in principle a numeric string — kept as
/// String throughout for simplicity, matching how the stub already modeled
/// it; only business_id/membership_id needed the type change).
///
/// RIPPLE WARNING (flagged in END RESULT, not silently fixed): ~40 files
/// outside login_registration/ under owner_workspace/, agent_workspace/,
/// investor_workspace/, and customer_workspace/ also read
/// `.selectedBusinessId` or `Membership.businessId`. This chat's file
/// ownership boundary explicitly forbids editing those four directories,
/// so this type change WILL fail to compile against those call sites until
/// a chat that owns those directories propagates the same int->String fix
/// there. See END RESULT for the full list and the exact boundary conflict.
class AuthFlowState {
  final String? personId;
  final String? mlid;
  final String? mlidType;
  final bool? pinExists;
  final String? token;
  final ManaLanguage language;
  final List<Membership> memberships;
  final String? selectedBusinessId; // set on LR-012 selection (or its auto-collapse)
  final String? selectedRole; // set on LR-013 selection (or its auto-collapse)

  /// Transient — set when register()/passwordResetRequest()/pinResetRequest()
  /// (or the account-unlock path) triggers a server-side OTP send. LR-005
  /// reads this (via ref.watch) instead of taking it as a constructor param,
  /// so router.dart's existing `GoRoute(path: '/lr-005', builder: (c, s) =>
  /// OtpVerificationScreen(purpose: ...))` doesn't need to change — this
  /// chat is not allowed to touch router.dart. Cleared once verifyOtp()
  /// succeeds or the flow otherwise completes.
  final String? pendingOtpId;

  const AuthFlowState({
    this.personId,
    this.mlid,
    this.mlidType,
    this.pinExists,
    this.token,
    this.language = ManaLanguage.english,
    this.memberships = const [],
    this.selectedBusinessId,
    this.selectedRole,
    this.pendingOtpId,
  });

  AuthFlowState copyWith({
    String? personId,
    String? mlid,
    String? mlidType,
    bool? pinExists,
    String? token,
    ManaLanguage? language,
    List<Membership>? memberships,
    String? selectedBusinessId,
    String? selectedRole,
    String? pendingOtpId,
    bool clearPendingOtpId = false,
  }) {
    return AuthFlowState(
      personId: personId ?? this.personId,
      mlid: mlid ?? this.mlid,
      mlidType: mlidType ?? this.mlidType,
      pinExists: pinExists ?? this.pinExists,
      token: token ?? this.token,
      language: language ?? this.language,
      memberships: memberships ?? this.memberships,
      selectedBusinessId: selectedBusinessId ?? this.selectedBusinessId,
      selectedRole: selectedRole ?? this.selectedRole,
      pendingOtpId: clearPendingOtpId ? null : (pendingOtpId ?? this.pendingOtpId),
    );
  }
}

class Membership {
  final String membershipId;
  final String businessId;
  final String businessName;
  final String role;
  final String membershipStatus;
  /// businesses.business_status — distinct from membershipStatus (LR-012:
  /// a Suspended business can still show for a person with an Active
  /// membership row, visually flagged, not hidden).
  final String businessStatus;
  /// business_members.verification_status — gates role visibility on
  /// LR-013 (BR-188/190/191): 'Verified' or 'Not Required' are eligible,
  /// 'Pending Verification' is hidden entirely from that screen.
  final String verificationStatus;

  const Membership({
    required this.membershipId,
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.membershipStatus,
    this.businessStatus = 'Active',
    this.verificationStatus = 'Not Required',
  });
}

class AuthFlowNotifier extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  void setLanguage(ManaLanguage lang) => state = state.copyWith(language: lang);

  void setRegistrationResult({
    required String personId,
    required String mlid,
    required String mlidType,
  }) {
    state = state.copyWith(personId: personId, mlid: mlid, mlidType: mlidType);
  }

  /// Set once a register()/passwordResetRequest()/pinResetRequest() call
  /// returns an otp_id from the server — LR-005 reads this to know which
  /// OTP it's verifying.
  void setPendingOtpId(String otpId) {
    state = state.copyWith(pendingOtpId: otpId);
  }

  void clearPendingOtpId() {
    state = state.copyWith(clearPendingOtpId: true);
  }

  /// Sets the auth result AND pushes the session into ManaSession so
  /// every subsequent Postgrest/RLS-scoped call (e.g. fetchMemberships())
  /// carries the right bearer token immediately — these two must not drift
  /// out of sync, so this is the one place both are touched together.
  Future<void> setLoginResult({
    required String personId,
    required String token,
    required bool pinExists,
    List<Membership> memberships = const [],
  }) async {
    state = state.copyWith(
      personId: personId,
      token: token,
      pinExists: pinExists,
      memberships: memberships,
    );
    await ManaSession.instance.setSession(accessToken: token, personId: personId);
  }

  void setMemberships(List<Membership> memberships) {
    state = state.copyWith(memberships: memberships);
  }

  /// LR-012 selection (or its single-business auto-collapse).
  void selectBusiness(String businessId) {
    state = state.copyWith(selectedBusinessId: businessId);
  }

  /// LR-013 selection (or its single-role auto-collapse).
  void selectRole(String role) {
    state = state.copyWith(selectedRole: role);
  }

  Future<void> reset() async {
    state = const AuthFlowState();
    await ManaSession.instance.clear();
  }
}

final authFlowProvider = NotifierProvider<AuthFlowNotifier, AuthFlowState>(
  AuthFlowNotifier.new,
);

/// ---------------------------------------------------------------------
/// ManaSession — holds the custom auth JWT (see main.dart's
/// Supabase.initialize(accessToken: ...) callback) and persists it via
/// flutter_secure_storage so LR-001 (System Startup) can hydrate a
/// returning session on cold start without a fresh login (Item E of this
/// session's briefing). Deliberately a separate small singleton rather than
/// folded into AuthFlowNotifier, because main.dart needs a synchronous
/// token getter BEFORE the ProviderScope/Riverpod container exists —
/// Supabase.initialize() runs before runApp(). Riverpod state can't be
/// read that early, but a plain static singleton can.
/// ---------------------------------------------------------------------
class ManaSession {
  ManaSession._();
  static final ManaSession instance = ManaSession._();

  static const _storage = FlutterSecureStorage();
  static const _kAccessToken = 'mana_session_access_token';
  static const _kPersonId = 'mana_session_person_id';

  String? _accessToken;
  String? _personId;

  /// Read synchronously by supabase_flutter's accessToken callback on
  /// every outgoing request. Returning null before a session exists is
  /// expected and correct — it's what makes register/login themselves
  /// (which must run as `anon`, not `authenticated`) work at all.
  String? get currentAccessToken => _accessToken;
  String? get currentPersonId => _personId;
  bool get hasSession => _accessToken != null;

  Future<void> setSession({required String accessToken, required String personId}) async {
    _accessToken = accessToken;
    _personId = personId;
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kPersonId, value: personId);
  }

  Future<void> clear() async {
    _accessToken = null;
    _personId = null;
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kPersonId);
  }

  /// Called once from main(), before runApp(). Populates the in-memory
  /// token from secure storage so the very first authenticated Postgrest
  /// call after a warm/cold restart already carries the right bearer
  /// token. This does NOT verify the token is still valid (not expired /
  /// not revoked server-side) — that's discovered the first time a
  /// protected query runs and RLS silently returns zero rows, or (once
  /// the real Edge Functions exist) a dedicated token-refresh/verify call.
  /// Flagged in END RESULT: no refresh-token/expiry story exists yet
  /// because the custom-JWT-minting Edge Function that would issue one is
  /// itself the blocking gap.
  Future<void> hydrateFromSecureStorage() async {
    _accessToken = await _storage.read(key: _kAccessToken);
    _personId = await _storage.read(key: _kPersonId);
  }
}

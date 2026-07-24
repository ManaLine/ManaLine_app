import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_flow_state.dart';

final authApiServiceProvider = Provider<AuthApiService>((ref) => AuthApiService());

/// =============================================================================
/// ARCHITECTURAL DECISION RECORD (read this before touching this file)
/// =============================================================================
///
/// 1. IDENTITY LAYER: `persons` (MLID/password_hash/pin_hash) is the sole
///    source of truth, per BR-178/181/182 — NOT Supabase Auth's own
///    `auth.users` table. There is no `persons.auth_user_id` column in the
///    delivered schema (supabase/migrations/0001_module0_identity.sql,
///    confirmed this session) to bridge the two, and the schema already
///    models password/PIN as hashed columns directly on `persons`. Using
///    Supabase Auth's own signUp/signInWithPassword would mean maintaining
///    TWO parallel identity records (an auth.users row AND a persons row)
///    that could drift — rejected for that reason.
///
/// 2. CONSEQUENCE — BLOCKING GAP, FLAGGED: because `persons` isn't a GoTrue
///    user, register/login/OTP-send/OTP-verify/password-reset/PIN-reset
///    cannot be plain Postgrest table writes (they need server-side
///    password/PIN hashing, the MLID-collision 409 logic from SP-001, and
///    — for login — minting a session token for a "user" GoTrue has never
///    heard of). This requires **Supabase Edge Functions** that this
///    session has NOT written and cannot write here — they're a separate
///    Deno/TypeScript codebase (`supabase/functions/**`), not a file this
///    chat owns, and they need `SUPABASE_JWT_SECRET`/service_role secrets
///    that must never live in this Flutter client. Every method below
///    calls a named Edge Function (`auth-register`, `auth-login`, etc.)
///    matching the exact Body/Response contract already documented in
///    04_API_Specification_v1_Part1.md §1 (unchanged from the original
///    stub's endpoint comments) — so this file is a real, working client
///    the moment those functions exist, but **they do not exist yet**.
///    This is the single blocking item for end-to-end testing. See END
///    RESULT.
///
/// 3. SESSION MECHANISM: the login Edge Function is expected to mint a
///    custom JWT — signed with the project's JWT secret, `role:
///    authenticated`, containing a `person_id` custom claim — NOT a real
///    GoTrue session. This app never calls `supabase.auth.signIn*`. The
///    returned token is handed to `ManaSession` (auth_flow_state.dart),
///    which main.dart's `Supabase.initialize(accessToken: ...)` callback
///    reads on every subsequent request. RLS policies in
///    0012_rls_module0_identity.sql already expect exactly this claim via
///    `app.current_person_id()`.
///
/// 4. PIN VALIDATION: happens INSIDE the `auth-login` Edge Function, by
///    comparing the submitted PIN against `persons.pin_hash` server-side.
///    This fixes a real bug found in the pre-existing LR-009 stub, which
///    compared the entered PIN against a value read back out of
///    `flutter_secure_storage` on-device (`_entered == storedPin`) — i.e.
///    validating a secret against a plaintext copy of itself stored
///    locally, which authenticates "is this the same device" at best, not
///    "did a human just prove they know the PIN" in any way a server can
///    rely on. The device-local PIN copy is now used ONLY to gate the
///    biometric-unlock convenience path (retrieve-then-submit-as-normal-
///    login, per LR-009's own locked architecture note) — never as the
///    login screen's own success/failure signal.
///
/// 5. OTP DELIVERY: which SMS gateway `auth-otp-send` calls internally
///    (MSG91, Twilio, etc.) is UNDECIDED and out of scope for this Dart
///    client — flagged as a second, independent blocking decision. The
///    client-side contract (send returns an `otp_id`; verify takes
///    `otp_id` + 6-digit `code`) is stable regardless of which gateway is
///    chosen, so nothing in this file needs to change once that's decided.
///
/// 6. SP-001 COMPLIANCE: `register()` distinguishes two different
///    "duplicate" signals returned by the Edge Function, per SP-001's
///    confidentiality requirement:
///      - a soft `duplicate_flag` (BR-228 `duplicate_suspects` fuzzy
///        match, e.g. same Aadhaar+Phone pattern) — registration still
///        SUCCEEDS, the flag is carried but never shown to the registering
///        person (matches the pre-existing LR-004 comment: "duplicate_flag
///        is never surfaced ... avoids identity-fraud fishing").
///      - a hard 409 CONFLICT (real `persons.aadhaar_number`/`mlid` UNIQUE
///        violation — someone else already holds this Aadhaar) — this
///        actually blocks registration. `register()` catches that
///        specific case and throws `RegistrationBlockedException` with
///        ONLY the generic SP-001-approved message ("This Aadhaar Number
///        is already associated with an existing account."), never the
///        raw Postgres error and never which account is blocking.
/// =============================================================================

/// Named Edge Functions this file calls. Centralized so a future rename
/// only needs to change one place.
class _Fn {
  static const register = 'auth-register';
  static const otpSend = 'auth-otp-send';
  static const otpVerify = 'auth-otp-verify';
  static const login = 'auth-login';
  static const pinCreate = 'auth-pin-create';
  static const passwordResetRequest = 'auth-password-reset-request';
  static const passwordResetConfirm = 'auth-password-reset-confirm';
  static const pinResetRequest = 'auth-pin-reset-request';
  static const pinResetConfirm = 'auth-pin-reset-confirm';
}

class AuthApiService {
  final SupabaseClient _client;
  AuthApiService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------
  // POST-equivalent Edge Function calls (§1.1/§1.3 of the API spec)
  // ---------------------------------------------------------------------

  /// auth-register (§1.1). Runs as `anon` — no session exists yet.
  Future<RegisterResult> register({
    required String fullName,
    required String fatherHusbandName,
    required String genderDigit,
    String? dob,
    String? mobileNumber,
    String? aadhaarNumber,
    required Map<String, String?> address,
    required String registrationSource,
    required String customerType,
  }) async {
    try {
      final res = await _client.functions.invoke(_Fn.register, body: {
        'full_name': fullName,
        'father_husband_name': fatherHusbandName,
        'gender_digit': genderDigit,
        'dob': dob,
        'mobile_number': mobileNumber,
        'aadhaar_number': aadhaarNumber,
        'address': address,
        'registration_source': registrationSource,
        'customer_type': customerType,
      });
      final data = _asMap(res.data);
      return RegisterResult(
        personId: data['person_id'].toString(),
        mlid: data['mlid'] as String,
        mlidType: data['mlid_type'] as String,
        profileStatus: data['profile_status'] as String,
        duplicateFlag: data['duplicate_flag'] as bool? ?? false,
        otpId: data['otp_id'] as String?,
      );
    } on FunctionException catch (e) {
      if (e.status == 409) {
        // SP-001: generic block message only, never expose which account.
        throw RegistrationBlockedException(
          'This Aadhaar Number is already associated with an existing account.',
        );
      }
      rethrow;
    }
  }

  /// auth-otp-send (§1.3). Returns the new otp_id.
  Future<String> sendOtp({required String personId, required String purpose}) async {
    final res = await _client.functions.invoke(_Fn.otpSend, body: {
      'person_id': personId,
      'purpose': purpose,
    });
    final data = _asMap(res.data);
    return data['otp_id'] as String;
  }

  /// auth-otp-verify (§1.3). Returns whether the code was correct — a
  /// wrong code is a normal (non-exceptional) business-logic outcome, not
  /// a thrown error, so screens can show "Incorrect code" inline the same
  /// way the pre-existing stub UI already expects.
  Future<bool> verifyOtp({required String otpId, required String code}) async {
    final res = await _client.functions.invoke(_Fn.otpVerify, body: {
      'otp_id': otpId,
      'code': code,
    });
    final data = _asMap(res.data);
    return data['verified'] as bool? ?? false;
  }

  /// auth-login (§1.3) — identifier: mobile_number, credential:
  /// password|pin. PIN validation happens server-side inside this
  /// function (see architectural note #4 above) — this client never
  /// compares credentials itself.
  Future<LoginResult> login({
    required String identifier,
    required String credential,
    required String deviceFingerprint,
  }) async {
    final res = await _client.functions.invoke(_Fn.login, body: {
      'identifier': identifier,
      'credential': credential,
      'device_fingerprint': deviceFingerprint,
    });
    final data = _asMap(res.data);
    return LoginResult(
      success: data['success'] as bool? ?? false,
      token: data['token'] as String?,
      personId: data['person_id']?.toString(),
      verificationRing: data['verification_ring'] as String?,
      pinExists: data['pin_exists'] as bool? ?? false,
    );
  }

  /// auth-pin-create (LR-008). Requires an already-authenticated session
  /// (this runs right after a successful password login, before PIN
  /// exists) — called with the bearer token already attached via
  /// ManaSession/accessToken callback.
  Future<void> createPin({
    required String personId,
    required String pin,
    required bool biometricEnabled,
  }) async {
    await _client.functions.invoke(_Fn.pinCreate, body: {
      'person_id': personId,
      'pin': pin,
      'biometric_enabled': biometricEnabled,
    });
  }

  /// auth-password-reset-request (§1.3). Per LR-010's locked behavior,
  /// the caller must show an identical message regardless of this call's
  /// outcome — never branch UI on success/failure of this specific call.
  /// Returns the otp_id so the caller can proceed to the OTP step.
  Future<String> passwordResetRequest({required String identifier}) async {
    final res = await _client.functions.invoke(_Fn.passwordResetRequest, body: {
      'identifier': identifier,
    });
    final data = _asMap(res.data);
    return data['otp_id'] as String;
  }

  Future<void> passwordResetConfirm({
    required String otpId,
    required String code,
    required String newPassword,
  }) async {
    await _client.functions.invoke(_Fn.passwordResetConfirm, body: {
      'otp_id': otpId,
      'code': code,
      'new_password': newPassword,
    });
  }

  /// auth-pin-reset-request (password-gated, LR-011). Returns the otp_id
  /// for the subsequent OTP step, purpose='PIN Reset'.
  Future<String> pinResetRequest({required String personId, required String password}) async {
    final res = await _client.functions.invoke(_Fn.pinResetRequest, body: {
      'person_id': personId,
      'password': password,
    });
    final data = _asMap(res.data);
    return data['otp_id'] as String;
  }

  Future<void> pinResetConfirm({
    required String otpId,
    required String code,
    required String newPin,
  }) async {
    await _client.functions.invoke(_Fn.pinResetConfirm, body: {
      'otp_id': otpId,
      'code': code,
      'new_pin': newPin,
    });
  }

  // ---------------------------------------------------------------------
  // Real Postgrest query (NOT an Edge Function) — this is the one part of
  // this file that works today against the real schema, no blocking gap.
  // Per this session's Item C: "populate AuthFlowState.memberships from a
  // real query ... subject to RLS same as everything else (a person can
  // only ever see their own membership rows via business_members_self_
  // select, which is exactly what you want here)." No person_id filter is
  // passed — RLS does that scoping, so this call can never accidentally
  // leak another person's memberships even if the caller had a bug.
  // ---------------------------------------------------------------------
  Future<List<Membership>> fetchMemberships() async {
    final rows = await _client
        .from('business_members')
        .select('business_id, role, membership_status, verification_status, '
            'businesses(business_name, business_status)');

    return (rows as List).map((row) {
      final r = row as Map<String, dynamic>;
      final business = r['businesses'] as Map<String, dynamic>?;
      return Membership(
        businessId: r['business_id'] as String,
        businessName: business?['business_name'] as String? ?? '',
        role: r['role'] as String,
        membershipStatus: r['membership_status'] as String,
        businessStatus: business?['business_status'] as String? ?? 'Active',
        verificationStatus: r['verification_status'] as String,
      );
    }).toList();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Unexpected Edge Function response shape');
  }
}

/// Thrown by register() on a genuine SP-001 collision. Screens must show
/// `message` verbatim and MUST NOT additionally show any raw error detail
/// alongside it — the whole point is that no other information leaks.
class RegistrationBlockedException implements Exception {
  final String message;
  const RegistrationBlockedException(this.message);
  @override
  String toString() => message;
}

class RegisterResult {
  final String personId;
  final String mlid;
  final String mlidType;
  final String profileStatus;
  final bool duplicateFlag;
  /// Set when registration also triggers the initial OTP send server-side
  /// (single combined action) — null if this deployment's auth-register
  /// function expects a separate explicit sendOtp() call instead. Either
  /// shape is compatible with this client; check which your Edge Function
  /// actually implements before wiring LR-004's call site.
  final String? otpId;
  RegisterResult({
    required this.personId,
    required this.mlid,
    required this.mlidType,
    required this.profileStatus,
    required this.duplicateFlag,
    this.otpId,
  });
}

class LoginResult {
  final bool success;
  final String? token;
  final String? personId;
  final String? verificationRing;
  final bool pinExists;
  LoginResult({
    required this.success,
    this.token,
    this.personId,
    this.verificationRing,
    required this.pinExists,
  });
}

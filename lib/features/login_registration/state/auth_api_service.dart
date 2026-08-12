import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/text_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/supabase_config.dart';
import 'auth_flow_state.dart';

final authApiServiceProvider =
    Provider<AuthApiService>((ref) => AuthApiService());

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
/// 2. All 9 named Edge Functions below are deployed and ACTIVE on the live
///    project (confirmed this batch) — the "blocking gap" language further
///    down is historical from an earlier session and no longer accurate;
///    left in place only because the architectural reasoning is still
///    correct, not because the functions are still missing.
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
///
/// 7. PIN LENGTH (ADDED this batch): `persons.pin_length` now records
///    whether the currently-set PIN is 4 or 6 digits, written by
///    auth-pin-create. auth-login returns `needs_pin_upgrade` — true only
///    when pin_length is 4 or NULL (legacy, predates this column) — so
///    the client can force a one-time upgrade to a 6-digit PIN without
///    re-prompting anyone who's already on 6.
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
  AuthApiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // BUG FIX (confirmed live): main.dart's `accessToken` callback attaches
  // whatever ManaSession.currentAccessToken currently holds to EVERY
  // outgoing request, including these Edge Function calls — and
  // hydrateFromSecureStorage() restores that token on cold start without
  // checking whether it has expired (its own doc comment already admits
  // this). Once it expires, every call carries it, including a fresh
  // login attempt — so a person could never recover: the dashboard threw
  // PostgrestException(JWT expired, PGRST303), and BOTH the PIN and
  // password login screens then failed with FunctionException 401 for
  // the exact same reason, since supabase_flutter's AuthHttpClient only
  // fills in Authorization via `putIfAbsent` (never overwrites one that's
  // already present) — the stale header from ManaSession always won.
  // Passing this explicit header on the calls below restores the
  // documented intent ("must run as anon, not authenticated" — see the
  // class doc's Architectural Decision #3) by giving `invoke()` an
  // Authorization value to put before AuthHttpClient ever gets a chance
  // to fill one in with the stale token.
  static const Map<String, String> _anonAuth = {
    'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
  };

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
    String? password,
    String? aadhaarNumber,
    // `Object?`, not `String?`: the address now also carries the GPS pin,
    // which is numeric. Typing it as String? forced the coordinates to be
    // stringified, and the Edge Function's numeric range checks would then
    // reject them.
    required Map<String, Object?> address,
    required String registrationSource,
    required String customerType,
  }) async {
    try {
      final res = await _client.functions.invoke(_Fn.register, headers: _anonAuth, body: {
        'full_name': fullName,
        'father_husband_name': fatherHusbandName,
        'gender_digit': genderDigit,
        'dob': dob,
        'mobile_number': mobileNumber,
        'password': password,
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
        // Covers both Aadhaar and mobile_number collisions (0039) — not
        // narrowed to "Aadhaar" specifically anymore, since that would be
        // actively misleading for a mobile-triggered block.
        throw const RegistrationBlockedException(
          'This Aadhaar Number or Mobile Number is already associated with an existing account.',
        );
      }
      rethrow;
    }
  }

  /// auth-otp-send (§1.3). Returns the new otp_id.
  Future<String> sendOtp(
      {required String personId,
      required String purpose,
      String? membershipId}) async {
    final res = await _client.functions.invoke(_Fn.otpSend, headers: _anonAuth, body: {
      'person_id': personId,
      'purpose': purpose,
      if (membershipId != null) 'membership_id': membershipId,
    });
    final data = _asMap(res.data);
    return data['otp_id'] as String;
  }

  /// auth-otp-verify (§1.3). Returns whether the code was correct — a
  /// wrong code is a normal (non-exceptional) business-logic outcome, not
  /// a thrown error, so screens can show "Incorrect code" inline the same
  /// way the pre-existing stub UI already expects.
  Future<bool> verifyOtp({required String otpId, required String code}) async {
    final res = await _client.functions.invoke(_Fn.otpVerify, headers: _anonAuth, body: {
      'otp_id': otpId,
      'code': code,
    });
    final data = _asMap(res.data);
    return data['verified'] as bool? ?? false;
  }

  /// auth-login (§1.3) — identifier: mobile_number, credential: password
  /// or PIN depending on credentialType.
  Future<LoginResult> login({
    required String identifier,
    required String credential,
    required String credentialType,
    required String deviceFingerprint,
    /// Set only after the person has been shown that their account is switched
    /// off (or scheduled for deletion) and has confirmed they want it back.
    ///
    /// Reactivation rides on the login call rather than its own endpoint
    /// because a disabled person cannot obtain a token, so they cannot call an
    /// authenticated RPC to undo it. The credential they just presented is the
    /// identity proof.
    bool reactivate = false,
  }) async {
    try {
      final res = await _client.functions.invoke(_Fn.login, headers: _anonAuth, body: {
        'identifier': identifier,
        'credential': credential,
        'credential_type': credentialType,
        'device_fingerprint': deviceFingerprint,
        if (reactivate) 'reactivate': true,
      });
      final data = _asMap(res.data);
      return LoginResult(
        success: data['success'] as bool? ?? false,
        token: data['token'] as String?,
        personId: data['person_id']?.toString(),
        verificationRing: data['verification_ring'] as String?,
        pinExists: data['pin_exists'] as bool? ?? false,
        needsPinUpgrade: data['needs_pin_upgrade'] as bool? ?? false,
      );
    } on FunctionException catch (e) {
      // BUG FIXED this pass: BR-201 lockout (auth-login returns 403
      // ACCOUNT_LOCKED once failed_pin_attempts/failed_password_attempts
      // hits its cap) was never distinguished from a plain wrong
      // password/PIN — LR-007/LR-009 always showed the same generic
      // "incorrect" message, even though the OTP-unlock screen
      // (OtpPurpose.accountUnlock in lr_005) already existed. Surfacing
      // it as a typed exception so those screens can route there instead
      // of silently absorbing it into "incorrect credentials".
      if (e.status == 403 && e.details is Map) {
        final errors = (e.details as Map)['errors'];
        final firstError = errors is List && errors.isNotEmpty ? errors.first as Map? : null;
        if (firstError?['code'] == 'ACCOUNT_LOCKED') {
          throw AccountLockedException(
            message: firstError?['message'] as String? ??
                'Account is locked after too many failed attempts. Verify via OTP to unlock.',
            personId: firstError?['person_id']?.toString(),
          );
        }
        // P4: the person switched their own account off, or asked for it to be
        // deleted. Distinct from a lockout — nothing is wrong with their
        // credentials, and the remedy is a confirmation rather than an OTP.
        // Typed so the login screens can offer to bring the account back
        // instead of showing "incorrect credentials", which would be a lie.
        final code = firstError?['code'];
        if (code == 'ACCOUNT_DISABLED' || code == 'ACCOUNT_PENDING_DELETION') {
          throw AccountDisabledException(
            message: firstError?['message'] as String? ??
                'This account is switched off.',
            personId: firstError?['person_id']?.toString(),
            pendingDeletion: code == 'ACCOUNT_PENDING_DELETION',
            purgeAfter: firstError?['purge_after']?.toString(),
          );
        }
      }
      rethrow;
    }
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
    final res = await _client.functions.invoke(_Fn.passwordResetRequest, headers: _anonAuth, body: {
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
    await _client.functions.invoke(_Fn.passwordResetConfirm, headers: _anonAuth, body: {
      'otp_id': otpId,
      'code': code,
      'new_password': newPassword,
    });
  }

  /// auth-pin-reset-request (password-gated, LR-011). Returns the otp_id
  /// for the subsequent OTP step, purpose='PIN Reset'.
  Future<String> pinResetRequest(
      {required String personId, required String password}) async {
    final res = await _client.functions.invoke(_Fn.pinResetRequest, headers: _anonAuth, body: {
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
    await _client.functions.invoke(_Fn.pinResetConfirm, headers: _anonAuth, body: {
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
  Future<List<Membership>> fetchMemberships(String personId) async {
    final rows = await _client
        .from('business_members')
        .select(
            'membership_id, business_id, role, membership_status, verification_status, '
            'businesses(business_name, business_status)')
        .eq('person_id', personId);

    return (rows as List).map((row) {
      final r = row as Map<String, dynamic>;
      final business = r['businesses'] as Map<String, dynamic>?;
      return Membership(
        membershipId: r['membership_id'] as String,
        businessId: r['business_id'] as String,
        businessName: titleCaseName(business?['business_name'] as String? ?? ''),
        role: r['role'] as String,
        membershipStatus: r['membership_status'] as String,
        businessStatus: business?['business_status'] as String? ?? 'Active',
        verificationStatus: r['verification_status'] as String,
      );
    }).toList();
  }

  /// Every Edge Function in this batch responds with a consistent
  /// {data: {...}, meta: {...}, errors: [...]} envelope — the actual
  /// payload lives under the `data` key, not at the top level. This was
  /// discovered as a real bug: this file was originally written expecting
  /// flat top-level fields (e.g. `data['success']`), which silently
  /// misparsed every response, success or failure alike, once the real
  /// functions were deployed. Unwrapping centrally here fixes every
  /// caller in this file at once.
  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Edge Function response shape');
    }
    final inner = raw['data'];
    if (inner is Map<String, dynamic>) return inner;
    // Fallback for any endpoint that isn't wrapped (defensive — none of
    // the 9 delivered functions should hit this branch, but fail toward
    // the raw map rather than throwing if one doesn't follow the pattern).
    return raw;
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

/// Thrown by login() on a BR-201 lockout (403 ACCOUNT_LOCKED). Callers
/// should send an 'Account Unlock' OTP for [personId] (via sendOtp) and
/// navigate to OtpVerificationScreen(purpose: OtpPurpose.accountUnlock)
/// rather than showing the generic "incorrect credentials" message.
class AccountLockedException implements Exception {
  final String message;
  final String? personId;
  const AccountLockedException({required this.message, this.personId});
  @override
  String toString() => message;
}

/// The person switched their own account off, or asked for it to be deleted.
///
/// Deliberately separate from [AccountLockedException]: a lockout is the app
/// defending itself against someone guessing, and the way out is an OTP. This
/// is the account holder's own earlier decision, and the way out is simply
/// confirming they changed their mind — so the two must not share a message.
class AccountDisabledException implements Exception {
  final String message;
  final String? personId;

  /// True when a 90-day deletion is already running, in which case signing
  /// back in cancels it.
  final bool pendingDeletion;

  /// yyyy-MM-dd the purge falls due, when one is scheduled.
  final String? purgeAfter;

  const AccountDisabledException({
    required this.message,
    this.personId,
    this.pendingDeletion = false,
    this.purgeAfter,
  });

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

  /// True only when the currently-set PIN is 4 digits, or predates the
  /// pin_length column entirely (NULL — treated as needing upgrade).
  /// Anyone already on a 6-digit PIN is never flagged.
  final bool needsPinUpgrade;
  LoginResult({
    required this.success,
    this.token,
    this.personId,
    this.verificationRing,
    required this.pinExists,
    this.needsPinUpgrade = false,
  });
}

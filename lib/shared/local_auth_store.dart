import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mana_time.dart';

/// Result of [decideDeviceFingerprint]: the value to return this call, and
/// whether [LocalAuthStore.deviceFingerprint] still needs to persist it.
class DeviceFingerprintDecision {
  final String value;
  final bool shouldPersist;
  const DeviceFingerprintDecision(this.value, {required this.shouldPersist});
}

/// Pure decision logic behind [LocalAuthStore.deviceFingerprint], pulled out
/// so it can be unit-tested against both `isWeb` branches without faking
/// `kIsWeb` (that constant is compile-time and cannot be overridden in a
/// test — this is the same extraction Task 7 used for
/// `webUploadRejectionReason`).
///
/// - A value already in durable storage (`persisted`) always wins, on any
///   platform — this is what makes native's "generated once, reused
///   forever" true, and also means a pre-existing web value from before
///   this change is honoured rather than silently replaced.
/// - Otherwise on web: reuse the in-memory `cached` value if this page
///   session already minted one; never persist.
/// - Otherwise on web with no cache yet: mint one, still never persist —
///   the caller is responsible for caching it in memory.
/// - Otherwise (native, nothing persisted yet): mint one and persist it.
DeviceFingerprintDecision decideDeviceFingerprint({
  required bool isWeb,
  required String? persisted,
  required String? cached,
  required String Function() generate,
}) {
  if (persisted != null) {
    return DeviceFingerprintDecision(persisted, shouldPersist: false);
  }
  if (isWeb) {
    return DeviceFingerprintDecision(cached ?? generate(), shouldPersist: false);
  }
  return DeviceFingerprintDecision(generate(), shouldPersist: true);
}

/// Device-local secure storage backing LR-009 Daily Login's stated
/// prerequisites (per that screen's own spec):
///   - `pin_length` remembered locally from LR-008, non-sensitive
///     metadata, no server round-trip needed to know PIN pad length.
///   - the PIN value itself, stored securely (Keychain/Keystore via
///     flutter_secure_storage) so a successful biometric unlock can
///     retrieve it and submit it as a normal PIN login — biometric
///     never becomes a distinct server credential type (locked
///     architecture, LR-009 API BINDING section).
///   - `biometric_enabled`, set at LR-008's opt-in step.
///   - `device_fingerprint`, generated once per device install and
///     reused on every login call (LR-007 and LR-009 both send it).
///     Native only — see [deviceFingerprint] for the web behaviour.
///   - `last_mobile_number`, so LR-009's step-down to LR-007 on 3x PIN
///     failure (BR-201) can pre-fill Mobile Number per that screen's S4.
///     Native only — see [saveMobileNumber].
class LocalAuthStore {
  static const _storage = FlutterSecureStorage();

  static const _kPinLength = 'mana_pin_length';
  static const _kPinValue = 'mana_pin_value';
  static const _kBiometricEnabled = 'mana_biometric_enabled';
  static const _kDeviceFingerprint = 'mana_device_fingerprint';
  static const _kLastMobileNumber = 'mana_last_mobile_number';

  /// businessId -> when this device last opened it, as ISO-8601.
  ///
  /// Ordering data, not credentials. It lives here rather than in a second
  /// store because adding a whole storage dependency for one map is how an
  /// app ends up with two answers to "what does this device remember".
  static const _kBusinessLastOpened = 'mana_business_last_opened';

  // Web only: holds the fingerprint for the lifetime of the browser tab.
  // A fingerprint minted per session is the accepted outcome (see
  // deviceFingerprint's doc), but minting one per *login call* would insert
  // a fresh `devices` row every time (auth-login/index.ts:255-274 upserts on
  // fingerprint) — unbounded row growth once the site is public. This cache
  // is what keeps one browser session to one row.
  static String? _webFingerprintCache;

  // --- Written by LR-008 at PIN creation ---------------------------------
  static Future<void> savePin({required String pin, required bool biometricEnabled}) async {
    // Web only: flutter_secure_storage is backed by localStorage there, not
    // Keychain/Keystore — readable by any XSS on the origin and outlasting
    // the browser closing, a no-expiry bearer credential strictly worse than
    // the session JWT. It is stored at all only so a fingerprint unlock can
    // replay it as a PIN login (see the class doc), and ManaBiometric.
    // isAvailable() already returns false on web, so nothing on web can ever
    // read this back. Skipping the write removes the exposure with no loss
    // of function.
    if (!kIsWeb) {
      await _storage.write(key: _kPinValue, value: pin);
    }
    await _storage.write(key: _kPinLength, value: pin.length.toString());
    await _storage.write(key: _kBiometricEnabled, value: biometricEnabled.toString());
  }

  // Web only: flutter_secure_storage is localStorage there — XSS-readable
  // and outliving the browser closing, same exposure as the PIN value
  // above. Nothing on web reads this back for anything functional (every
  // reader only pre-fills a text field, per the LR-007/LR-009/Settings
  // trace in fingerprint-investigation.md §7), so skipping the write on
  // web costs a re-typed mobile number, never a broken flow.
  static Future<void> saveMobileNumber(String mobile) async {
    if (kIsWeb) return;
    await _storage.write(key: _kLastMobileNumber, value: mobile);
  }

  /// Toggle biometric on/off independently of PIN creation — used by the
  /// Settings screen when a person enables it AFTER initially skipping it
  /// at LR-008. Does not touch the stored PIN value/length at all;
  /// requires a PIN to already exist (caller verifies this).
  static Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _kBiometricEnabled, value: enabled.toString());

  // --- Read by LR-009 ------------------------------------------------
  static Future<int?> readPinLength() async {
    final v = await _storage.read(key: _kPinLength);
    return v == null ? null : int.tryParse(v);
  }

  static Future<String?> readPinValue() => _storage.read(key: _kPinValue);

  static Future<bool> readBiometricEnabled() async {
    final v = await _storage.read(key: _kBiometricEnabled);
    return v == 'true';
  }

  static Future<String?> readLastMobileNumber() => _storage.read(key: _kLastMobileNumber);

  /// Notes that this device just opened [businessId].
  ///
  /// The workspace list ranks by what the person IS to each business -- owner
  /// who works the round, then owner, then agent, then investor, then
  /// customer -- and businesses of equal standing used to tie. Ties broke on
  /// name, which is stable but arbitrary: three businesses somebody invests in
  /// are not meaningfully alphabetical. The one they were last in is the one
  /// they are most likely to want next.
  ///
  /// Best-effort in both directions. A write that fails loses an ordering
  /// preference, and a read that fails falls back to the name order, so
  /// neither can keep somebody out of their own businesses.
  static Future<void> recordBusinessOpened(String businessId) async {
    if (businessId.isEmpty) return;
    try {
      final now = manaTimestamp();
      final map = await readBusinessOpenTimes();
      map[businessId] = now;
      await _storage.write(key: _kBusinessLastOpened, value: jsonEncode(map));
    } catch (_) {
      // Ordering is a convenience; never let it break signing in.
    }
  }

  /// businessId -> ISO-8601 of the last time this device opened it.
  static Future<Map<String, String>> readBusinessOpenTimes() async {
    try {
      final raw = await _storage.read(key: _kBusinessLastOpened);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } catch (_) {
      // Corrupt or unreadable -- the caller falls back to ordering by name.
      return <String, String>{};
    }
  }

  /// Native: generated once, persisted, reused on every /auth/login call
  /// from this device forever (LR-007 and LR-009 both need the same value).
  ///
  /// Web: still generated and still sent on every login call — auth-login
  /// requires the field (index.ts:67) — but never written to storage.
  /// Browser storage here is localStorage: XSS-readable, outlives the
  /// browser closing. The value still must not change on it, only where
  /// it lives, is because nothing enforces on the result: a new
  /// fingerprint only flips which `devices` row is `is_active`
  /// (auth-login/index.ts:243-274, written and read nowhere else — no RPC,
  /// no RLS policy, no app query gates on it), and it is not part of any
  /// rate-limit key (those are `login:<identifier>:<ip>` and
  /// `lockout:<person_id>`). So a fresh value once per browser session is
  /// harmless. What is NOT harmless is a fresh value per *login call*
  /// within one session — auth-login upserts a `devices` row per
  /// fingerprint, so that would grow the table without bound. `_webFingerprintCache`
  /// exists to prevent exactly that: one generation per page load, reused
  /// for every login call after.
  static Future<String> deviceFingerprint() async {
    final persisted = await _storage.read(key: _kDeviceFingerprint);
    final decision = decideDeviceFingerprint(
      isWeb: kIsWeb,
      persisted: persisted,
      cached: _webFingerprintCache,
      generate: _generateFingerprint,
    );
    if (kIsWeb) {
      _webFingerprintCache = decision.value;
    } else if (decision.shouldPersist) {
      await _storage.write(key: _kDeviceFingerprint, value: decision.value);
    }
    return decision.value;
  }

  static String _generateFingerprint() {
    final rand = Random.secure();
    return List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
  }

  /// BR-201 step-down (3x wrong PIN) resets the local PIN so LR-009
  /// won't auto-trigger biometric/PIN again until LR-008 is redone
  /// after a fresh password login — server-side failed_pin_attempts
  /// reset is separate (handled by the API response), this only clears
  /// the device-local unlock material.
  static Future<void> clearPin() async {
    await _storage.delete(key: _kPinValue);
    await _storage.delete(key: _kPinLength);
    await _storage.delete(key: _kBiometricEnabled);
  }

  /// Forgets WHO this device last belonged to.
  ///
  /// Separate from [clearPin] because the two are not the same act: a
  /// BR-201 step-down drops the unlock material but the phone still belongs
  /// to the same person, whereas "Change User" means someone else is about
  /// to sign in and the remembered number would otherwise pre-fill theirs.
  static Future<void> clearLastMobileNumber() =>
      _storage.delete(key: _kLastMobileNumber);

  /// Forgets which businesses this device has opened.
  ///
  /// Goes with "Change User": the next person's list must not be ordered by
  /// where the last person had been.
  static Future<void> clearBusinessOpenTimes() =>
      _storage.delete(key: _kBusinessLastOpened);
}

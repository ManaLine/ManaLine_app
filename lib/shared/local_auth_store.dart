import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
///   - `last_mobile_number`, so LR-009's step-down to LR-007 on 3x PIN
///     failure (BR-201) can pre-fill Mobile Number per that screen's S4.
class LocalAuthStore {
  static const _storage = FlutterSecureStorage();

  static const _kPinLength = 'mana_pin_length';
  static const _kPinValue = 'mana_pin_value';
  static const _kBiometricEnabled = 'mana_biometric_enabled';
  static const _kDeviceFingerprint = 'mana_device_fingerprint';
  static const _kLastMobileNumber = 'mana_last_mobile_number';

  // --- Written by LR-008 at PIN creation ---------------------------------
  static Future<void> savePin({required String pin, required bool biometricEnabled}) async {
    await _storage.write(key: _kPinValue, value: pin);
    await _storage.write(key: _kPinLength, value: pin.length.toString());
    await _storage.write(key: _kBiometricEnabled, value: biometricEnabled.toString());
  }

  static Future<void> saveMobileNumber(String mobile) =>
      _storage.write(key: _kLastMobileNumber, value: mobile);

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

  /// Generated once, persisted, reused on every /auth/login call from
  /// this device (LR-007 and LR-009 both need the same value).
  static Future<String> deviceFingerprint() async {
    final existing = await _storage.read(key: _kDeviceFingerprint);
    if (existing != null) return existing;
    final generated = _generateFingerprint();
    await _storage.write(key: _kDeviceFingerprint, value: generated);
    return generated;
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
}

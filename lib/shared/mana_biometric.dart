import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// P2 Biometric — the real hardware prompt.
///
/// WHAT WAS THERE BEFORE: a Settings toggle that stored a flag, and LR-009's
/// "biometric unlock" which fetched the locally-saved PIN and submitted it as
/// a normal login. No fingerprint was ever requested. Anyone holding the
/// unlocked handset could tap the biometric button and be signed in, because
/// the only thing being checked was that a PIN had once been saved on this
/// device.
///
/// Same never-throw shape as ManaLocation, for the same reason: the caller
/// needs to tell "no hardware", "not enrolled", "user cancelled" and "wrong
/// finger" apart, and an exception or a bare false collapses them.
enum ManaBiometricResult {
  /// Identity confirmed by the device.
  ok,

  /// The person dismissed the prompt. Not a failure — a choice.
  cancelled,

  /// Fingerprint or face was presented and rejected.
  rejected,

  /// No biometric hardware on this handset.
  unavailable,

  /// Hardware exists but nothing is enrolled, or the device has no screen
  /// lock set at all.
  notEnrolled,

  /// Too many failed attempts; the OS has locked biometrics temporarily or
  /// permanently.
  lockedOut,

  failed,
}

class ManaBiometric {
  static final _auth = LocalAuthentication();

  /// Whether offering biometric login makes any sense on this device.
  ///
  /// Checked before showing the toggle rather than after tapping it: an
  /// option that always fails is worse than one that is not offered.
  static Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts for a fingerprint or face.
  ///
  /// [reason] is shown by the OS inside its own dialog, so it must read as a
  /// sentence to the person holding the phone, not as a log line.
  static Future<ManaBiometricResult> authenticate({
    String reason = 'Confirm it is you to sign in',
  }) async {
    try {
      // local_auth 3.x takes these as flat named parameters; the
      // AuthenticationOptions object belonged to 2.x.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // Biometric only — no device PIN/pattern fallback. This app already
        // has its own PIN screen behind this button, and accepting the PHONE's
        // unlock code would let someone who knows that code into the lending
        // account. Different secret, different person's money.
        biometricOnly: true,
        // Keeps the prompt alive if the handset briefly backgrounds the app
        // when the sensor fires, which some cheap devices do.
        persistAcrossBackgrounding: true,
      );
      return ok ? ManaBiometricResult.ok : ManaBiometricResult.rejected;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'NotAvailable' => ManaBiometricResult.unavailable,
        'NotEnrolled' => ManaBiometricResult.notEnrolled,
        'LockedOut' || 'PermanentlyLockedOut' => ManaBiometricResult.lockedOut,
        // The plugin reports a user dismissal as an error rather than false.
        'UserCanceled' || 'auth_in_progress' => ManaBiometricResult.cancelled,
        _ => ManaBiometricResult.failed,
      };
    }
  }

  /// What to show when [authenticate] did not return ok.
  ///
  /// Never phrased as an app failure: on this hardware most of these are
  /// ordinary device states, and the person always has the PIN screen behind
  /// the button.
  static String messageFor(ManaBiometricResult r) => switch (r) {
        ManaBiometricResult.ok => '',
        ManaBiometricResult.cancelled => 'Cancelled. Enter your PIN instead.',
        ManaBiometricResult.rejected =>
          'That did not match. Try again, or enter your PIN.',
        ManaBiometricResult.unavailable =>
          'This phone has no fingerprint or face unlock. Use your PIN.',
        ManaBiometricResult.notEnrolled =>
          'No fingerprint is set up on this phone yet. Add one in phone '
              'settings, or use your PIN.',
        ManaBiometricResult.lockedOut =>
          'Fingerprint is locked after too many tries. Use your PIN.',
        ManaBiometricResult.failed =>
          'Fingerprint could not be read. Use your PIN.',
      };
}

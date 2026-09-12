import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two Karri Priyanka rows, 2m14s apart, with DIFFERENT mobile numbers.
///
/// That detail is the whole diagnosis. A slip of the fingers produces the same
/// number twice; deliberately different details mean the second attempt was
/// made by somebody who believed the first had not worked. The Owner said so
/// outright -- the app "didn't show the first one as created successfully or
/// not created".
///
/// The cause was fixed the day after those rows were written (d79b3dd:
/// registration never sent the OTP, and LR-005 explained it by blaming a page
/// refresh, on a handset that has no page to refresh). The happy path now ends
/// on LR-006 showing the new MANA LINE ID.
///
/// What these pin is the window that fix left open: when the SEND fails, the
/// account exists and nothing on screen says so.
void main() {
  final lr005 =
      File('lib/features/login_registration/screens/lr_005_otp_verification.dart')
          .readAsStringSync();
  final lr004 =
      File('lib/features/login_registration/screens/lr_004_registration_form.dart')
          .readAsStringSync();

  group('the happy path still confirms', () {
    test('a verified registration lands on the screen that shows the ID', () {
      // LR-006 is the confirmation. If registration ever stops routing there,
      // nothing tells somebody their account is real.
      expect(lr005, contains("case OtpPurpose.registration:"));
      final reg = lr005.substring(lr005.indexOf('case OtpPurpose.registration:'));
      expect(reg.substring(0, reg.indexOf('break;')), contains("'/lr-006'"),
          reason: 'registration must end on the screen that shows the MLID');
    });

    test('the OTP is actually sent, which is the bug that started this', () {
      // auth-register deliberately does not send it and always answers
      // otp_id: null, so this caller must. The guard that read
      // `if (otpId != null)` found null every time and skipped in silence.
      expect(lr004, contains('sendOtp('),
          reason: 'nobody can register if the code is never sent');
    });
  });

  group('when the code could not be sent', () {
    test('the person is told the account exists, on arrival', () {
      expect(lr005, contains('account_created_code_not_sent_note'),
          reason: 'the screen looks like an ordinary OTP screen waiting for a '
              'code that will never arrive; saying nothing is what produced '
              'the duplicate');
    });

    test('the notice names the MLID', () {
      // Proof the account is real, and the thing they would otherwise have to
      // register again to discover.
      final banner = lr005.substring(lr005.indexOf('account_created_code_not_sent_note'));
      expect(banner.substring(0, banner.indexOf('),')), contains('{mlid}'),
          reason: 'an assurance with no ID in it is still asking them to take '
              'it on trust');
    });

    test('it is shown before typing, not after six wasted digits', () {
      // The old explanation lived inside _verify, so it only appeared once
      // somebody had entered a code they never received.
      final build = lr005.substring(lr005.indexOf('Widget build(BuildContext'));
      expect(build, contains('_accountExistsButCodeDidNot'),
          reason: 'the answer belongs in the build, not behind a button press');
    });

    test('only registration claims an account exists', () {
      // Password reset, PIN reset and account unlock arriving without an OTP
      // are lost sessions, not new accounts, and must keep their own sentence.
      final guard =
          lr005.substring(lr005.indexOf('bool get _accountExistsButCodeDidNot'));
      final body = guard.substring(0, guard.indexOf('\n  }'));
      expect(body, contains('OtpPurpose.registration'),
          reason: 'telling somebody resetting a password that their account '
              'was just created would be a lie');
      expect(body, contains('personId != null'),
          reason: 'personId is what distinguishes "account made, send failed" '
              'from a genuinely lost session');
    });
  });

  group('registering twice is not the way out', () {
    test('a failed send does not send them back to the form', () {
      // Going back means pressing Submit again, which registers the same
      // person a second time -- which is the entire defect being fixed.
      expect(lr004, contains("context.push('/lr-005')"));
      final after = lr004.substring(lr004.indexOf('final otpId = result!.otpId'));
      expect(after, contains("context.push('/lr-005')"),
          reason: 'the push must happen even when the send failed, because the '
              'account already exists by then');
    });
  });
}

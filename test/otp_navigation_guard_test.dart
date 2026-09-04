import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nobody may arrive at the OTP screen without an OTP having been sent.
///
/// THE BUG THIS EXISTS FOR: `auth-register` deliberately does not send the
/// code. Its own header says why — identity creation is kept decoupled from the
/// SMS gateway so a gateway outage can never block account creation — and it
/// always answers `otp_id: null`, expecting the caller to make a separate
/// `auth-otp-send` call.
///
/// LR-004 never made it. It guarded on `if (result.otpId != null)`, which was
/// false every single time, skipped in silence, and pushed to LR-005 anyway.
/// LR-005 then found no pending OTP and said:
///
///     "Your verification session was lost — this happens if the page was
///      refreshed or reopened directly."
///
/// On a handset there is no page to refresh. NOBODY COULD REGISTER, and the
/// error named a cause that could not have occurred — so it read as a browser
/// quirk rather than as the registration path being unwired.
///
/// Nothing typed would have caught this: a nullable field that is always null
/// is perfectly valid Dart, and the guard around it looked careful.
///
/// THE RULE: a screen that navigates to /lr-005 must, in the same file, either
/// send an OTP or record one. Checked on source text, because the alternative
/// is a live SMS gateway.
const _otpRoute = "'/lr-005'";

/// The send itself, and ONLY the send.
///
/// `setPendingOtpId` was the obvious second thing to accept here, and it would
/// have made this whole file worthless: the broken LR-004 called it — inside
/// `if (result.otpId != null)`, a branch that never ran — so a guard accepting
/// it passed on the exact code it exists to reject. Checked against the pre-fix
/// file rather than assumed: zero occurrences of `sendOtp`, one of
/// `setPendingOtpId`.
///
/// Recording an id proves nothing about where the id came from. Minting one is
/// the thing that has to happen.
const _otpEvidence = ['sendOtp'];

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Files that actually navigate there, as opposed to merely naming the route.
  /// router.dart declares it and auth_flow_state.dart mentions it in a comment;
  /// neither is a caller.
  List<File> navigators() => [
        for (final f in files)
          if (RegExp(r'(push|go|pushReplacement)\(\s*' + RegExp.escape(_otpRoute))
              .hasMatch(f.readAsStringSync()))
            f,
      ];

  test('the guard is looking at something', () {
    // Zero navigators means the matcher has drifted and the assertion below
    // passes without checking anything — the exact shape of the original bug.
    expect(navigators(), isNotEmpty,
        reason: 'Nothing navigates to /lr-005 any more. Either the route moved '
            'or the navigation style changed and this matcher needs updating.');
  });

  test('every route to the OTP screen sends an OTP first', () {
    final offenders = <String>[];
    for (final f in navigators()) {
      final source = f.readAsStringSync();
      if (_otpEvidence.any(source.contains)) continue;
      offenders.add(f.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These push /lr-005 without sending an OTP or recording one, so '
          'the screen opens with nothing to verify and blames the person:\n  '
          '${offenders.join('\n  ')}\n\n'
          'Call authApiService.sendOtp(...) and pass the id to '
          'setPendingOtpId, the way LR-004 does after registering.',
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// K Bhaskara Reddy accepted an Investor invitation to SDF, entered the OTP,
/// and watched a blank screen with a turning spinner until he gave up.
///
/// Nothing had failed. LR-005 ends Role Escalation with `context.pop()`, which
/// returns to LR-013 -- whose postFrameCallback had already run, on arrival,
/// before the OTP existed. So build() re-read the SAME cached membership
/// snapshot, still saw 'Pending Verification', still computed zero eligible
/// roles, and returned its bare `Scaffold(body: Center(CircularProgressIndicator()))`
/// with nothing left alive to move it. The hang was not a request that never
/// answered; it was a screen that had already finished thinking.
///
/// That spinner has no app bar, no message and no back affordance, so every
/// early return in this screen landed somewhere with no way out. There were
/// three.
void main() {
  final source =
      File('lib/features/login_registration/screens/lr_013_role_selector.dart')
          .readAsStringSync();

  group('coming back from the OTP', () {
    test('the push to LR-005 is awaited', () {
      // The whole defect in one character. An unawaited push means the pop
      // comes back to a screen that will never reconsider anything.
      expect(RegExp(r'await\s+context\.push\(\s*\n?\s*./lr-005.').hasMatch(source),
          isTrue,
          reason: 'LR-005 pops back here, so the push must be awaited or '
              'nothing runs after the OTP is entered');
    });

    test('memberships are re-read after it, not only on arrival', () {
      // The snapshot is stale BY DEFINITION at that point: the row Role
      // Escalation just verified is the row this screen filtered out.
      final escalation =
          source.substring(source.indexOf('Future<void> _startRoleEscalation('));
      final afterPush = escalation.substring(escalation.indexOf("'/lr-005'"));
      expect(afterPush, contains('_refreshMemberships'),
          reason: 'the verified membership is still Pending Verification in '
              'the cached list, so re-running the routing rule on it would '
              'compute the same empty role set');
      expect(afterPush, contains('_applyRoutingRule'),
          reason: 'refreshing without re-deciding leaves the same spinner up');
    });

    test('escalation cannot loop', () {
      // Re-applying the rule calls back into escalation when the role set is
      // still empty. Without a latch that sends a second OTP and pushes the
      // same screen again, forever.
      expect(source, contains('_escalated'),
          reason: 'a re-entrant escalation is an OTP loop');
    });
  });

  group('no path ends on the bare spinner', () {
    test('every early return in the escalation leaves for somewhere usable',
        () {
      // Counted, not eyeballed: three bare `return;`s used to strand the
      // person here -- no person/business id, nothing pending to escalate,
      // and the OTP send failing. Each now goes to the business list.
      final escalation =
          source.substring(source.indexOf('Future<void> _startRoleEscalation('));
      final body = escalation.substring(0, escalation.indexOf('\n  Future<void> _selectRole'));

      final bareReturns = RegExp(r'^\s*return;\s*$', multiLine: true)
          .allMatches(body)
          .length;
      final exits = RegExp(r'_leaveToBusinessList\(\)').allMatches(body).length;

      expect(exits, greaterThanOrEqualTo(3),
          reason: 'found only $exits guarded exits; the three early returns '
              'that stranded people were the missing-ids case, the '
              'nothing-pending case and the OTP-send failure');
      // Bare returns are fine ONLY when an exit was issued on the line before.
      expect(bareReturns, lessThanOrEqualTo(exits + 1),
          reason: 'a bare return with no navigation in front of it lands on '
              'build()\'s spinner, which has no app bar and no way out');
    });

    test('the spinner this strands people on is still the one described', () {
      // If this screen ever grows a real loading state with a way out, this
      // guard is checking the wrong thing and should be revisited rather
      // than silently passing.
      expect(source, contains('Scaffold(body: Center(child: CircularProgressIndicator()))'),
          reason: 'the bare spinner was replaced or reworded -- re-read this '
              'guard against what the screen does now');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_location.dart';

/// The rule these tests exist to protect: "couldn't verify" and "doesn't
/// match" are different claims. Showing the second when you mean the first
/// accuses a customer of being somewhere they are not, on the strength of a
/// weak GPS fix.
void main() {
  // The 'address check wording' group lived here and is gone with the
  // feature it described. The collect sheet no longer compares the
  // Agent's position against the customer's saved address -- it records
  // where the money was taken instead, which is a statement rather than
  // a verdict. app.compare_address_gps is left in the database; nothing
  // in the app calls it.
  group('fix outcomes', () {
    test('every failure mode has its own words', () {
      // A denied permission and a dead satellite are different things to a
      // person standing at a door, and one generic "location error" would tell
      // them nothing about what to do.
      final messages = <String>{
        for (final s in ManaFixStatus.values)
          ManaFix(status: s, accuracyM: 10).message,
      };
      expect(messages.length, ManaFixStatus.values.length);
    });

    test('none of them sounds like the loan failed', () {
      // GPS never blocks a loan, so no message may imply something was
      // refused or lost.
      for (final s in ManaFixStatus.values) {
        final m = ManaFix(status: s, accuracyM: 10).message.toLowerCase();
        expect(m, isNot(contains('failed')));
        expect(m, isNot(contains('cannot continue')));
      }
    });

    test('a rough fix is flagged before it is ever sent for comparison', () {
      const rough = ManaFix(
          status: ManaFixStatus.ok,
          latitude: 17.0,
          longitude: 78.0,
          accuracyM: 250);
      expect(rough.isTooRoughToJudge, isTrue);
      expect(rough.message, contains('could not be checked'));

      const good = ManaFix(
          status: ManaFixStatus.ok,
          latitude: 17.0,
          longitude: 78.0,
          accuracyM: 18);
      expect(good.isTooRoughToJudge, isFalse);
    });

    test('the client threshold matches the server rule', () {
      // compare_address_gps returns is_indeterminate when accuracy > 100.
      // If these drift, the app promises a check the server will refuse.
      expect(ManaFix.indeterminateAboveM, 100.0);
    });

    test('only an ok fix carries a position', () {
      for (final s in ManaFixStatus.values) {
        final f = ManaFix(status: s, latitude: 1, longitude: 2);
        expect(f.hasPosition, s == ManaFixStatus.ok);
      }
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/global_workflow_state.dart';

import 'support/schema_snapshot.dart';

/// Adding somebody to a business is ONE path now: search, choose a role, add.
///
/// It was three, and all three already did search-and-add -- they differed
/// only in which half they refused. Meanwhile the screen you actually reach a
/// stranger from, Universal Search, could not add at all: a result holding no
/// role here printed "Not a member of this business." and stopped, because the
/// Add button was drawn only when the search found NOBODY. So the app offered
/// to create a brand new person and offered nothing for the person already on
/// screen -- which is how a phone-number search for a real customer became a
/// dead end.
void main() {
  group('a dead end cannot come back', () {
    test('saying someone is not a member always comes with a way to add them',
        () {
      // The rule, not the widget tree: any screen that tells the Owner a
      // person is not in this business must also offer to put them in it.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        if (!source.contains('not_a_member_of_business')) continue;
        if (!source.contains('add_to_this_business')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these say a person is not a member and offer no way to '
              'add them, which is the dead end this guard exists for: '
              '$offenders');
    });

    test('the message is still drawn somewhere, so this guard checks something',
        () {
      // A guard that finds nothing to check reads exactly like one that
      // passes. If the message is renamed, this fails rather than going quiet.
      final found = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .any((f) => f.readAsStringSync().contains('not_a_member_of_business'));
      expect(found, isTrue,
          reason: 'nothing renders not_a_member_of_business any more -- either '
              'the key was renamed, in which case rename it here too, or the '
              'branch is gone and this guard should go with it');
    });
  });

  group('one way in', () {
    final ow004 =
        File('lib/features/owner_workspace/screens/ow_004_customer_management.dart')
            .readAsStringSync();

    test('Customer Management offers exactly one way to add a customer', () {
      // Three rows collapsed to one: "Existing Customers" (the same sheet
      // locked against creating anybody) and "Pre-Existing Customer" (OW-014)
      // are gone. A second row reappearing here means the three doors into one
      // room are growing back.
      final actions = RegExp(r'MemberAction\(').allMatches(ow004).length;
      expect(actions, 1,
          reason: 'found $actions add-actions on Customer Management; the '
              'Owner asked for one path in a running business');
    });

    test('nothing asks the add sheet to refuse to create', () {
      // existingOnly still EXISTS on the sheet and now has no caller passing
      // true. Left in place deliberately rather than deleted in the same
      // change: its branch carries a real rule -- a person who already holds a
      // MANA LINE ID must never be re-registered as a new one -- and whether
      // that protection is still wanted is the Owner's call, not a tidy-up.
      // This pins the current state so the answer is a decision rather than a
      // drift.
      expect(RegExp(r'existingOnly:\s*true').hasMatch(ow004), isFalse,
          reason: 'a caller has started using existingOnly again; if that is '
              'deliberate, this guard and the comment above it need updating '
              'together');
    });
  });

  group('the role the Owner picks', () {
    test('all three member types can be added, and only those three', () {
      // app.attach_person_to_business raises 22023 for anything that is not
      // Agent, Investor or Customer. The picker is built from this enum, so a
      // fourth value added here without the RPC learning about it would be a
      // role the sheet offers and the server refuses.
      expect(MemberType.values.map((t) => t.role).toSet(),
          {'Customer', 'Agent', 'Investor'});
    });

    test('the RPC the add path calls actually exists', () {
      // A plpgsql body is not type-checked at CREATE time and an invented
      // function name applies perfectly, so the snapshot is what says this
      // name is real.
      expect(manaAppFunctions, contains('attach_person_to_business'));
      // The overloads map records only the functions that HAVE more than one,
      // so absence from it is the single-overload assertion. A second overload
      // is PGRST203 and the screen would just say it could not add them.
      expect(manaAppFunctionOverloads, isNot(contains('attach_person_to_business')));
    });
  });
}

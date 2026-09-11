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
      // true. The rule it used to carry -- an already-registered person must
      // not be re-registered as a new one -- is enforced by _wouldDuplicate
      // now, on the one path that remains, rather than by a second entry point
      // somebody had to know to choose.
      expect(RegExp(r'existingOnly:\s*true').hasMatch(ow004), isFalse,
          reason: 'a caller has started using existingOnly again; if that is '
              'deliberate, this guard and the comment above it need updating '
              'together');
    });

    test('Create New cannot be reached without the duplicate check', () {
      // The hole this closes, measured: persons.mobile_number is UNIQUE but
      // NULLABLE, Postgres allows unlimited NULLs in a unique column, and
      // _canCreateNew permits an empty mobile -- so two people with the same
      // name, father's name, gender and village and no phone between them were
      // two rows with an MLID each, and nothing objected. A search that finds
      // nobody falls straight through to Create New, so this is on the live
      // path, not a corner.
      final createNew = ow004.substring(ow004.indexOf('Future<void> _createNew('));
      final body = createNew.substring(0, createNew.indexOf('createNewReturningId'));
      expect(body, contains('_wouldDuplicate'),
          reason: 'createNewReturningId is reachable without the duplicate '
              'check in front of it');
    });

    test('the check runs exactly where the unique constraint does not', () {
      // With a mobile number the database is already the authority: a second
      // registration on the same number is 23505 and already reaches the Owner
      // as "that mobile number is already registered". The check bows out
      // there, which is also what keeps a genuine namesake registerable --
      // typing the phone number that distinguishes them is the way through.
      final guard = ow004.substring(ow004.indexOf('Future<bool> _wouldDuplicate('));
      expect(guard.substring(0, guard.indexOf('}')),
          contains('_mobile.text.trim().isNotEmpty'),
          reason: 'the duplicate check must stand down when a mobile number '
              'makes the database the authority');
    });
  });

  group('telling two people apart', () {
    test('every screen that lists search matches shows the village', () {
      // A name search legitimately returns several people, and the village is
      // the only line an Owner can tell two men of the same name apart by --
      // owner_search_person has returned it all along. The Add Customer sheet
      // showed it; Universal Search did not, so the one screen you reach a
      // stranger from was the one that could not distinguish them.
      final screens = {
        'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart':
            'Universal Search',
        'lib/features/owner_workspace/screens/ow_004_customer_management.dart':
            'the Add Customer sheet',
      };
      screens.forEach((path, what) {
        final source = File(path).readAsStringSync();
        expect(source, contains('person.village.isNotEmpty'),
            reason: '$what lists identity matches without the village, which '
                'is what distinguishes two people of the same name');
      });
    });
  });

  group('who gets asked, and who just gets added', () {
    // The Owner's rule: an Agent and an Investor both get reach into somebody
    // else's book, so both are ASKED. A Customer is being recorded rather
    // than granted anything.
    //
    // The rule lives in two languages -- plpgsql decides the status, Dart
    // decides the sentence the Owner reads -- which is precisely the shape
    // that produced this project's worst regressions. These pin them to each
    // other.
    final migration = File(
            'supabase/migrations/20260911211146_agents_and_investors_are_asked_customers_are_added.sql')
        .readAsStringSync();

    test('Dart and the migration agree about who needs to accept', () {
      expect(MemberType.customer.needsAcceptance, isFalse);
      expect(MemberType.agent.needsAcceptance, isTrue);
      expect(MemberType.investor.needsAcceptance, isTrue);

      // The server's half of the same sentence, verified by invocation on
      // 2026-09-11: Agent and Investor returned 'Pending Invitation',
      // Customer returned 'Active'.
      // The server's half of the same sentence, verified by invocation on
      // 2026-09-11: Agent and Investor returned 'Pending Invitation',
      // Customer returned 'Active'. Matched as fragments rather than one
      // pattern so reformatting the SQL does not read as a rule change.
      final statusRule = migration.substring(
          migration.indexOf('v_status := CASE'),
          migration.indexOf('membership_status_enum;',
              migration.indexOf('v_status := CASE')));
      expect(statusRule, contains("WHEN v_role = 'Customer'"));
      expect(statusRule, contains("THEN 'Active'"));
      expect(statusRule, contains("ELSE 'Pending Invitation'"),
          reason: 'the migration no longer says what '
              'MemberType.needsAcceptance says; change both or neither');
    });

    test('accepting an Agent still creates their permissions row', () {
      // The precondition that made this change safe. respond_to_invitation
      // creates the agents row; before this migration it did NOT create
      // agent_permissions, which attach_person_to_business always had. Every
      // column but agent_id defaults true, so a MISSING row is not "no
      // permissions yet" -- it is every permission reading false, a workspace
      // that loads and refuses every action. One live agent was already in
      // that state; routing all new Agents through acceptance would have
      // given it to all of them.
      final respond =
          migration.substring(migration.indexOf('FUNCTION app.respond_to_invitation'));
      expect(respond, contains('INSERT INTO agent_permissions'),
          reason: 'an accepted Agent gets a workspace that refuses everything '
              'without this');
    });

    test('the Owner is told when somebody accepts', () {
      final respond =
          migration.substring(migration.indexOf('FUNCTION app.respond_to_invitation'));
      expect(respond, contains('INSERT INTO notifications'));
      expect(respond, contains("o.role = 'Owner'"),
          reason: 'the notification must reach the Owner who sent the request');
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

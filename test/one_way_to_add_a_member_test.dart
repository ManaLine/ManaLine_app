import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Adding somebody to a business goes through Universal Search. All of it.
///
/// There were SEVEN ways in, and every one of them searched-and-added:
///
///   OW-002 Workforce         -> /ow-014?type=agent
///   OW-003 Investors         -> its own MLID/name sheet, AND /ow-014?type=investor
///   OW-004 Customers         -> a sheet, the same sheet locked, and /ow-014?type=customer
///   OW-012 Members           -> two dialogs asking for an MLID typed from memory
///   OW-000 first setup       -> /ow-014?type=agent
///   OW-001 quick actions     -> a deep link that popped OW-003's sheet
///   the header +             -> /ow-014?type=agent or ?type=investor
///
/// They differed only in which half they would refuse, and the person adding
/// somebody had to know which door led where before they could start. The
/// MLID dialogs were the worst of them: a box that could not search, could
/// not confirm the ID belonged to the person meant, and offered nothing to
/// somebody who did not have one.
void main() {
  final owner = Directory('lib/features/owner_workspace/screens')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('the old doors are shut', () {
    test('nothing routes to OW-014 by member type any more', () {
      final offenders = <String>[];
      for (final f in [
        ...owner,
        File('lib/shared/widgets/workspace_actions.dart'),
      ]) {
        final source = f.readAsStringSync();
        // The ROUTE, not the prose: these files discuss OW-014 in comments.
        if (RegExp(r"""push\(\s*'/ow-014\?type=""").hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these still open OW-014 by member type instead of '
              'Universal Search: $offenders');
    });

    test('no screen still offers to add an "existing" member', () {
      // The word carried the whole false distinction. Adding somebody already
      // registered and adding somebody who is not are one errand now.
      final dead = [
        'add_existing_agent',
        'add_existing_customer',
        'add_existing_investor',
        'pre_existing_investor',
        'pre_existing_customer',
      ];
      final offenders = <String>[];
      for (final f in owner) {
        final source = f.readAsStringSync();
        for (final key in dead) {
          if (source.contains("t('$key')")) offenders.add('${f.path}: $key');
        }
      }
      expect(offenders, isEmpty, reason: 'still offered: $offenders');
    });

    test('nobody is added by an MLID typed from memory', () {
      final members =
          File('lib/features/owner_workspace/screens/ow_012_business_management.dart')
              .readAsStringSync();
      expect(members, isNot(contains('_addExisting(')),
          reason: 'the MLID dialogs are back; they cannot search and cannot '
              'confirm the ID belongs to the person meant');
    });
  });

  group('and they all lead to the same place', () {
    test('every add entry point pushes Universal Search', () {
      final expected = {
        'lib/features/owner_workspace/screens/ow_002_workforce_management.dart':
            'Workforce',
        'lib/features/owner_workspace/screens/ow_003_investor_management.dart':
            'Investor Management',
        'lib/features/owner_workspace/screens/ow_012_business_management.dart':
            'Business Management members',
        'lib/features/owner_workspace/screens/ow_000_first_business_setup.dart':
            'first business setup',
        'lib/shared/widgets/workspace_actions.dart': 'the header +',
      };
      expected.forEach((path, what) {
        expect(File(path).readAsStringSync(), contains('/ow-search'),
            reason: '$what no longer reaches Universal Search');
      });
    });

    test('a customer can still be added and lent to in one go', () {
      // The ONE deliberate exception, and the reason it survives:
      // /customer-new ends with a choice Universal Search does not have --
      // add them, or add them and go straight to a loan. Somebody standing in
      // front of a new borrower should not have to find them again in a list
      // of fifty-six to lend to them.
      final actions =
          File('lib/shared/widgets/workspace_actions.dart').readAsStringSync();
      expect(actions, contains("ManaMemberKind.customer => '/customer-new'"),
          reason: 'the add-then-lend shortcut is gone');
    });
  });

  group('one action needs no menu', () {
    test('a roster with a single add action does not open a sheet', () {
      // All three rosters offer exactly one way in now, and a bottom sheet
      // holding a single row is a tap that asks a question with one answer.
      final roster =
          File('lib/design/components/mana_member_roster.dart').readAsStringSync();
      final open = roster.substring(roster.indexOf('Future<void> _openAddSheet('));
      final head = open.substring(0, open.indexOf('showModalBottomSheet'));
      expect(head, contains('addActions.length == 1'),
          reason: 'a one-row menu is a wasted tap on every roster');
    });
  });
}

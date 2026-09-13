import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The + and the magnifier had become the same button.
///
/// Tranche B pointed both at Universal Search, which made adding a member one
/// path -- right -- and also made the two header controls indistinguishable.
/// On OW-005 that produced FIVE controls of which THREE did one job: register
/// a customer, +, and search. None of them labelled.
///
/// Worse, the + on Workforce and Investor Management landed on the
/// role-choosing search, whose add-new button opened the one sheet it knew --
/// the add-CUSTOMER sheet. So on the two screens whose entire subject is
/// agents and investors, searching for somebody who did not exist offered to
/// file them as a borrower. One tap from the wrong kind of person in the book.
///
/// They are told apart now: + adds a member of THIS SCREEN's kind, the
/// magnifier finds anyone and asks.
void main() {
  final actions =
      File('lib/shared/widgets/workspace_actions.dart').readAsStringSync();
  final search =
      File('lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart')
          .readAsStringSync();
  final router = File('lib/app/router.dart').readAsStringSync();

  group('the + carries the screen it was pressed on', () {
    test('agent and investor screens add their own kind', () {
      expect(actions, contains("'/ow-search?role=agent'"));
      expect(actions, contains("'/ow-search?role=investor'"));
    });

    test('a customer screen still goes to the add-then-lend sheet', () {
      // The one deliberate exception, unchanged: /customer-new ends with a
      // choice Universal Search does not have -- add them, or add them and go
      // straight to a loan.
      expect(actions, contains("ManaMemberKind.customer => '/customer-new'"));
    });

    test('the magnifier carries no role, so it asks', () {
      final searchAction = actions.substring(actions.indexOf('class _SearchAction'));
      expect(searchAction, contains("'/ow-search'"));
      expect(searchAction, isNot(contains('role=')),
          reason: 'the magnifier finds ANYONE; fixing its role would make it a '
              'second + and undo the whole distinction');
    });
  });

  group('the route carries it through', () {
    // Sliced to the NEXT GoRoute rather than to an exact indentation string.
    // The first version anchored on a literal containing leading spaces and
    // broke the moment the file was reformatted around it. A guard that fails
    // on whitespace teaches people to ignore guards.
    String routeBlock() {
      final from = router.indexOf("path: '/ow-search'");
      final next = router.indexOf('GoRoute(', from);
      return router.substring(from, next == -1 ? router.length : next);
    }

    test('all three roles are understood', () {
      final block = routeBlock();
      for (final role in ['customer', 'agent', 'investor']) {
        expect(block, contains("'$role' =>"), reason: '$role is not routed');
      }
    });

    test('an unrecognised role asks rather than guessing', () {
      // The safe direction: a wrong role files an agent as a borrower, a
      // needless question does not.
      expect(routeBlock(), contains('_ => null'),
          reason: 'an unknown role must fall back to asking, not to a default '
              'kind of person');
    });
  });

  group('add-new is no longer always a customer', () {
    test('the add-new button is routed by role', () {
      final addNew = search.substring(search.indexOf('Future<void> _addNewPerson('));
      final body = addNew.substring(0, addNew.indexOf('Future<void> _search('));
      expect(body, contains('ManaMemberKind.agent'));
      expect(body, contains('ManaMemberKind.investor'));
      expect(body, contains('ManaAddCustomerSheet'),
          reason: 'customers keep the sheet that can also issue a loan');
    });

    test('its label follows the role too', () {
      // A button reading "Add Customer" on Workforce Management is the report
      // that started this, even if the tap now does the right thing.
      expect(search, contains("ManaMemberKind.agent => 'add_an_agent'"));
      expect(search, contains("ManaMemberKind.investor => 'add_investor'"));
    });

    test('a fixed role is not asked about twice', () {
      final add = search.substring(search.indexOf('Future<void> _addToBusiness('));
      expect(add.substring(0, add.indexOf('showModalBottomSheet')),
          contains('widget.fixedRole'),
          reason: 'the picker must be skipped when the screen already answered');
    });
  });

  group('three buttons, one job', () {
    test('the new-loan header no longer carries its own register glyph', () {
      final loan =
          File('lib/features/owner_workspace/screens/ow_005_new_loan_workflow.dart')
              .readAsStringSync();
      expect(loan, isNot(contains("ref.t('register_customer')")),
          reason: 'the + already adds a customer on this screen and the '
              'magnifier already finds one');
      expect(loan, contains("ref.t('group_loans')"),
          reason: 'group loans is the one header control here that goes '
              'somewhere else entirely, and must survive');
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_one_person_entry.dart';
import 'package:mana_line/features/owner_workspace/state/village_book_summary.dart';

import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Two device findings, and what they are each worth guarding.
///
/// ITEM 5: the member roster's three-dot menu offered Reactivate to somebody
/// already active, and put Remove one tap from the errand an Owner is
/// actually doing on that screen. The dots are gone: tap is the errand, a
/// three-second hold is the rest.
///
/// ITEM 7: the one-person entry screen was the VILLAGE book with a name in
/// the title bar -- "1 Customers" over a row you had to expand. It is its own
/// screen now.
ManaLoanPosition _position({
  String name = 'Ramesh Kumar Reddy Garu',
  String careOf = 'Venkata Subbaiah',
  String village = 'Someswaram',
  String loanId = 'loan-1',
  int balance = 12340,
}) =>
    ManaLoanPosition(
      personId: '1',
      mlid: 'MLPI100000026',
      fullName: name,
      fatherHusbandName: careOf,
      village: village,
      inOperatingArea: true,
      loanId: loanId,
      balance: balance,
      lastCollection: null,
    );

void main() {
  group('item 5 - the roster row', () {
    final source = File(
            'lib/features/owner_workspace/screens/ow_012_business_management.dart')
        .readAsStringSync();

    test('the three-dot menu is gone from the member row', () {
      // Not "the file has no PopupMenuButton" -- the Operating Areas tab in
      // the same file legitimately has one. The member row is the region
      // between its build method and the class that follows it.
      final row = source.substring(source.indexOf('class _MemberRow'));
      final body = row.substring(0, row.indexOf('class _HoldForActions'));
      expect(body.contains('PopupMenuButton'), isFalse,
          reason: 'the member row grew its three-dot menu back; the Owner '
              'asked for tap-for-entry and hold-for-the-rest');
    });

    test('Reactivate is not offered to somebody who is already Active', () {
      final row = source.substring(source.indexOf('Future<void> _holdActions'));
      final body = row.substring(0, row.indexOf('@override'));
      // The guard is the condition, not the string: `reactivate` must sit
      // behind a test that the person is not active.
      final reactivate = body.indexOf("ref.t('reactivate')");
      expect(reactivate, greaterThan(-1),
          reason: 'Reactivate vanished entirely; a suspended member needs a '
              'way back');
      final before = body.substring(0, reactivate);
      expect(before, contains('if (!active)'),
          reason: "Reactivate must be behind `if (!active)`. Offering it on "
              'an active row was the finding: an option that cannot mean '
              'anything still has to be read, and it invites the thought '
              'that the person might not be active after all');
    });

    test('the hold is three seconds, not a default long-press', () {
      expect(source, contains('duration: const Duration(seconds: 3)'),
          reason: "Flutter's 500ms long-press is something a thumb does by "
              'accident while scrolling. Three seconds is the gate in front '
              'of removing somebody from a book, and it is what was asked for');
    });

    test('the hold shows progress while it runs', () {
      final hold = source.substring(source.indexOf('class _HoldForActionsState'));
      expect(hold, contains('LinearProgressIndicator'),
          reason: 'a three-second hold with no feedback is indistinguishable '
              'from a dead row for the first two of them -- somebody lets go '
              'at one second and concludes the list does not respond');
    });

    test('a tap that cannot open an entry says which reason applies', () {
      final tap = source.substring(source.indexOf('Future<void> _tap(BuildContext'));
      final body = tap.substring(0, tap.indexOf('/// Suspend, remove'));
      expect(body, contains("ref.t('entry_needs_mlid_note')"));
      expect(body, contains("ref.t('entry_closed_note')"),
          reason: 'silence on a tap reads as a broken row, and the two '
              'reasons differ: a locked migration is the BOOK being '
              'finished, a missing MLID is one PERSON being incomplete');
    });

    test('the gestures are named somewhere, since no row shows them', () {
      expect(source, contains("ref.t('members_gesture_hint')"),
          reason: 'removing the three dots removed the only thing on screen '
              'saying suspend and remove exist; a gesture nobody is told '
              'about is a feature nobody has');
    });
  });

  group('item 7 - one person is not a list of one', () {
    testWidgets('the header is the name, the MLID, the C/o and the village',
        (tester) async {
      await pumpManaScreen(
        tester,
        OnePersonEntryScreen(
          businessId: 'b1',
          positions: [_position()],
          onSaved: () async {},
        ),
      );
      expect(find.text('Ramesh Kumar Reddy Garu'), findsOneWidget);
      expect(find.text('MLPI100000026'), findsOneWidget);
      // C/o and village share the second line, joined.
      expect(
        find.textContaining('Venkata Subbaiah'),
        findsOneWidget,
        reason: 'the care-of name is what tells two men of the same name in '
            'one village apart',
      );
      expect(find.textContaining('Someswaram'), findsOneWidget);
      expectNoLayoutFault(tester, 'the one-person entry header');
    });

    testWidgets('it does not say "1 Customers"', (tester) async {
      await pumpManaScreen(
        tester,
        OnePersonEntryScreen(
          businessId: 'b1',
          positions: [_position()],
          onSaved: () async {},
        ),
      );
      // The exact finding, in the exact words it was reported in. The count
      // line belongs to a village book; here it was counting to one.
      expect(find.textContaining('Customers'), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing,
          reason: 'a magnifier over one person is a control that cannot do '
              'anything');
      expect(find.byIcon(Icons.expand_more), findsNothing,
          reason: 'nothing to expand: the loans are the screen, not a row to '
              'tap open');
    });

    testWidgets('the loans are drawn and Add Loan is below them',
        (tester) async {
      await pumpManaScreen(
        tester,
        OnePersonEntryScreen(
          businessId: 'b1',
          positions: [
            _position(),
            _position(loanId: 'loan-2', balance: 8000),
          ],
          onSaved: () async {},
        ),
      );
      final addLoan = find.byType(FilledButton);
      expect(addLoan, findsOneWidget);
      final loanCards = find.byType(Card);
      expect(tester.widgetList(loanCards).length, 2,
          reason: 'two live loans, two cards');
      // Position, not just presence: the Owner asked for it at the bottom,
      // and it is outside the scroll view so six loans do not bury it.
      final buttonY = tester.getTopLeft(addLoan).dy;
      final lastCardY = tester.getTopLeft(loanCards.last).dy;
      expect(buttonY, greaterThan(lastCardY),
          reason: 'Add Loan must sit below the loans, not above them');
    });

    testWidgets('a customer with no loan yet gets no phantom Rs 0 card',
        (tester) async {
      // The RPC returns a loan-less customer as a row on purpose, so their
      // village still counts a head and there is a way in. Drawing that row
      // as a loan would put Rs 0 in front of the Owner for a loan that does
      // not exist -- and this screen came from one that did exactly that.
      await pumpManaScreen(
        tester,
        OnePersonEntryScreen(
          businessId: 'b1',
          positions: [_position(loanId: '', balance: 0)],
          onSaved: () async {},
        ),
      );
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ListView), findsNothing,
          reason: 'no loans means no list, not an empty one');
      expect(find.byType(FilledButton), findsOneWidget,
          reason: 'the way in has to stay for the person who has no loan yet');
    });

    testWidgets('the header survives a long Telugu name at 2.0x',
        (tester) async {
      // Overflow is this project's recurring shipped bug, always a bare
      // unflexible child beside a flexible one, and a header of four fields
      // on one 360dp row is exactly that shape.
      await pumpManaScreen(
        tester,
        OnePersonEntryScreen(
          businessId: 'b1',
          positions: [
            _position(
              name: 'Kammalapati Venkata Subrahmanya Sastry Garu',
              careOf: 'Kammalapati Venkata Ramana Murthy',
              village: 'Chinna Ganjam Agraharam',
            ),
          ],
          onSaved: () async {},
        ),
        textScale: 2.0,
        language: ManaLanguage.telugu,
      );
      expectNoLayoutFault(tester, 'the one-person header at 2.0x in Telugu');
    });
  });
}

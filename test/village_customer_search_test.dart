import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_village_customers.dart';
import 'package:mana_line/features/owner_workspace/state/village_book_summary.dart';

import 'support/mana_harness.dart';

/// What this pins: a village of n people can be searched by the three things
/// somebody standing in it might have in hand.
///
/// The Owner, 2026-09-19: "add search - in one-by-one - customers - if there
/// are n customers user needs a search inside it by name, phone no, MLID."
///
/// Name and MLID already matched. The phone could not, and the reason is
/// worth keeping: `app.migration_customer_positions` -- the row this whole
/// screen is built from -- did not return mobile_number at all, so no amount
/// of filtering in the app could have found one. A search that silently
/// cannot match a third of what its label promises is worse than one that
/// says it only does two.
ManaLoanPosition _person({
  required String id,
  required String mlid,
  required String name,
  String careOf = '',
  String mobile = '',
}) =>
    ManaLoanPosition(
      personId: id,
      mlid: mlid,
      fullName: name,
      fatherHusbandName: careOf,
      mobile: mobile,
      village: 'Someswaram',
      inOperatingArea: true,
      loanId: '',
      balance: 0,
      lastCollection: null,
    );

/// Four people, two of them called Lakshmi -- which is the case the Owner is
/// describing when they say the count has gone up.
final _village = <ManaLoanPosition>[
  _person(
      id: '1',
      mlid: 'MLPI011111111',
      name: 'Lakshmi Devi',
      careOf: 'Ramana Rao',
      mobile: '9876543210'),
  _person(
      id: '2',
      mlid: 'MLPI022222222',
      name: 'Lakshmi Kumari',
      careOf: 'Venkat Reddy',
      mobile: '9000000002'),
  _person(
      id: '3',
      mlid: 'MLTI033333333',
      name: 'Suresh Babu',
      careOf: 'Ramana Rao',
      mobile: ''),
  _person(
      id: '4',
      mlid: 'MLPI044444444',
      name: 'Padma Latha',
      careOf: 'Suribabu',
      mobile: '9123456789'),
];

void main() {
  Future<void> open(WidgetTester t) async {
    await pumpManaScreen(
      t,
      VillageCustomersScreen(
        businessId: 'b1',
        title: 'Someswaram',
        positions: _village,
      ),
      surfaceSize: const Size(360, 900),
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.search));
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String q) async {
    await t.enterText(find.byType(TextField).first, q);
    await t.pumpAndSettle();
  }

  testWidgets('the search is offered once there is a list to search',
      (t) async {
    await open(t);
    expect(find.text('Search by name, phone or MLID'), findsOneWidget);
    expectNoLayoutFault(t, 'village customers with the search open');
  });

  testWidgets('a phone number finds its owner', (t) async {
    await open(t);
    await type(t, '9123456789');

    expect(find.text('Padma Latha'), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsNothing);
  });

  testWidgets('a partial phone number narrows rather than failing', (t) async {
    await open(t);
    // Somebody reads out the last four digits, which is what they remember.
    await type(t, '3210');

    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('Padma Latha'), findsNothing);
  });

  testWidgets('a number typed with spaces or +91 still finds it', (t) async {
    await open(t);
    // Non-digits are stripped from both sides, because a number copied out of
    // a phone book arrives with whatever punctuation it was written with.
    await type(t, '+91 98765 43210');

    expect(find.text('Lakshmi Devi'), findsOneWidget);
  });

  testWidgets('an MLID still finds its owner', (t) async {
    await open(t);
    await type(t, 'MLTI03');
    expect(find.text('Suresh Babu'), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsNothing);
  });

  testWidgets('a name that two people share returns both', (t) async {
    await open(t);
    await type(t, 'lakshmi');

    // Not a failure -- it is the situation. The count line says 2 / 4 so a
    // narrowed list is never mistaken for the whole village.
    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('Lakshmi Kumari'), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget);
  });

  testWidgets('the care-of name tells two of the same name apart', (t) async {
    await open(t);
    // Not on the Owner's list of three, but it is the field the row header
    // already shows to distinguish them, and a search that knows less than
    // the screen it sits on is a search somebody stops trusting.
    await type(t, 'ramana');

    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('Suresh Babu'), findsOneWidget);
    expect(find.text('Lakshmi Kumari'), findsNothing);
  });

  testWidgets('a customer with no phone is not lost by a text search',
      (t) async {
    await open(t);
    await type(t, 'suresh');
    // A paper-book customer may legitimately have no mobile --
    // persons_mlti_needs_hard_key accepts an Aadhaar OR a mobile OR
    // is_migrated -- and must still be findable by the things they do have.
    expect(find.text('Suresh Babu'), findsOneWidget);
  });

  testWidgets('a query nobody matches says so rather than showing everyone',
      (t) async {
    await open(t);
    await type(t, 'zzzqqq');
    expect(find.text('Lakshmi Devi'), findsNothing);
    expect(find.text('Padma Latha'), findsNothing);
    expect(find.text('0 / 4'), findsOneWidget);
  });

  testWidgets('clearing the search brings the whole village back', (t) async {
    await open(t);
    await type(t, 'padma');
    expect(find.text('1 / 4'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('Padma Latha'), findsOneWidget);
  });
}

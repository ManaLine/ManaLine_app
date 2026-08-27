import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';

import 'support/mana_harness.dart';

/// What this pins: how much a person has to type before a customer can be
/// created at a doorstep.
///
/// The form used to demand seven fields -- name, father/husband, gender,
/// mobile, PIN, door number and village. register_new_customer requires
/// three. persons is NOT NULL on full_name, father_husband_name and
/// gender_digit and nothing else; mobile and door_no are NULLIF'd inside the
/// RPC, and the whole person_addresses INSERT sits behind
/// `IF p_village_id IS NOT NULL`.
///
/// So the form was refusing registrations the database would have taken. At a
/// doorstep that means the customer is not created, the loan is not issued,
/// and the round moves on without them.
///
/// If someone tightens this again, this test says what it costs.
class _SeededCustomerList extends CustomerListNotifier {
  @override
  CustomerListState build() => const CustomerListState(customers: []);

  @override
  Future<void> load(String businessId) async {}

  /// No match, which is what puts the sheet on the Create New stage -- the
  /// doorstep case: somebody who is not in the book yet.
  @override
  Future<List<CustomerSummary>> searchIdentity({
    String? mlid,
    String? aadhaar,
    String? phone,
    String? fullName,
  }) async =>
      const [];
}

void main() {
  // Everything is scoped to the sheet. The screen BEHIND it has its own
  // search box, so an unscoped find.byType(TextField) types into the wrong
  // one and the sheet never leaves its first stage.
  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(BottomSheet), matching: f);

  Finder createButton() =>
      inSheet(find.widgetWithText(ElevatedButton, 'Create & Link to Business'));

  Future<void> openSheet(WidgetTester tester) async {
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1', initialAction: 'register'),
      overrides: [customerListProvider.overrideWith(_SeededCustomerList.new)],
      surfaceSize: const Size(360, 900),
    );
    await tester.pumpAndSettle();
  }


  /// The sheet scrolls, so the create button is not built until it is reached.
  Future<Finder> revealCreate(WidgetTester tester) async {
    final btn = createButton();
    if (btn.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        btn,
        200,
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
    }
    return btn;
  }

  /// The sheet opens on search, and Create New is reached only by searching
  /// for somebody who is not there. That is the doorstep case exactly.
  Future<void> gotoCreateNew(WidgetTester tester) async {
    await tester.enterText(
        inSheet(find.byType(TextField)).first, 'Somebody Not In The Book');
    await tester.pumpAndSettle();
    // The box does not submit on its own -- there is a Search button beside it.
    await tester.tap(inSheet(find.widgetWithText(ElevatedButton, 'Search')).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('three fields are enough to create a customer', (tester) async {
    await openSheet(tester);
    await gotoCreateNew(tester);

    final fields = inSheet(find.byType(TextField));
    expect(fields, findsWidgets, reason: 'the create-new form did not open');

    // Name and father/husband are the first two text fields on the stage.
    await tester.enterText(fields.at(0), 'Nagabhushanam Venkata Subba Reddy');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Garikipati Venkata Subba Rami Reddy');
    await tester.pumpAndSettle();

    // Gender is the only other thing the server insists on.
    final gender = inSheet(find.byType(DropdownButtonFormField<String>));
    expect(gender, findsWidgets, reason: 'no gender control');
    await tester.tap(gender.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    final btn = await revealCreate(tester);
    expect(btn, findsOneWidget, reason: 'create button missing');

    // No mobile, no Aadhaar, no address. This is the doorstep case.
    expect(
      tester.widget<ElevatedButton>(btn).onPressed,
      isNotNull,
      reason: 'name + father/husband + gender must be enough -- the server '
          'accepts exactly that, and the form must not be stricter',
    );
  });

  testWidgets('a half-typed mobile is still refused', (tester) async {
    await openSheet(tester);
    await gotoCreateNew(tester);

    final fields = inSheet(find.byType(TextField));
    await tester.enterText(fields.at(0), 'Chalasani Ramana');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Chalasani Rao');
    await tester.pumpAndSettle();

    final gender = inSheet(find.byType(DropdownButtonFormField<String>));
    await tester.tap(gender.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Optional does not mean unvalidated: four digits is a typo, not a
    // decision to leave it blank.
    await tester.enterText(fields.at(2), '9493');
    await tester.pumpAndSettle();

    final btn = await revealCreate(tester);
    expect(tester.widget<ElevatedButton>(btn).onPressed, isNull,
        reason: 'a partial mobile number must still block the save');
  });
}

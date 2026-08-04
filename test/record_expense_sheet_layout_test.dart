import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/widgets/record_expense_sheet.dart';

import 'support/mana_harness.dart';

/// The expense sheet is a brand-new surface, and new surfaces are exactly
/// where this repo's overflow bug keeps appearing -- LR-003, LR-007, LR-013
/// and OW-019 all shipped with one.
///
/// The risky parts here are specific: the payer note is a full sentence
/// (the agent variant runs to two lines before scaling), the category
/// dropdown has to fit "External Chit", and the action Row puts two labelled
/// buttons side by side. That is the same shape as the LR-013 header that
/// overflowed 277px at 2.0x.
///
/// The sheet is pumped directly rather than through its host screens: both
/// hosts load from Supabase in initState, and a test that lays out an empty
/// loading state would prove nothing about the sheet itself.
void main() {
  Widget sheet({required String payerNote}) => Scaffold(
        body: RecordExpenseSheet(
          payerNote: payerNote,
          onSubmit: ({required category, required amount, remarks}) async {},
        ),
      );

  // The longer of the two real notes -- the agent one, which is the two
  // sentence variant. Testing the short Owner note only would measure a
  // narrower layout than production.
  const agentNote = 'Paid from your own cash in hand. This reduces what you '
      'hand over at settlement.';
  const ownerNote = 'Paid from your own balance (Owner BF).';

  for (final scale in kManaTextScales) {
    testWidgets('Record Expense sheet survives text scale ${scale}x',
        (tester) async {
      await pumpManaScreen(tester, sheet(payerNote: agentNote),
          textScale: scale);
      expectNoLayoutFault(tester, 'Record Expense sheet at ${scale}x');
    });
  }

  testWidgets('Owner variant survives the largest scale', (tester) async {
    await pumpManaScreen(tester, sheet(payerNote: ownerNote), textScale: 2.0);
    expectNoLayoutFault(tester, 'Record Expense sheet, Owner note at 2.0x');
  });

  testWidgets('every expense_category_enum value is offered', (tester) async {
    await pumpManaScreen(tester, sheet(payerNote: ownerNote));

    // These are the enum's members, not a UI list: the RPC casts the string
    // straight to expense_category_enum, so a value missing here is a
    // category the app simply cannot record, and an extra one is a
    // guaranteed server-side cast failure.
    expect(
      kExpenseCategories,
      const ['General', 'Travel', 'Salary', 'Fuel', 'External Chit', 'Other'],
    );
  });

  testWidgets('a non-positive amount is refused before any RPC call',
      (tester) async {
    var submitted = false;
    await pumpManaScreen(
      tester,
      Scaffold(
        body: RecordExpenseSheet(
          payerNote: ownerNote,
          onSubmit: ({required category, required amount, remarks}) async {
            submitted = true;
          },
        ),
      ),
    );

    // Money columns are numeric(_,0) and the RPC refuses <= 0 anyway; the
    // point of the local check is that a typo never reaches a money path.
    // Found by type, not by label: ManaText enforces Title Case on the
    // translation key, so find.text('record') matches nothing rendered.
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(submitted, isFalse,
        reason: 'a zero amount must not reach record_expense');
    expect(find.textContaining('above zero'), findsOneWidget);
  });
}

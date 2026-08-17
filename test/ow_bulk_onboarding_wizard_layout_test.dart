import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';

import 'support/mana_harness.dart';

/// Walks the wizard one page at a time. Every page is laid out at 2.0x on a
/// 360dp surface, because overflow is this project's recurring bug class and it
/// is invisible to `flutter analyze`.
Future<void> _advance(WidgetTester tester) async {
  await tester.ensureVisible(find.text('next').last);
  await tester.tap(find.text('next').last);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Pre-Existing Business Wizard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BulkOnboardingWizardScreen(businessId: 'b1'),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Pre-Existing Business Wizard at ${scale}x');

      // Page 1 is the first thing an Owner sees, and the sentence that tells
      // them nothing is saved yet is the one they must not miss.
      expect(find.textContaining('Nothing is saved on this page'), findsOneWidget);
    });
  }

  testWidgets('the header names the page and its position', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    expectNoLayoutFault(tester, 'Pre-Existing Business Wizard fully laid out');
    expect(find.text('1. Identities'), findsOneWidget);
    expect(find.text('1/8'), findsOneWidget);
  });

  testWidgets('nothing can be imported before a file is chosen', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    expect(find.text('Save Areas And Import Identities'), findsNothing);
    expect(find.text('Import Investments'), findsNothing);
    expect(find.text('Import Loans And History'), findsNothing);
  });

  testWidgets('every page survives 2.0x once navigated to', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      textScale: 2.0,
      surfaceSize: const Size(360, 2400),
    );

    const expectations = <String, String>{
      '2. Areas & Villages': 'No villages yet',
      '3. Investors': 'equity',
      '4. Customers': 'One sheet per repayment frequency',
      '5. Agents': 'Which days each agent worked',
      '6. Opening Snapshot': 'No cut-off date chosen',
      '7. Weekly Account': 'one row per line',
    };

    for (final entry in expectations.entries) {
      await _advance(tester);
      expectNoLayoutFault(tester, 'Pre-Existing Business Wizard ${entry.key} at 2.0x');
      expect(find.text(entry.key), findsOneWidget,
          reason: 'expected to be on ${entry.key}');
      expect(find.textContaining(entry.value), findsWidgets,
          reason: 'expected ${entry.key} to explain itself');
    }

    // …and the Finish page, reached by the button that says so rather than
    // "next".
    await tester.ensureVisible(find.text('finish').last);
    await tester.tap(find.text('finish').last);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expectNoLayoutFault(tester, 'Pre-Existing Business Wizard Finish at 2.0x');
    expect(find.text('8. Finish'), findsOneWidget);
  });
}

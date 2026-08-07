import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Bulk Onboarding Wizard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BulkOnboardingWizardScreen(businessId: 'b1'),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Bulk Onboarding Wizard at ${scale}x');

      // Step 1 is the first thing an Owner sees — its dedupe-review
      // explanation is the sentence that tells them why some rows might not
      // import immediately, so it must survive scaling.
      expect(find.textContaining('flagged for you to'), findsOneWidget);
    });
  }

  testWidgets('all four step chips are present on a surface that fits them', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    expectNoLayoutFault(tester, 'Bulk Onboarding Wizard fully laid out');
    expect(find.text('1. Identities'), findsOneWidget);
    expect(find.text('2. Details'), findsOneWidget);
    expect(find.text('3. EMI History'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets('import is not offered before a file is chosen', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    expect(find.text('Import Identities'), findsNothing);
  });

  testWidgets('step 2 (Details) survives at 2.0x once navigated to', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      textScale: 2.0,
      surfaceSize: const Size(360, 1600),
    );
    await tester.tap(find.text('next'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expectNoLayoutFault(tester, 'Bulk Onboarding Wizard step 2 at 2.0x');
    expect(find.textContaining('prefilled with'), findsOneWidget);
  });

  testWidgets('step 3 (EMI History) survives at 2.0x once navigated to', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      textScale: 2.0,
      surfaceSize: const Size(360, 1600),
    );
    await tester.tap(find.text('next'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('next'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expectNoLayoutFault(tester, 'Bulk Onboarding Wizard step 3 at 2.0x');
    expect(find.textContaining('Optional.'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

import 'support/mana_harness.dart';

/// A book with every section in it, so every page exists and can be laid out.
/// An Owner who has said nothing about their book correctly sees only the
/// chooser, which is a different test.
class _FullBook implements BulkOnboardingService {
  _FullBook({this.step});

  /// Where the wizard opens. The page-walker starts on Identities rather than
  /// the chooser, whose action is "Start" and whose own layout the text-scale
  /// tests already cover.
  final int? step;

  @override
  Future<int?> wizardStep(String businessId) async => step;

  @override
  Future<void> saveWizardStep(String businessId, int step) async {}

  @override
  Future<MigrationPlan?> migrationPlan(String businessId) async => MigrationPlan(
        investors: true,
        shareholders: true,
        customers: true,
        emiHistory: true,
        attendance: true,
        weekly: true,
        profit: true,
        cutoff: DateTime(2026, 3, 20),
      );

  @override
  Future<List<String>> migrationPlanGaps(String businessId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
        overrides: [
          bulkOnboardingServiceProvider.overrideWithValue(_FullBook())
        ],
      );
      await tester.pump();
      await tester.pump();
      expectNoLayoutFault(tester, 'Pre-Existing Business Wizard at ${scale}x');

      // Page 1 is now the chooser: what the book has, and the cut-off every
      // other page states its figures as at.
      expect(find.textContaining('Tell us what your book has'), findsOneWidget);
    });
  }

  testWidgets('the header names the page and its position', (tester) async {
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
      overrides: [bulkOnboardingServiceProvider.overrideWithValue(_FullBook())],
    );
    await tester.pump();
    await tester.pump();
    expectNoLayoutFault(tester, 'Pre-Existing Business Wizard fully laid out');
    expect(find.text('1. What Your Book Has'), findsOneWidget);
    // Eight pages for a book with everything in it.
    expect(find.text('1/8'), findsOneWidget);
  });

  testWidgets('a book that has said nothing yet shows only the chooser',
      (tester) async {
    // No plan: the wizard must not march an Owner through pages for sections
    // they may not have, and cannot know which pages those are until they say.
    await pumpManaScreen(
      tester,
      const BulkOnboardingWizardScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 1600),
    );
    await tester.pump();
    expect(find.text('1. What Your Book Has'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
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
      overrides: [
        bulkOnboardingServiceProvider.overrideWithValue(_FullBook(step: 1))
      ],
    );
    await tester.pump();
    await tester.pump();

    // Opened on Identities, so the walk below starts from the page after it.
    expect(find.text('2. Identities'), findsOneWidget);
    expectNoLayoutFault(tester, 'Pre-Existing Business Wizard 2. Identities at 2.0x');

    const expectations = <String, String>{
      // The chooser is page 1; Areas & Villages is gone entirely — villages
      // and areas are set up before the wizard is opened, and a village typed
      // fresh into the identity sheet is created by the import.
      '3. Investors': 'equity',
      '4. Customers': 'One sheet per repayment frequency',
      '5. Agents': 'Which days each agent worked',
      '6. Opening Snapshot': 'Cut-off',
      '7. Weekly Account': 'one row per account',
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

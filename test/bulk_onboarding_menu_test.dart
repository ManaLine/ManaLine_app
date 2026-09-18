import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_menu.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_pages.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

const _businessId = '0b726425-2338-49e5-bea1-6856624995b4';

/// `implements`, not `extends` — the real service reaches Supabase.instance,
/// which is not initialised in a test process. Same reason as
/// bulk_onboarding_resume_test.dart's fake.
class _FakeService implements BulkOnboardingService {
  _FakeService({this.plan, this.progress, this.sheetThrows = false});

  final MigrationPlan? plan;
  final Map<String, dynamic>? progress;
  final bool sheetThrows;

  int? savedStep;
  final downloaded = <String>[];

  @override
  Future<MigrationPlan?> migrationPlan(String businessId) async => plan;

  @override
  Future<MigrationProgress> migrationProgress(String businessId) async =>
      MigrationProgress(progress ?? const {});

  @override
  Future<void> saveWizardStep(String businessId, int step) async =>
      savedStep = step;

  @override
  Future<void> shareBytes(Uint8List bytes, String fileName) async =>
      downloaded.add(fileName);

  @override
  Future<Uint8List> buildCustomerGridTemplate({
    required String businessId,
    required String language,
  }) async {
    if (sheetThrows) throw Exception('the workbook could not be built');
    return Uint8List(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A book with everything in it, so every sheet and every step is offered.
const _fullPlan = MigrationPlan(
  investors: true,
  shareholders: true,
  customers: true,
  emiHistory: true,
  attendance: true,
  weekly: true,
  profit: true,
);

Future<_FakeService> _pump(
  WidgetTester tester, {
  MigrationPlan? plan = _fullPlan,
  Map<String, dynamic>? progress,
  bool sheetThrows = false,
  double textScale = 1.0,
  ManaLanguage language = ManaLanguage.english,
  // A DESK, for the tests that read content. This screen's list runs past
  // the bottom of a 360x640 phone, and a ListView only builds what is on
  // screen -- so a small surface makes "the step is missing" and "the step
  // is below the fold" the same failure. The layout sweep at the end keeps
  // the phone, which is the size that actually overflows.
  Size surfaceSize = const Size(1280, 1600),
}) async {
  final svc =
      _FakeService(plan: plan, progress: progress, sheetThrows: sheetThrows);
  await pumpManaScreen(
    tester,
    const BulkOnboardingMenuScreen(businessId: _businessId),
    textScale: textScale,
    language: language,
    surfaceSize: surfaceSize,
    overrides: [bulkOnboardingServiceProvider.overrideWithValue(svc)],
  );
  // The plan and the counts are two awaits behind the first frame.
  await tester.pump();
  await tester.pump();
  return svc;
}

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('the step list has exactly one definition', () {
    // The menu writes a step pointer that the WIZARD restores. Two copies of
    // the list would agree until the first time a page was added, and then
    // the menu's "Customers" button would open Agents.
    test('the wizard no longer keeps a private copy', () {
      final wizard = _code(
          'lib/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart');
      expect(wizard, isNot(contains('enum _WizardPage')));
      expect(wizard, isNot(contains('_pagesFor(')));
      expect(wizard, contains('manaBulkPagesFor(_plan)'));
    });

    test('the plan decides which steps exist', () {
      expect(manaBulkPagesFor(null), [ManaBulkPage.plan],
          reason: 'an Owner who has not said what their book holds has '
              'nothing else to be shown yet');

      expect(manaBulkPagesFor(const MigrationPlan(customers: false)), [
        ManaBulkPage.plan,
        ManaBulkPage.identities,
        ManaBulkPage.snapshot,
        ManaBulkPage.finish,
      ]);

      expect(manaBulkPagesFor(_fullPlan).length, 8);
    });

    test('shareholders alone still open the investors step', () {
      // They share a page. A book with profit shares and no investors must
      // not lose the only step that can record them.
      expect(
        manaBulkPagesFor(const MigrationPlan(customers: false, shareholders: true)),
        contains(ManaBulkPage.investors),
      );
    });
  });

  group('the menu is the journey, not a second wizard', () {
    final menu = _code(
        'lib/features/owner_workspace/screens/ow_bulk_onboarding_menu.dart');

    test('it downloads, and never imports', () {
      // The whole design rests on this split: downloading is orderless and
      // writes nothing, importing is ordered and writes money. An import
      // landing here would be a second code path for a write the wizard
      // already owns, with none of its parse, duplicate review or commit.
      for (final importer in const [
        'bulkImportIdentities',
        'importMigratedLoans',
        'importWeeklyAccount',
        'openFile(',
      ]) {
        expect(menu, isNot(contains(importer)),
            reason: '$importer belongs in the wizard');
      }
      expect(menu, contains('shareBytes'));
    });

    test('the Open button uses the verb, not the loan-status word', () {
      // ui_translations.open is Telugu "తెరిచి ఉంది" — "IS open", which is
      // right for a loan and wrong on a button. It would have read "Is Open"
      // for every Telugu user while looking perfect in English.
      expect(menu, contains("ref.t('bulk_menu_open_step')"));
      expect(menu, isNot(contains("ref.t('open')")));
    });
  });

  group('what it shows', () {
    testWidgets('no plan yet: one card, and it starts the chooser',
        (tester) async {
      final svc = await _pump(tester, plan: null);
      expect(find.text('Start With Your Book'), findsOneWidget);
      expect(find.text('Get Your Sheets'), findsNothing,
          reason: 'there is nothing to download until the book is described');

      await tester.tap(find.text('Start With Your Book'));
      await tester.pump();
      expect(svc.savedStep, isNull,
          reason: 'the chooser is step 0 — writing a pointer to it would '
              'overwrite a real resume position with the first page');
    });

    testWidgets('a full book is offered every sheet', (tester) async {
      await _pump(tester);
      for (final sheet in const [
        'Identities',
        'Investors',
        'Withdrawals',
        'Profit Shares',
        'Customers',
        'Agent Attendance',
        'Weekly Account',
      ]) {
        expect(find.text(sheet), findsWidgets, reason: '$sheet is missing');
      }
    });

    testWidgets('a book with no investors is offered no investor sheet',
        (tester) async {
      await _pump(tester, plan: const MigrationPlan(customers: true));
      expect(find.text('Withdrawals'), findsNothing);
      expect(find.text('Profit Shares'), findsNothing);
      expect(find.text('Customers'), findsWidgets);
    });

    testWidgets('the counts come from live rows, and read as words',
        (tester) async {
      await _pump(tester, progress: const {
        'customers': 55,
        'investors': 3,
        'agents': 1,
        'loans': 1,
      });
      expect(find.text('59 people'), findsOneWidget);
      // Singular, because "1 loans" is how a screen tells somebody it was
      // assembled by a machine that was not paying attention.
      expect(find.text('1 loan'), findsOneWidget);
    });

    testWidgets('a failed call shows no count rather than a zero',
        (tester) async {
      // Claiming an empty book because a call failed is the one thing this
      // line must never do — an Owner would import everything again.
      await _pump(tester, progress: const {});
      expect(find.textContaining('0 '), findsNothing);
    });

    testWidgets('no cut-off date says so instead of leaving a blank',
        (tester) async {
      await _pump(tester);
      expect(find.text('Not Chosen Yet'), findsOneWidget);
    });
  });

  group('handing over to the wizard', () {
    testWidgets('a step writes the pointer the wizard restores',
        (tester) async {
      final svc = await _pump(tester);
      // Customers is index 3 of the full eight: plan, identities, investors,
      // customers. Computed here from the shared list rather than typed, so
      // this test cannot drift from the screen it is checking.
      // Both numbers come from the shared list rather than being typed, so
      // this test cannot drift from the screen it is checking.
      final pages = manaBulkPagesFor(_fullPlan);
      final want = pages.indexOf(ManaBulkPage.customers);
      // The chooser has no Open button, so the nth button is the (n+1)th page.
      final button = pages
          .where((p) => p != ManaBulkPage.plan)
          .toList()
          .indexOf(ManaBulkPage.customers);

      final opens = find.text('Open');
      expect(opens, findsNWidgets(pages.length - 1));
      await tester.tap(opens.at(button));
      await tester.pump();
      expect(svc.savedStep, want);
    });
  });

  group('it lays out', () {
    // A DESKTOP screen — the first in this app to set a max width — but the
    // 360x640 sweep still has to pass. Nothing stops an Owner opening the
    // website on the phone in their hand.
    for (final scale in kManaTextScales) {
      testWidgets('at text scale ${scale}x', (tester) async {
        await _pump(tester,
            textScale: scale,
            surfaceSize: kManaSmallPhone,
            progress: const {'customers': 55});
        expectNoLayoutFault(tester, 'Bulk onboarding menu at ${scale}x');
      });

      testWidgets('at text scale ${scale}x in Telugu', (tester) async {
        await _pump(
          tester,
          textScale: scale,
          language: ManaLanguage.telugu,
          surfaceSize: kManaSmallPhone,
          progress: const {'customers': 55},
        );
        expectNoLayoutFault(
            tester, 'Bulk onboarding menu at ${scale}x in Telugu');
      });
    }
  });
}

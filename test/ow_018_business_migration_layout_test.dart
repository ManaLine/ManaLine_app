import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_018_business_migration.dart';
import 'package:mana_line/features/owner_workspace/state/business_management_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// `implements`, not `extends` — the real service reaches Supabase.instance.
class _FakeApi implements BusinessManagementApiService {
  _FakeApi(this._summary);
  final MigrationSummary _summary;

  @override
  Future<MigrationSummary> fetchMigrationSummary({required String businessId}) async => _summary;

  @override
  Future<int> fetchInvestorPayableBalance({
    required String businessId,
    DateTime? asOf,
  }) async => 250000;

  @override
  Future<int> fetchBusinessProfit({
    required String businessId,
    DateTime? asOf,
  }) async => 87500;

  /// No snapshot: this fake stands in for a book part-way through migration,
  /// so the screen falls back to the derived profit.
  @override
  Future<({DateTime cutoff, int declaredProfit})?> fetchMigrationSnapshot({
    required String businessId,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _open = MigrationSummary(
  migrationLocked: false,
  businessStartedAt: null,
  investmentPrincipal: 500000,
  migratedLoanCount: 12,
  totalGiven: 800000,
  totalCollected: 300000,
  lineBalance: 500000,
  bf: 250000,
  openingBfDeclaredAmount: 250000,
  openingBfDeclaredOn: DateTime(2026, 8, 1),
);

final _locked = MigrationSummary(
  migrationLocked: true,
  businessStartedAt: DateTime(2026, 7, 1),
  investmentPrincipal: 0,
  migratedLoanCount: 40,
  totalGiven: 0,
  totalCollected: 0,
  lineBalance: 120000,
  bf: 90000,
  openingBfDeclaredAmount: 90000,
  openingBfDeclaredOn: DateTime(2026, 7, 1),
);

const _telugu = <String, Map<String, String>>{
  'pre_existing_business': {'English': 'Pre-Existing Business', 'Telugu': 'ముందుగా ఉన్న వ్యాపారం'},
  'add_existing_loan': {'English': 'Add Existing Loan', 'Telugu': 'ఇప్పటికే ఉన్న రుణం జోడించండి'},
  'bulk_onboarding_wizard': {'English': 'Bulk Onboarding Wizard', 'Telugu': 'బల్క్ ఆన్‌బోర్డింగ్ విజార్డ్'},
  'finish_migration': {'English': 'Finish Migration', 'Telugu': 'మైగ్రేషన్ ముగించండి'},
  'migration_closed': {'English': 'Migration Closed', 'Telugu': 'మైగ్రేషన్ మూసివేయబడింది'},
  'migration_open': {'English': 'Migration Open', 'Telugu': 'మైగ్రేషన్ తెరిచి ఉంది'},
  'locked': {'English': 'Locked', 'Telugu': 'లాక్ చేయబడింది'},
  'open_status': {'English': 'Open', 'Telugu': 'తెరిచి ఉంది'},
  'migration_locked_note': {
    'English': 'This business was started on {date}. Reopen migration to enter records from the old book.',
    'Telugu': 'ఈ వ్యాపారం {date}న ప్రారంభమైంది. పాత పుస్తకం నుండి రికార్డులను నమోదు చేయడానికి మైగ్రేషన్ తిరిగి తెరవండి.',
  },
  'migration_open_note': {
    'English': 'Enter the loans that were already running when you joined. Each one records what you gave out and what has come back.',
    'Telugu': 'మీరు చేరినప్పుడు ఇప్పటికే నడుస్తున్న రుణాలను నమోదు చేయండి. ప్రతి ఒక్కటి మీరు ఇచ్చినది మరియు తిరిగి వచ్చినది నమోదు చేస్తుంది.',
  },
  'pre_existing_loans_entered_note': {'English': '{count} pre-existing loans entered', 'Telugu': '{count} ముందుగా ఉన్న రుణాలు నమోదు చేయబడ్డాయి'},
  'reopen_migration': {'English': 'Reopen Migration', 'Telugu': 'మైగ్రేషన్ తిరిగి తెరవండి'},
  'bf_cash_in_hand': {'English': 'BF — Cash in Hand', 'Telugu': 'BF — చేతిలో నగదు'},
  'bf_declared_on_note': {'English': 'Declared on {date}', 'Telugu': '{date}న ప్రకటించబడింది'},
  'bf_locked_suffix': {'English': ' — locked', 'Telugu': ' — లాక్ చేయబడింది'},
  'declare_opening_bf': {'English': 'Declare Opening BF', 'Telugu': 'ప్రారంభ BF ప్రకటించండి'},
  'change_opening_bf': {'English': 'Change Opening BF', 'Telugu': 'ప్రారంభ BF మార్చండి'},
  'line_balance_label': {'English': 'Line balance — still with customers', 'Telugu': 'లైన్ నిల్వ — ఇంకా కస్టమర్ల వద్ద'},
  'line_balance_note': {
    'English': 'Line balance is deliberately outside BF — that money is out on the line, not in the cash box.',
    'Telugu': 'లైన్ నిల్వ ఉద్దేశపూర్వకంగా BF వెలుపల ఉంది — ఆ డబ్బు లైన్‌లో ఉంది, నగదు పెట్టెలో కాదు.',
  },
  'profit_and_investor_payable': {'English': 'Profit & Investor Payable', 'Telugu': 'లాభం & పెట్టుబడిదారుకు చెల్లించవలసినది'},
  'owed_back_to_investors': {'English': 'Owed back to investors', 'Telugu': 'పెట్టుబడిదారులకు తిరిగి చెల్లించవలసినది'},
  'business_profit': {'English': 'Business profit', 'Telugu': 'వ్యాపార లాభం'},
};

void main() {
  for (final c in [('open', _open), ('locked', _locked)]) {
    for (final scale in kManaTextScales) {
      testWidgets('OW-018 ${c.$1} survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(tester, const BusinessMigrationScreen(businessId: 'b1'),
            textScale: scale,
            overrides: [businessManagementApiServiceProvider.overrideWithValue(_FakeApi(c.$2))]);
        await tester.pump();
        await tester.pump();
        expectNoLayoutFault(tester, 'OW-018 ${c.$1} at ${scale}x');
      });

      testWidgets('OW-018 ${c.$1} survives text scale ${scale}x in Telugu', (tester) async {
        await pumpManaScreen(tester, const BusinessMigrationScreen(businessId: 'b1'),
            textScale: scale,
            language: ManaLanguage.telugu,
            translations: _telugu,
            overrides: [businessManagementApiServiceProvider.overrideWithValue(_FakeApi(c.$2))]);
        await tester.pump();
        await tester.pump();
        expectNoLayoutFault(tester, 'OW-018 ${c.$1} at ${scale}x in Telugu');
      });
    }
  }
  // OW-018's two dialogs, neither of which had a test opening it.
  //
  // They are gated on opposite states: Reopen Migration only exists once the
  // migration is LOCKED, and Declare Opening BF only while it is still open.
  // Seeding one summary would have proved at most half of it.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('OW-018 reopen migration dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, const BusinessMigrationScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _telugu : null,
            overrides: [businessManagementApiServiceProvider.overrideWithValue(_FakeApi(_locked))]);
        await tester.pumpAndSettle();

        final button = find.byType(OutlinedButton);
        for (var i = 0; i < 6 && button.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(button, findsWidgets, reason: 'no reopen button on a locked migration');
        await tester.ensureVisible(button.first);
        await tester.pumpAndSettle();
        await tester.tap(button.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'reopen migration dialog did not open');
        expectNoLayoutFault(tester, 'OW-018 reopen at ${scale}x$tag');
      });

      testWidgets('OW-018 declare opening BF dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(tester, const BusinessMigrationScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _telugu : null,
            overrides: [businessManagementApiServiceProvider.overrideWithValue(_FakeApi(_open))]);
        await tester.pumpAndSettle();

        // OutlinedButton.icon, so it is an OutlinedButton too -- the open
        // summary draws no reopen button, which leaves this the only one.
        final button = find.byType(OutlinedButton);
        for (var i = 0; i < 8 && button.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(button, findsWidgets, reason: 'no declare-BF button on an open migration');
        await tester.ensureVisible(button.first);
        await tester.pumpAndSettle();
        await tester.tap(button.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'declare opening BF dialog did not open');
        expectNoLayoutFault(tester, 'OW-018 declare BF at ${scale}x$tag');
      });
    }
  }
}

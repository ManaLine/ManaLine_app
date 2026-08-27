import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_003_investor_management.dart';
import 'package:mana_line/features/owner_workspace/state/investor_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-003's Investor Profile is a two-tab drill-in that OW-003's existing
/// layout tests never opened -- they pumped the investor list only. Both tabs
/// are walked here, since TabBarView lays out just the visible one.
class _SeededInvestorProfile extends InvestorProfileNotifier {
  _SeededInvestorProfile(this._seed);
  final InvestorProfile _seed;

  @override
  Future<InvestorProfile> build(String investorId) async => _seed;
}

void main() {
  final investor = InvestorSummary(
    investorId: 'i1',
    fullName: 'Nagabhushanam Venkata Subba Reddy',
    mlid: 'MLIN0000012345',
    phoneNumber: '9493509919',
    investmentBalance: 1284500,
    roi: 2.5,
    interestDue: 32112,
    membershipStatus: 'Active',
    lastTransaction: DateTime(2026, 8, 20),
  );

  final profile = InvestorProfile(
    summary: investor,
    investments: [
      InvestmentRecord(
        investmentId: 'inv1',
        principalAmount: 1000000,
        roiRate: 2.5,
        interestMethod: 'Monthly Payout',
        effectiveDate: DateTime(2025, 11, 3),
        interestAccrued: 62500,
        interestPaid: 30388,
        originalPrincipal: 1000000,
        totalInterestEarned: 92888,
        status: 'Active',
        profitSharePercent: 1.5,
      ),
    ],
  );

  Widget screen() => InvestorProfileScreen(businessId: 'b1', investor: investor);

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      for (var i = 0; i < 2; i++) {
        testWidgets('OW-003 investor profile tab $i survives text scale ${scale}x$tag',
            (tester) async {
          await pumpManaScreen(
            tester,
            screen(),
            textScale: scale,
            language: lang,
            overrides: [
              investorProfileProvider.overrideWith(() => _SeededInvestorProfile(profile)),
            ],
          );
          await tester.pumpAndSettle();

          if (i > 0) {
            // ensureVisible first: the TabBar scrolls, so a later tab sits
            // off-screen and a tap with warnIfMissed off lands on nothing
            // in silence -- which is how these walks reported every tab
            // clean while never leaving the first one.
            await tester.ensureVisible(find.byType(Tab).at(i));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
          expectNoLayoutFault(tester, 'OW-003 investor profile tab $i at ${scale}x$tag');
        });
      }
    }
  }
  // The two dialogs reachable from this profile. Both carry scrollable: true,
  // applied in a sweep with no test opening them; these open them.
  //
  // Each asserts the dialog is on screen before measuring. A tap that lands
  // on a disabled or off-screen button is silent, and without the assertion a
  // green result would prove only that nothing happened.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('OW-003 withdraw dialog survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          screen(),
          textScale: scale,
          language: lang,
          overrides: [
            investorProfileProvider.overrideWith(() => _SeededInvestorProfile(profile)),
          ],
        );
        await tester.pumpAndSettle();
        // Withdraw lives on the Investments tab.
        // ensureVisible first: the TabBar scrolls, so a later tab sits
        // off-screen and a tap with warnIfMissed off lands on nothing
        // in silence -- which is how these walks reported every tab
        // clean while never leaving the first one.
        await tester.ensureVisible(find.byType(Tab).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
        await tester.pumpAndSettle();

        final withdraw = find.byType(OutlinedButton);
        expect(withdraw, findsWidgets, reason: 'no withdraw button on the investment row');
        await tester.ensureVisible(withdraw.first);
        await tester.pumpAndSettle();
        await tester.tap(withdraw.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'withdraw dialog did not open');
        expectNoLayoutFault(tester, 'OW-003 withdraw dialog at ${scale}x$tag');
      });
    }
  }
  // Record Investment, on the Investments tab. The third of OW-003's dialogs
  // and the second reachable from this profile; it took scrollable: true in a
  // sweep with nothing opening it.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-003 record investment dialog survives ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          screen(),
          textScale: scale,
          language: lang,
          overrides: [
            investorProfileProvider.overrideWith(() => _SeededInvestorProfile(profile)),
          ],
        );
        await tester.pumpAndSettle();
        // ensureVisible first: the TabBar scrolls, so a later tab sits
        // off-screen and a tap with warnIfMissed off lands on nothing
        // in silence -- which is how these walks reported every tab
        // clean while never leaving the first one.
        await tester.ensureVisible(find.byType(Tab).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
        await tester.pumpAndSettle();

        // Gated on an Active membership -- the seed is Active, so a missing
        // button means the tab did not open, not that the rule fired.
        final record = find.byType(ElevatedButton);
        expect(record, findsWidgets, reason: 'no Record Investment button');
        await tester.ensureVisible(record.first);
        await tester.pumpAndSettle();
        await tester.tap(record.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'record investment dialog did not open');
        expectNoLayoutFault(tester, 'OW-003 record investment at ${scale}x$tag');
      });
    }
  }
}

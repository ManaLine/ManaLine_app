import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/investor_workspace/screens/iw_003_my_investments.dart';
import 'package:mana_line/features/investor_workspace/state/my_investments_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededMyInvestmentsListNotifier extends MyInvestmentsListNotifier {
  _SeededMyInvestmentsListNotifier(this._seed);
  final MyInvestmentsListState _seed;

  @override
  MyInvestmentsListState build(MyInvestmentsKey arg) => _seed;

  @override
  Future<void> load() async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807175039 + reused earlier keys).
const _iw003TeluguTranslations = <String, Map<String, String>>{
  'my_investments': {'English': 'My Investments', 'Telugu': 'నా పెట్టుబడులు'},
  'investment_meta_note': {
    'English': '{id} · {roi} · {method} · since {date}',
    'Telugu': '{id} · {roi} · {method} · {date} నుండి',
  },
  'accrued_this_year_note': {
    'English': 'Accrued this year: {amount} · Total earned: {total}',
    'Telugu': 'ఈ సంవత్సరం పోగుపడింది: {amount} · మొత్తం సంపాదించింది: {total}',
  },
  'accrued_note': {
    'English': 'Accrued: {amount} · Total earned: {total}',
    'Telugu': 'పోగుపడింది: {amount} · మొత్తం సంపాదించింది: {total}',
  },
  'paid_short_note': {'English': 'Paid: {amount}', 'Telugu': 'చెల్లించినది: {amount}'},
};

void main() {
  final investments = [
    InvestorInvestmentSummary(
      investmentId: 'INV-0000012345',
      principalAmount: 500000,
      roiRate: 1.5,
      interestMethod: 'Yearly Compound',
      effectiveDate: DateTime(2024, 4, 1),
      interestAccrued: 45000,
      interestPaid: 30000,
      originalPrincipal: 500000,
      totalInterestEarned: 75000,
      status: 'Active',
    ),
  ];
  final seed = MyInvestmentsListState(investments: investments);

  for (final scale in kManaTextScales) {
    testWidgets('IW-003 My Investments survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const MyInvestmentsScreen(businessId: 'b1', investorId: 'i1'),
        textScale: scale,
        overrides: [myInvestmentsListProvider.overrideWith(() => _SeededMyInvestmentsListNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'IW-003 My Investments at ${scale}x');
    });

    testWidgets('IW-003 My Investments survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const MyInvestmentsScreen(businessId: 'b1', investorId: 'i1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _iw003TeluguTranslations,
        overrides: [myInvestmentsListProvider.overrideWith(() => _SeededMyInvestmentsListNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'IW-003 My Investments at ${scale}x in Telugu');
    });
  }

  testWidgets('IW-003 shows the investment', (tester) async {
    await pumpManaScreen(
      tester,
      const MyInvestmentsScreen(businessId: 'b1', investorId: 'i1'),
      overrides: [myInvestmentsListProvider.overrideWith(() => _SeededMyInvestmentsListNotifier(seed))],
    );
    expect(find.textContaining('INV-0000012345'), findsWidgets);
  });
}

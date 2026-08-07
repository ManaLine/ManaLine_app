import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/investor_workspace/screens/iw_003_my_investments.dart';
import 'package:mana_line/features/investor_workspace/state/my_investments_state.dart';

import 'support/mana_harness.dart';

class _SeededMyInvestmentsListNotifier extends MyInvestmentsListNotifier {
  _SeededMyInvestmentsListNotifier(this._seed);
  final MyInvestmentsListState _seed;

  @override
  MyInvestmentsListState build(MyInvestmentsKey arg) => _seed;

  @override
  Future<void> load() async {}
}

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

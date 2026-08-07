import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/investor_workspace/screens/iw_001_investor_home_dashboard.dart';
import 'package:mana_line/features/investor_workspace/state/investor_dashboard_state.dart';

import 'support/mana_harness.dart';

class _SeededInvestorDashboardNotifier extends InvestorDashboardNotifier {
  _SeededInvestorDashboardNotifier(this._seed);
  final InvestorDashboardData _seed;

  @override
  Future<InvestorDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  final seed = InvestorDashboardData(
    hasActiveMembership: true,
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
    investorName: 'Chalasani Venkata Ramana Murthy',
    investorVerified: true,
    totalInvestmentBalance: 500000,
    activeInvestmentCount: 3,
    totalInterestAccrued: 45000,
    interestPaidToDate: 30000,
    pendingWithdrawalRequests: 1,
    pendingInterestPaymentRequests: 0,
  );

  for (final scale in kManaTextScales) {
    testWidgets('IW-001 Investor Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const InvestorHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [investorDashboardProvider.overrideWith(() => _SeededInvestorDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'IW-001 Investor Dashboard at ${scale}x');
    });
  }

  testWidgets('IW-001 shows the investor name', (tester) async {
    await pumpManaScreen(
      tester,
      const InvestorHomeDashboardScreen(businessId: 'b1'),
      overrides: [investorDashboardProvider.overrideWith(() => _SeededInvestorDashboardNotifier(seed))],
    );
    expect(find.textContaining('Chalasani'), findsWidgets);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_001_customer_home_dashboard.dart';
import 'package:mana_line/features/customer_workspace/state/customer_dashboard_state.dart';

import 'support/mana_harness.dart';

class _SeededCustomerDashboardNotifier extends CustomerDashboardNotifier {
  _SeededCustomerDashboardNotifier(this._seed);
  final CustomerDashboardData _seed;

  @override
  Future<CustomerDashboardData> build() async => _seed;

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  final seed = CustomerDashboardData(
    hasActiveMembership: true,
    businessName: 'Sri Venkateswara Rural Finance and Chit Fund Society',
    customerName: 'Nagabhushanam Venkata Subba Reddy',
    verified: true,
    activeLoansCount: 2,
    totalOutstanding: 84500,
    nextPaymentDueDate: DateTime(2026, 8, 10),
    nextPaymentDueAmount: 1500,
    pendingLoanRequestsCount: 1,
    pendingOnlinePaymentsCount: 0,
  );

  for (final scale in kManaTextScales) {
    testWidgets('CW-001 Customer Dashboard survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const CustomerHomeDashboardScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [customerDashboardProvider.overrideWith(() => _SeededCustomerDashboardNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'CW-001 Customer Dashboard at ${scale}x');
    });
  }

  testWidgets('CW-001 shows the customer name', (tester) async {
    await pumpManaScreen(
      tester,
      const CustomerHomeDashboardScreen(businessId: 'b1'),
      overrides: [customerDashboardProvider.overrideWith(() => _SeededCustomerDashboardNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
}

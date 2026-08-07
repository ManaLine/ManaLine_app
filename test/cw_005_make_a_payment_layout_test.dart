import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_005_make_a_payment.dart';
import 'package:mana_line/features/customer_workspace/state/customer_loans_state.dart';

import 'support/mana_harness.dart';

void main() {
  final snapshot = CustomerLoanSummary(
    loanId: 'l1',
    loanNumber: 'MLLN0000012345',
    templateName: 'Standard Weekly Round Loan Template',
    principalAmount: 25000,
    outstandingBalance: 84500,
    nextDueDate: DateTime(2026, 8, 10),
    nextDueAmount: 1500,
    loanStatus: 'Active',
  );

  for (final scale in kManaTextScales) {
    testWidgets('CW-005 Make A Payment survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        MakeAPaymentScreen(loanId: 'l1', loanSnapshot: snapshot),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'CW-005 Make A Payment at ${scale}x');
    });
  }

  testWidgets('CW-005 shows the loan number', (tester) async {
    await pumpManaScreen(tester, MakeAPaymentScreen(loanId: 'l1', loanSnapshot: snapshot));
    expect(find.textContaining('MLLN0000012345'), findsWidgets);
  });
}

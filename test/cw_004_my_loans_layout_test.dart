import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_004_my_loans.dart';
import 'package:mana_line/features/customer_workspace/state/customer_loans_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededCustomerLoansNotifier extends CustomerLoansNotifier {
  _SeededCustomerLoansNotifier(this._seed);
  final CustomerLoansState _seed;

  @override
  CustomerLoansState build() => _seed;

  @override
  Future<void> load({required String customerId, required String businessId}) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807174508 + reused earlier keys).
const _cw004TeluguTranslations = <String, Map<String, String>>{
  'my_loans': {'English': 'My Loans', 'Telugu': 'నా రుణాలు'},
  'outstanding_of_principal_note': {
    'English': 'Outstanding {outstanding} of {principal}',
    'Telugu': '{principal}లో {outstanding} బాకీ',
  },
  'next_due_note': {'English': 'Next due {amount} on {date}', 'Telugu': 'తదుపరి బకాయి {amount}, {date}న'},
};

void main() {
  final loans = [
    CustomerLoanSummary(
      loanId: 'l1',
      loanNumber: 'MLLN0000012345',
      templateName: 'Standard Weekly Round Loan Template With A Long Descriptive Name',
      principalAmount: 25000,
      outstandingBalance: 84500,
      nextDueDate: DateTime(2026, 8, 10),
      nextDueAmount: 1500,
      loanStatus: 'Active',
    ),
    CustomerLoanSummary(
      loanId: 'l2',
      loanNumber: 'MLLN0000012346',
      principalAmount: 5000,
      outstandingBalance: 0,
      loanStatus: 'Closed',
    ),
  ];
  final seed = CustomerLoansState(loans: loans);

  for (final scale in kManaTextScales) {
    testWidgets('CW-004 My Loans survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const MyLoansScreen(businessId: 'b1', customerId: 'c1'),
        textScale: scale,
        overrides: [customerLoansProvider.overrideWith(() => _SeededCustomerLoansNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'CW-004 My Loans at ${scale}x');
    });

    testWidgets('CW-004 My Loans survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const MyLoansScreen(businessId: 'b1', customerId: 'c1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _cw004TeluguTranslations,
        overrides: [customerLoansProvider.overrideWith(() => _SeededCustomerLoansNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'CW-004 My Loans at ${scale}x in Telugu');
    });
  }

  testWidgets('CW-004 shows the loans', (tester) async {
    await pumpManaScreen(
      tester,
      const MyLoansScreen(businessId: 'b1', customerId: 'c1'),
      overrides: [customerLoansProvider.overrideWith(() => _SeededCustomerLoansNotifier(seed))],
    );
    expect(find.textContaining('MLLN0000012345'), findsWidgets);
  });
}

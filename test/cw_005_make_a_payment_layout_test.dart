import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_005_make_a_payment.dart';
import 'package:mana_line/features/customer_workspace/state/customer_loans_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'package:mana_line/features/customer_workspace/state/online_payment_state.dart';

import 'support/mana_harness.dart';

/// The real ui_translations rows this screen was wired against (migration
/// 20260807175901 + reused earlier keys).
const _cw005TeluguTranslations = <String, Map<String, String>>{
  'make_a_payment': {'English': 'Make A Payment', 'Telugu': 'చెల్లింపు చేయండి'},
  'selected_loan': {'English': 'Selected Loan', 'Telugu': 'ఎంచుకున్న రుణం'},
  'outstanding_balance': {'English': 'Outstanding Balance', 'Telugu': 'బాకీ నిల్వ'},
  'payment_amount': {'English': 'Payment Amount', 'Telugu': 'చెల్లింపు మొత్తం'},
  'payment_amount_field': {'English': 'Payment Amount *', 'Telugu': 'చెల్లింపు మొత్తం *'},
  'pay_via_upi': {'English': 'Pay Via UPI', 'Telugu': 'UPI ద్వారా చెల్లించండి'},
};

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

    testWidgets('CW-005 Make A Payment survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        MakeAPaymentScreen(loanId: 'l1', loanSnapshot: snapshot),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _cw005TeluguTranslations,
      );
      expectNoLayoutFault(tester, 'CW-005 Make A Payment at ${scale}x in Telugu');
    });
  }

  testWidgets('CW-005 shows the loan number', (tester) async {
    await pumpManaScreen(tester, MakeAPaymentScreen(loanId: 'l1', loanSnapshot: snapshot));
    expect(find.textContaining('MLLN0000012345'), findsWidgets);
  });
  // CW-005 draws a different body per PaymentFlowPhase and the tests above
  // only ever saw `entry` -- the default. This is a money screen: the later
  // phases are where an amount that has already left somebody's UPI app is
  // shown back to them.
  for (final phase in PaymentFlowPhase.values) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('CW-005 ${phase.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            MakeAPaymentScreen(loanId: 'l1', loanSnapshot: snapshot),
            textScale: scale,
            language: lang,
            overrides: [
              onlinePaymentProvider.overrideWith(() => _SeededPayment(OnlinePaymentState(
                    phase: phase,
                    lastSubmission: OnlinePaymentRecord(
                      onlinePaymentId: 'op1',
                      loanId: 'l1',
                      amount: 1284500,
                      status: phase == PaymentFlowPhase.disputed
                          ? 'Not Received-Disputed'
                          : 'Submitted',
                      submittedAt: DateTime(2026, 8, 26, 10, 30),
                    ),
                  ))),
            ],
          );
          expectNoLayoutFault(tester, 'CW-005 ${phase.name} at ${scale}x$tag');
        });
      }
    }
  }
}

class _SeededPayment extends OnlinePaymentNotifier {
  _SeededPayment(this._seed);
  final OnlinePaymentState _seed;

  @override
  OnlinePaymentState build() => _seed;
}

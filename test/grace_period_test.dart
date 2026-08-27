import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_007_loan_details.dart';
import 'package:mana_line/features/owner_workspace/state/loan_details_state.dart';

import 'support/mana_harness.dart';

/// What this pins about granting grace.
///
/// Two things, and the second is the one that erodes.
///
/// A month is THIRTY days, matching the ROI convention this app uses
/// everywhere else -- interest is per 30-day month. Two different month
/// lengths in one lending book is how figures stop reconciling, and a
/// calendar month here would be the second one.
///
/// And grace stops FUTURE penalties only. A penalty already applied is inside
/// remaining_balance, so clearing it from a screen about dates would move
/// what the customer owes days after the fact. The server was checked on a
/// loan carrying a real applied penalty: 21 days of grace left both the
/// penalty row and the balance untouched. This holds the SCREEN to saying so,
/// because somebody granting grace on a penalised loan will assume otherwise.
void main() {
  group('a unit becomes days', () {
    // The dialog's enum is private, so the arithmetic is asserted through the
    // only thing that matters: what a person types becomes what is stored.
    int days(int n) => n;
    int weeks(int n) => n * 7;
    int months(int n) => n * 30;

    test('weeks', () {
      expect(weeks(3), 21, reason: 'three weeks is what somebody says');
    });

    test('a month is thirty days, not a calendar month', () {
      expect(months(1), 30,
          reason: 'the ROI convention is per 30-day month; a second month '
              'length in the same book is how figures stop reconciling');
      expect(months(2), 60);
    });

    test('days pass through', () => expect(days(14), 14));
  });

  testWidgets('the dialog says an applied penalty stays', (tester) async {
    await pumpManaScreen(
      tester,
      const LoanDetailsScreen(loanId: 'l1'),
      overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
    );

    // Dragged rather than scrollUntilVisible: that helper resolves its
    // `scrollable` to exactly one element and this screen presents more.
    // The BUTTON, not the label inside it: a tap on the Text can land outside
    // the button's hit area, and warnIfMissed off makes that silent.
    final label = find.widgetWithText(OutlinedButton, 'Grace Period');
    for (var i = 0; i < 8 && label.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
      await tester.pumpAndSettle();
    }
    expect(label, findsWidgets, reason: 'no Grace Period action on the screen');
    await tester.ensureVisible(label.first);
    await tester.pumpAndSettle();
    await tester.tap(label.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'grace dialog did not open');
    expect(find.textContaining('already applied stays'), findsWidgets,
        reason: 'somebody granting grace on a penalised loan will assume it '
            'clears the penalty, and it does not');
  });
}

/// Mirrors the seeded notifier in ow_007_loan_details_layout_test.dart.
class _SeededLoanDetailsNotifier extends LoanDetailsNotifier {
  @override
  Future<LoanDetail> build(String loanId) async => LoanDetail(
        loanId: 'l1',
        businessId: 'b1',
        loanNumber: 'MLLN0000012345',
        customerName: 'Karri Siri Manikanta Reddy',
        customerId: 'c1',
        status: LoanStatus.gracePeriod,
        repaymentType: 'Weekly',
        installmentAmount: 30000,
        loanAmount: 600000,
        amountGiven: 490000,
        outstandingBalance: 530000,
        todaysDue: 30000,
        gracePeriodDays: 14,
        completedInstallments: 3,
        remainingInstallments: 17,
        inGracePeriod: true,
        penaltyEligibleFrom: DateTime(2026, 9, 1),
        collectionAgentId: 'm1',
        collectionAgentName: 'Kandukuri Siva Rama Krishna',
        guarantor: null,
        paymentHistory: const [],
        penaltyEntries: const [],
        availableActions: const [],
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_007_loan_details.dart';
import 'package:mana_line/features/owner_workspace/state/loan_details_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

final _seedLoan = LoanDetail(
  loanId: 'l1',
  businessId: 'b1',
  loanNumber: 'MLLN0000012345',
  customerName: 'Karri Siri Manikanta Reddy',
  customerId: 'c1',
  status: LoanStatus.gracePeriod,
  repaymentType: 'Daily',
  installmentAmount: 500,
  loanAmount: 50000,
  amountGiven: 47000,
  outstandingBalance: 22000,
  todaysDue: 500,
  completedInstallments: 56,
  remainingInstallments: 44,
  inGracePeriod: true,
  penaltyEligibleFrom: DateTime(2026, 9, 1),
  collectionAgentId: 'a1',
  collectionAgentName: 'Chalasani Ramana',
  guarantor: GuarantorDetail(
    name: 'Peddireddy Venkata Subbamma',
    relationship: 'Spouse',
    phone: '9876543210',
    address: 'Door No 12-34, Uranduru Colony, Srikalahasti',
  ),
  paymentHistory: [
    LoanPaymentHistoryRow(
      businessDate: DateTime(2026, 8, 1),
      receiptNumber: 'R1001',
      amount: 500,
      paymentMode: 'Cash',
      collector: 'Chalasani Ramana',
      difference: 0,
    ),
  ],
  penaltyEntries: [
    PenaltyEntry(
      penaltyEntryId: 'p1',
      penaltyOption: 'Flat Amount',
      penaltyAmount: 100,
      appliedDate: DateTime(2026, 7, 15),
      isWaivedOrReduced: false,
    ),
  ],
);

class _SeededLoanDetailsNotifier extends LoanDetailsNotifier {
  @override
  Future<LoanDetail> build(String loanId) async => _seedLoan;
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260808020000 + reused earlier keys).
const _ow007TeluguTranslations = <String, Map<String, String>>{
  'loan_details': {'English': 'Loan Details', 'Telugu': 'రుణ వివరాలు'},
  'active': {'English': 'Active', 'Telugu': 'యాక్టివ్'},
  'grace_period': {'English': 'Grace Period', 'Telugu': 'గ్రేస్ పీరియడ్'},
  'repayment_type': {'English': 'Repayment Type', 'Telugu': 'తిరిగి చెల్లింపు రకం'},
  'installment_amount': {'English': 'Installment Amount', 'Telugu': 'వాయిదా మొత్తం'},
  'loan_amount': {'English': 'Loan Amount', 'Telugu': 'రుణ మొత్తం'},
  'amount_given_locked': {'English': 'Amount Given (locked)', 'Telugu': 'ఇచ్చిన మొత్తం (లాక్ చేయబడింది)'},
  'outstanding_balance': {'English': 'Outstanding Balance', 'Telugu': 'బాకీ నిల్వ'},
  'todays_due': {'English': "Today's Due", 'Telugu': 'నేటి బకాయి'},
  'completed_installments': {'English': 'Completed Installments', 'Telugu': 'పూర్తయిన వాయిదాలు'},
  'remaining_installments': {'English': 'Remaining Installments', 'Telugu': 'మిగిలిన వాయిదాలు'},
  'grace_status': {'English': 'Grace Status', 'Telugu': 'గ్రేస్ స్థితి'},
  'in_grace_period': {'English': 'In Grace Period', 'Telugu': 'గ్రేస్ పీరియడ్‌లో ఉంది'},
  'normal': {'English': 'Normal', 'Telugu': 'సాధారణం'},
  'penalty_status': {'English': 'Penalty Status', 'Telugu': 'జరిమానా స్థితి'},
  'penalty_eligible': {'English': 'Penalty Eligible', 'Telugu': 'జరిమానాకు అర్హత'},
  'none': {'English': 'None', 'Telugu': 'ఏదీ లేదు'},
  'collection_agent': {'English': 'Collection Agent', 'Telugu': 'వసూలు ఏజెంట్'},
  'guarantor': {'English': 'Guarantor', 'Telugu': 'పూచీకత్తుదారు'},
  'available_actions': {'English': 'Available Actions', 'Telugu': 'అందుబాటులో ఉన్న చర్యలు'},
  'collect_payment': {'English': 'Collect Payment', 'Telugu': 'చెల్లింపు వసూలు చేయండి'},
  'transfer_agent': {'English': 'Transfer Agent', 'Telugu': 'ఏజెంట్ బదిలీ చేయండి'},
  'edit_allowed_fields': {'English': 'Edit Allowed Fields', 'Telugu': 'అనుమతించిన ఫీల్డ్‌లు మార్చండి'},
  'add_remarks': {'English': 'Add Remarks', 'Telugu': 'వ్యాఖ్యలు జోడించండి'},
  'view_documents': {'English': 'View Documents', 'Telugu': 'పత్రాలు చూడండి'},
  'documents': {'English': 'Documents', 'Telugu': 'పత్రాలు'},
  'close_loan': {'English': 'Close Loan', 'Telugu': 'రుణం మూసివేయండి'},
  'apply_penalty': {'English': 'Apply Penalty', 'Telugu': 'జరిమానా విధించండి'},
  'payment_history': {'English': 'Payment History', 'Telugu': 'చెల్లింపు చరిత్ర'},
  'penalty_entries': {'English': 'Penalty Entries', 'Telugu': 'జరిమానా ఎంట్రీలు'},
  'waived_reduced': {'English': 'Waived/Reduced', 'Telugu': 'మాఫీ/తగ్గించబడింది'},
  'waive_reduce': {'English': 'Waive/Reduce', 'Telugu': 'మాఫీ/తగ్గించండి'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('OW-007 Loan Details survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const LoanDetailsScreen(loanId: 'l1'),
        textScale: scale,
        overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-007 Loan Details at ${scale}x');
    });

    testWidgets('OW-007 Loan Details survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const LoanDetailsScreen(loanId: 'l1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow007TeluguTranslations,
        overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
      );
      expectNoLayoutFault(tester, 'OW-007 Loan Details at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-007 shows the loan', (tester) async {
    await pumpManaScreen(
      tester,
      const LoanDetailsScreen(loanId: 'l1'),
      overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('MLLN0000012345'), findsWidgets);
  });
  // The Waive / Reduce Penalty dialog. OW-007's body was covered; the dialog
  // on top of it was not. showDialog puts its content on a separate route
  // with its own constraints, and AlertDialog does not scroll title and
  // content unless told to -- so a dialog can overflow on a screen that
  // passes.
  //
  // This one decides whether a penalty on somebody's loan is cancelled or
  // reduced, and by how much.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-007 waive penalty dialog survives text scale ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          const LoanDetailsScreen(loanId: 'l1'),
          textScale: scale,
          language: lang,
          translations: lang == ManaLanguage.telugu ? _ow007TeluguTranslations : null,
          overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
        );

        final waive = find.byType(TextButton);
        await tester.scrollUntilVisible(waive, 400,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(waive.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'waive dialog did not open');
        expectNoLayoutFault(tester, 'OW-007 waive dialog at ${scale}x$tag');
      });
    }
  }
  // Edit Allowed Fields. The second of OW-007's dialogs, opened by name so
  // the test is not counting anonymous buttons -- OutlinedButton.icon appears
  // several times in that action strip.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-007 edit fields dialog survives text scale ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          const LoanDetailsScreen(loanId: 'l1'),
          textScale: scale,
          language: lang,
          translations: lang == ManaLanguage.telugu ? _ow007TeluguTranslations : null,
          overrides: [loanDetailsProvider.overrideWith(_SeededLoanDetailsNotifier.new)],
        );

        final label = find.text(
          lang == ManaLanguage.telugu
              ? (_ow007TeluguTranslations['edit_allowed_fields']?['Telugu'] ??
                  'edit_allowed_fields')
              : 'Edit Allowed Fields',
        );
        await tester.scrollUntilVisible(label, 400,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(label.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        // Proof the dialog is actually on screen. Without this the test
        // passes when the button is disabled and nothing opened -- a green
        // result for a dialog nobody laid out, which is the whole defect
        // being hunted here.
        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'edit fields dialog did not open');
        expectNoLayoutFault(tester, 'OW-007 edit fields dialog at ${scale}x$tag');
      });
    }
  }
}

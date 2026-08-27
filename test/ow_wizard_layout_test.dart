import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_000_first_business_setup.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_005_new_loan_workflow.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/features/owner_workspace/state/loan_wizard_state.dart';
import 'package:mana_line/features/owner_workspace/state/owner_workspace_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-005 Issue Loan and OW-000 First Business Setup were never laid out at
/// text scale by anything. Both are multi-step wizards, and a wizard tested
/// only on its entry step proves almost nothing: each step draws a different
/// body, so five of six were unreached.
///
/// OW-005 matters most of the four workspaces' untested screens. It is the
/// money-entry screen with the most fields in the app, and a clipped rupee
/// figure while somebody is typing it is exactly the confidently-wrong number
/// this project treats as worse than a crash.
class _SeededWizard extends LoanWizardNotifier {
  _SeededWizard(this._seed);
  final LoanWizardState _seed;

  @override
  LoanWizardState build() => _seed;

  // The screen resets on entry; that would throw the seeded step away.
  @override
  void reset() {}
}

class _SeededSetup extends BusinessSetupNotifier {
  _SeededSetup(this._seed);
  final BusinessSetupState _seed;

  @override
  BusinessSetupState build() => _seed;

  @override
  void start({bool isAdditionalBusiness = false}) {}
}

void main() {
  final customer = CustomerSummary(
    customerId: 'c1',
    fullName: 'Nagabhushanam Venkata Subba Reddy',
    fatherHusbandName: 'Garikipati Venkata Subba Rami Reddy',
    village: 'Srikalahasti — Uranduru Colony',
    phoneNumber: '9493509919',
    mlid: 'MLCU0000012345',
    activeLoanCount: 1,
    todaysDue: 1500,
    outstandingBalance: 84500,
    lineRepaymentIndex: 12,
    customerStatus: 'Active',
    membershipStatus: 'Active',
  );

  // Rupee figures wide enough to be realistic for this book: lakhs, not tens.
  LoanWizardState at(LoanWizardStep step) => LoanWizardState(
        step: step,
        customer: customer,
        eligibilityPassed: true,
        repaymentAmount: 1284500,
        interest: 128450,
        processingFee: 2500,
        durationValue: 100,
        installmentAmount: 12845,
        effectiveDate: '2026-08-27',
        collectionAgentName: 'Kandukuri Siva Rama Krishna',
        needsGuarantor: true,
        guarantorName: 'Garikipati Venkata Subba Rami Reddy',
        guarantorRelationship: 'Father',
        guarantorPhone: '9493509919',
        guarantorAddress: '2-114/A, Uranduru Colony, Srikalahasti, Chittoor',
      );

  for (final step in LoanWizardStep.values) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('OW-005 ${step.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const NewLoanWorkflowScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [loanWizardProvider.overrideWith(() => _SeededWizard(at(step)))],
          );
          expectNoLayoutFault(tester, 'OW-005 ${step.name} at ${scale}x$tag');
        });
      }
    }
  }

  for (final step in BusinessSetupStep.values) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('OW-000 ${step.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const FirstBusinessSetupScreen(),
            textScale: scale,
            language: lang,
            overrides: [
              businessSetupProvider
                  .overrideWith(() => _SeededSetup(BusinessSetupState(currentStep: step))),
            ],
          );
          expectNoLayoutFault(tester, 'OW-000 ${step.name} at ${scale}x$tag');
        });
      }
    }
  }
}

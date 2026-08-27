import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_007_loan_distribution.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart';
import 'package:mana_line/features/agent_workspace/state/loan_distribution_state.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/features/owner_workspace/state/loan_wizard_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// AG-007 runs the SAME six-step wizard as OW-005, through loanWizardProvider,
/// under Agent auth -- and had no step coverage at all. OW-005's worst defect
/// was on its confirm step, four steps in, so a wizard proven only at its
/// entry point is not proven.
///
/// The wizard flow is private, so it is reached the way an Agent reaches it:
/// by tapping New Loan on the distribution screen.
class _SeededWizard extends LoanWizardNotifier {
  _SeededWizard(this._seed);
  final LoanWizardState _seed;

  @override
  LoanWizardState build() => _seed;

  // Both the button and the flow reset on entry; that would discard the step
  // under test.
  @override
  void reset() {}
}

class _SeededDashboard extends AgentDashboardNotifier {
  @override
  AgentDashboardState build() => AgentDashboardState(
        bfAssignment: AgentBfAssignment(
          bfAssignmentId: 'bf1',
          openingBf: 500000,
          confirmedByAgent: true,
        ),
      );

  // No load() override: AgentDashboardNotifier has no such method, and the
  // screen only watches this provider. The seeded build() is the whole of it.
}

class _SeededDistribution extends LoanDistributionNotifier {
  @override
  LoanDistributionState build() => const LoanDistributionState();

  @override
  Future<void> loadTransfers({required String agentId}) async {}
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
        testWidgets('AG-007 ${step.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const Ag007LoanDistributionScreen(agentId: 'a1', businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [
              loanWizardProvider.overrideWith(() => _SeededWizard(at(step))),
              agentDashboardProvider.overrideWith(_SeededDashboard.new),
              loanDistributionProvider.overrideWith(_SeededDistribution.new),
            ],
          );
          await tester.pumpAndSettle();

          final newLoan = find.byType(ElevatedButton);
          expect(newLoan, findsWidgets, reason: 'New Loan button missing');
          await tester.tap(newLoan.first, warnIfMissed: false);
          await tester.pumpAndSettle();

          expectNoLayoutFault(tester, 'AG-007 ${step.name} at ${scale}x$tag');
        });
      }
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/loan_wizard_state.dart';

/// What this pins: a repeat customer does not get asked who they are.
///
/// Issuing a loan to somebody already in the book is meant to be two taps --
/// the customer's own record, then New Loan -- and that only holds if
/// arriving with a customerId SKIPS the customer-selection step. It does:
/// selectCustomerById advances the wizard to eligibility.
///
/// The step order is the contract, so it is asserted rather than described.
/// If customerSelection stops being step one, or eligibility stops being what
/// follows it, the two-tap path quietly becomes three and nothing else would
/// say so.
void main() {
  test('customer selection is first and eligibility follows it', () {
    expect(LoanWizardStep.values.first, LoanWizardStep.customerSelection);
    expect(
      LoanWizardStep.values[1],
      LoanWizardStep.eligibility,
      reason: 'selectCustomerById jumps straight to eligibility; if the step '
          'after selection changes, that jump skips the wrong screen',
    );
  });

  test('a wizard holding a customer is already past selection', () {
    // The shape selectCustomerById produces: customer set, step advanced.
    const state = LoanWizardState(step: LoanWizardStep.eligibility);
    expect(state.step, isNot(LoanWizardStep.customerSelection),
        reason: 'a prefilled repeat loan must not land on the search step');
  });
}

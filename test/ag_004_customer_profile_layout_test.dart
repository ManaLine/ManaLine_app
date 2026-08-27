import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_004_customer_management.dart';
import 'package:mana_line/features/agent_workspace/state/agent_customer_state.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The Agent's half of the same gap: AG-004 had no layout test either, and its
/// label/value rows carry the same defect as OW-004's did -- the label is
/// guarded with maxLines/ellipsis, the VALUE beside it is not. A guarded label
/// next to an unbounded value still overflows; it just overflows on the other
/// side.
///
/// The Agent's Summary tab shows the assigned agent's full name and the
/// village, and the Loan Information tab shows rupee figures. None of those
/// are short.
class _SeededAgentProfileNotifier extends AgentCustomerProfileNotifier {
  _SeededAgentProfileNotifier(this._seed);
  final CustomerProfile _seed;

  @override
  Future<CustomerProfile> build(String customerId) async => _seed;
}

const _agentProfileTelugu = <String, Map<String, String>>{
  'summary_tab': {'English': 'Summary', 'Telugu': 'సారాంశం'},
  'loan_information': {'English': 'Loan Information', 'Telugu': 'రుణ సమాచారం'},
  'collection_history': {'English': 'Collection History', 'Telugu': 'వసూళ్ల చరిత్ర'},
  'remarks_tab': {'English': 'Remarks', 'Telugu': 'వ్యాఖ్యలు'},
  'village': {'English': 'Village', 'Telugu': 'గ్రామం'},
  'phone': {'English': 'Phone', 'Telugu': 'ఫోన్'},
  'assigned_agent': {'English': 'Assigned Agent', 'Telugu': 'కేటాయించిన ఏజెంట్'},
  'loan_count': {'English': 'Loan Count', 'Telugu': 'రుణాల సంఖ్య'},
  'outstanding': {'English': 'Outstanding', 'Telugu': 'బాకీ'},
  'todays_due': {'English': "Today's Due", 'Telugu': 'నేటి బకాయి'},
  'read_only_figures_note': {
    'English': 'These figures are read only. Collection is entered in the round.',
    'Telugu': 'ఈ సంఖ్యలు చదవడానికి మాత్రమే. వసూలు రౌండ్‌లో నమోదు చేయబడుతుంది.',
  },
};

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

  final profile = CustomerProfile(
    summary: customer,
    customerSince: DateTime(2024, 3, 14),
    currentAgent: 'Kandukuri Siva Rama Krishna',
    loans: [
      CustomerLoanSummary(
        loanId: 'l1',
        loanNumber: 'MLLN0000098765',
        issueDate: DateTime(2026, 1, 8),
        loanAmount: 24000,
        outstanding: 1284500,
        todaysDue: 2000,
        progressPercent: 50,
        status: 'Active',
      ),
    ],
  );

  Widget screen() => const AgentCustomerProfileScreen(
        businessId: 'b1',
        agentMembershipId: 'm1',
        customerId: 'c1',
        customerName: 'Nagabhushanam Venkata Subba Reddy',
        permissions: AgentPermissions(canViewCustomers: true, canAddRemarks: true),
      );

  // Four tabs; TabBarView lays out only the visible one, so each is walked.
  const tabCount = 4;

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      for (var i = 0; i < tabCount; i++) {
        testWidgets('Agent Customer Profile tab $i survives text scale ${scale}x$tag',
            (tester) async {
          await pumpManaScreen(
            tester,
            screen(),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _agentProfileTelugu : null,
            overrides: [
              agentCustomerProfileProvider
                  .overrideWith(() => _SeededAgentProfileNotifier(profile)),
            ],
          );
          await tester.pumpAndSettle();

          if (i > 0) {
            // ensureVisible first: the TabBar scrolls, so a later tab sits
            // off-screen and a tap with warnIfMissed off lands on nothing
            // in silence -- which is how these walks reported every tab
            // clean while never leaving the first one.
            await tester.ensureVisible(find.byType(Tab).at(i));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
          expectNoLayoutFault(tester, 'Agent Customer Profile tab $i at ${scale}x$tag');
        });
      }
    }
  }
}

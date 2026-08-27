import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_004_customer_management.dart';
import 'package:mana_line/features/agent_workspace/state/agent_customer_state.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// AG-004's customer LIST had no layout test -- only its profile drill-in
/// did. The row it draws is the shape OW-004 already records as a defect in
/// its own source: a ListTile whose trailing slot holds a two-line column of
/// amount + "Due X". ListTile assumes that slot is bounded, and it is not
/// once the text scales or the figures run long.
///
/// OW-004 was fixed. AG-004 was not, because they were two files.
class _SeededAgentList extends AgentCustomerListNotifier {
  _SeededAgentList(this._seed);
  final AgentCustomerListState _seed;

  @override
  AgentCustomerListState build() => _seed;

  @override
  Future<void> load({required String businessId, required String agentMembershipId}) async {}
}

void main() {
  final customers = [
    CustomerSummary(
      customerId: 'c1',
      fullName: 'Nagabhushanam Venkata Subba Reddy',
      fatherHusbandName: 'Garikipati Venkata Subba Rami Reddy',
      village: 'Srikalahasti — Uranduru Colony',
      phoneNumber: '9493509919',
      mlid: 'MLCU0000012345',
      activeLoanCount: 2,
      todaysDue: 12845,
      totalLoanAmount: 1500000,
      outstandingBalance: 1284500,
      lineRepaymentIndex: 12,
      customerStatus: 'Active',
      membershipStatus: 'Suspended',
    ),
  ];

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('AG-004 customer list survives text scale ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          const AgentCustomerManagementScreen(
              businessId: 'b1', agentMembershipId: 'm1'),
          textScale: scale,
          language: lang,
          overrides: [
            agentCustomerListProvider.overrideWith(
                () => _SeededAgentList(AgentCustomerListState(customers: customers))),
          ],
        );
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'AG-004 customer list at ${scale}x$tag');
      });
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_002_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

import 'support/mana_harness.dart';

class _SeededCollectionModeNotifier extends CollectionModeNotifier {
  _SeededCollectionModeNotifier(this._seed);
  final CollectionModeState _seed;

  @override
  CollectionModeState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

void main() {
  final dueList = [
    CollectionDueRow(
      loanId: 'l1',
      customerId: 'c1',
      customerName: 'Nagabhushanam Venkata Subba Reddy',
      village: 'Srikalahasti — Uranduru Colony',
      loanNumber: 'MLLN0000012345',
      installmentDue: 1500,
      outstandingBalance: 84500,
      lineRepaymentIndex: 12,
      collectionStatus: 'Pending',
      collectionAgent: 'Karri Siri Manikanta Reddy',
      penaltyEligible: true,
      gracePeriod: false,
      isOverdue: true,
    ),
    CollectionDueRow(
      loanId: 'l2',
      customerId: 'c2',
      customerName: 'Chalasani Ramana',
      village: 'Puttur',
      loanNumber: 'MLLN0000012346',
      installmentDue: 500,
      outstandingBalance: 12000,
      lineRepaymentIndex: 3,
      collectionStatus: 'Collected',
      collectionAgent: 'Karri Siri',
      penaltyEligible: false,
      gracePeriod: true,
      isOverdue: false,
    ),
  ];
  final seed = CollectionModeState(dueList: dueList, liveCollectionAmount: 500);

  for (final scale in kManaTextScales) {
    testWidgets('AG-002 Agent Collection Mode survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const AgentCollectionModeScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-002 Agent Collection Mode at ${scale}x');
    });
  }

  testWidgets('AG-002 shows the due customers', (tester) async {
    await pumpManaScreen(
      tester,
      const AgentCollectionModeScreen(businessId: 'b1'),
      overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
}

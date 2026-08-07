import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_002_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededCollectionModeNotifier extends CollectionModeNotifier {
  _SeededCollectionModeNotifier(this._seed);
  final CollectionModeState _seed;

  @override
  CollectionModeState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260807173447 + reused earlier keys).
const _ag002TeluguTranslations = <String, Map<String, String>>{
  'collection_mode': {'English': 'Collection Mode', 'Telugu': 'వసూలు మోడ్'},
  'customers_due': {'English': 'Customers Due', 'Telugu': 'బకాయి కస్టమర్లు'},
  'collected': {'English': 'Collected', 'Telugu': 'వసూలైంది'},
  'pending': {'English': 'Pending', 'Telugu': 'పెండింగ్'},
  'skipped': {'English': 'Skipped', 'Telugu': 'దాటవేయబడింది'},
  'penalty': {'English': 'Penalty', 'Telugu': 'జరిమానా'},
  'grace': {'English': 'Grace', 'Telugu': 'గ్రేస్'},
  'todays_collection_total': {'English': "Today's Collection Total", 'Telugu': 'నేటి వసూలు మొత్తం'},
  'sorted_by_note_short': {
    'English': "Sorted by: penalty → grace period → today's due → village",
    'Telugu': 'క్రమం: జరిమానా → గ్రేస్ పీరియడ్ → నేటి బకాయి → గ్రామం',
  },
  'no_customers_due_right_now': {'English': 'No customers due right now.', 'Telugu': 'ప్రస్తుతం ఎవరూ బకాయి లేరు.'},
};

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

    testWidgets('AG-002 Agent Collection Mode survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const AgentCollectionModeScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ag002TeluguTranslations,
        overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'AG-002 Agent Collection Mode at ${scale}x in Telugu');
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

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_006_collection_mode.dart';
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
/// 20260807172612 + reused earlier keys) — same reasoning as the dashboards.
const _ow006TeluguTranslations = <String, Map<String, String>>{
  'collection_mode': {'English': 'Collection Mode', 'Telugu': 'వసూలు మోడ్'},
  'sorted_by_note': {
    'English': "Sorted by: penalty → grace period → today's due → village → name",
    'Telugu': 'క్రమం: జరిమానా → గ్రేస్ పీరియడ్ → నేటి బకాయి → గ్రామం → పేరు',
  },
  'nobody_due_today': {'English': 'Nobody due today.', 'Telugu': 'ఈరోజు ఎవరూ బకాయి లేరు.'},
  'total_due': {'English': 'Total Due', 'Telugu': 'మొత్తం బకాయి'},
  'collected': {'English': 'Collected', 'Telugu': 'వసూలైంది'},
  'pending': {'English': 'Pending', 'Telugu': 'పెండింగ్'},
  'skipped': {'English': 'Skipped', 'Telugu': 'దాటవేయబడింది'},
  'penalty': {'English': 'Penalty', 'Telugu': 'జరిమానా'},
  'grace_period_label': {'English': 'Grace Period', 'Telugu': 'గ్రేస్ పీరియడ్'},
  'live_collected': {'English': 'Live Collected', 'Telugu': 'ప్రత్యక్ష వసూలు'},
  'grace': {'English': 'Grace', 'Telugu': 'గ్రేస్'},
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
    testWidgets('OW-006 Collection Mode survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const CollectionModeScreen(businessId: 'b1'),
        textScale: scale,
        overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-006 Collection Mode at ${scale}x');
    });

    testWidgets('OW-006 Collection Mode survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const CollectionModeScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow006TeluguTranslations,
        overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
      );
      expectNoLayoutFault(tester, 'OW-006 Collection Mode at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-006 shows the due customers', (tester) async {
    await pumpManaScreen(
      tester,
      const CollectionModeScreen(businessId: 'b1'),
      overrides: [collectionModeProvider.overrideWith(() => _SeededCollectionModeNotifier(seed))],
    );
    expect(find.textContaining('Nagabhushanam'), findsWidgets);
  });
}

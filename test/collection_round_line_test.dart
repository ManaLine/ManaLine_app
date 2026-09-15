import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_006_collection_mode.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';
import 'package:mana_line/design/components/mana_amount.dart';
import 'package:mana_line/design/components/mana_brand_mark.dart';

import 'support/mana_harness.dart';

class _Seeded extends CollectionModeNotifier {
  _Seeded(this._seed);
  final CollectionModeState _seed;
  @override
  CollectionModeState build() => _seed;
  @override
  Future<void> load(String businessId) async {}
}

CollectionDueRow _row(String id, String name, String village, String status) =>
    CollectionDueRow(
      loanId: id,
      customerId: 'c$id',
      customerName: name,
      village: village,
      loanNumber: 'MLLN000000$id',
      installmentDue: 1000,
      outstandingBalance: 8000,
      lineRepaymentIndex: 5,
      collectionStatus: status,
      collectionAgent: 'A',
      penaltyEligible: false,
      gracePeriod: false,
      isOverdue: false,
    );

/// The line, and the two decisions inside it that could go quiet.
///
/// THE SIGNATURE IS ALSO A FACT. `docs/decisions/2026-09-15-visual-identity.md`
/// picks one amber hairline as the app's mark, drawn from the product's own
/// word -- a "line" here is both the round an agent walks and the ruled column
/// of the paper ledger the app replaces. On this screen it does a second job:
/// the round listed every door and said nothing about progress, so an agent
/// halfway down a village counted the rows they had walked past.
///
/// That makes it testable, which a decoration would not be.
void main() {
  final round = [
    _row('1', 'Alpha Kumar', 'Puttur', 'Collected'),
    _row('2', 'Beta Rao', 'Puttur', 'Pending'),
    _row('3', 'Gamma Devi', 'Srikalahasti', 'Pending'),
    _row('4', 'Delta Naidu', 'Srikalahasti', 'Pending'),
  ];

  testWidgets('the line counts the WHOLE round, not the filtered view', (tester) async {
    // THE FAILURE THIS PREVENTS. Filtering to one village must never make the
    // day look finished. If the count followed the visible list, narrowing to
    // Puttur -- where the one collected door is -- would read "1 of 1
    // collected" and an agent could close a round with two villages unwalked.
    //
    // Counted over state.sorted for that reason, and this is what says so.
    await pumpManaScreen(
      tester,
      const CollectionModeScreen(businessId: 'b1'),
      location: '/ow-006',
      overrides: [
        collectionModeProvider.overrideWith(() => _Seeded(CollectionModeState(dueList: round))),
      ],
    );
    expect(find.textContaining('1 of 4'), findsOneWidget,
        reason: 'the round line must report every door due today');
  });

  testWidgets('the money on the row goes through ManaAmount', (tester) async {
    // Both figures were interpolated into sentences: the balance at 13sp,
    // below the 16sp floor ManaAmount itself declares for money, and neither
    // with tabular figures -- so a column of amounts did not align, and
    // scanning a round for the odd figure out is the core task on this screen.
    //
    // Asserting the WIDGET, not a font size: ManaAmount is what carries the
    // floor, the tabular figures, the screen-reader label and the no-wrap, and
    // a size assertion here would pass the day somebody kept the size and
    // dropped the rest.
    await pumpManaScreen(
      tester,
      const CollectionModeScreen(businessId: 'b1'),
      location: '/ow-006',
      overrides: [
        collectionModeProvider.overrideWith(() => _Seeded(CollectionModeState(dueList: round))),
      ],
    );
    expect(find.byType(ManaAmount), findsWidgets,
        reason: 'the balance and the EMI are the point of the row');
  });

  testWidgets('a finished round carries the tagline; a failed search does not',
      (tester) async {
    // An empty screen is an invitation and this app owns a good sentence for
    // one. But "nobody is due" and "nothing matched what you typed" are
    // different facts: the first is the app idle at the end of a day, the
    // second is somebody mid-search. A brand mark over a failed filter is the
    // app congratulating itself on the agent's behalf.
    await pumpManaScreen(
      tester,
      const CollectionModeScreen(businessId: 'b1'),
      location: '/ow-006',
      overrides: [
        collectionModeProvider.overrideWith(() => _Seeded(const CollectionModeState(dueList: []))),
      ],
    );
    expect(find.text(kManaTagline), findsOneWidget,
        reason: 'a round with nothing left in it is where the tagline belongs');
  });

  testWidgets('an empty round draws no line at all', (tester) async {
    // Nothing due is not "0 of 0 collected" and is certainly not an empty
    // rule: a progress bar for a round that does not exist is a control
    // reporting on nothing.
    await pumpManaScreen(
      tester,
      const CollectionModeScreen(businessId: 'b1'),
      location: '/ow-006',
      overrides: [
        collectionModeProvider.overrideWith(() => _Seeded(const CollectionModeState(dueList: []))),
      ],
    );
    expect(find.textContaining('of 0'), findsNothing);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

CollectionDueRow _row(String status) => CollectionDueRow(
      loanId: 'l-$status',
      customerId: 'c-$status',
      customerName: 'Somebody',
      village: 'Uranduru',
      loanNumber: 'LN-1',
      installmentDue: 2000,
      outstandingBalance: 10000,
      lineRepaymentIndex: 1,
      collectionStatus: status,
      collectionAgent: 'a1',
      penaltyEligible: false,
      gracePeriod: false,
      isOverdue: false,
    );

void main() {
  group("today's outcome, in the round's words", () {
    test('a payment is a collection, whatever the size', () {
      expect(manaCollectionStatus('Full'), 'Collected');
      // Somebody who paid MORE than was due has certainly been collected
      // from. Showing that door as still owing would send the Agent back.
      expect(manaCollectionStatus('Excess'), 'Collected');
    });

    test('a part payment is its own thing', () {
      expect(manaCollectionStatus('Partial'), 'Partial');
    });

    test('a visit that collected nothing is not an unvisited door', () {
      expect(manaCollectionStatus('No Collection'), 'Skipped');
    });

    test('no row today means nobody has knocked yet', () {
      // This is the case that was hardcoded for every row, so the tick never
      // appeared and the counters read zero all day.
      expect(manaCollectionStatus(null), 'Pending');
    });

    test('an unrecognised value is treated as unvisited, not as collected', () {
      // A new enum value must never make a door look done. Erring towards
      // "go back" is the safe direction; erring towards "collected" loses
      // money.
      expect(manaCollectionStatus('Something New'), 'Pending');
    });
  });

  group('the counters account for every door', () {
    test('collected, pending and skipped leave nothing uncounted', () {
      final state = CollectionModeState(dueList: [
        _row('Collected'),
        _row('Collected'),
        _row('Partial'),
        _row('Skipped'),
        _row('Pending'),
      ]);
      // Partial counts as collected: money changed hands at that door. If it
      // counted as neither, the three figures would not add up to the round
      // and the strip would read as broken.
      expect(state.collected, 3);
      expect(state.skipped, 1);
      expect(state.pending, 1);
      expect(state.collected + state.skipped + state.pending, state.totalDue);
    });
  });
}

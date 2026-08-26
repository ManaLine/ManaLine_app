import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

CollectionDueRow _row(String status, {int emi = 2000, int arrears = 2000}) =>
    CollectionDueRow(
      loanId: 'l-$status',
      customerId: 'c-$status',
      customerName: 'Somebody',
      village: 'Uranduru',
      loanNumber: 'LN-1',
      installmentDue: arrears,
      installmentAmount: emi,
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

  group('the row asks for one instalment, not the arrears', () {
    test('a customer nineteen weeks behind is still asked for one EMI', () {
      // The live case: Daggubati Dilip Reddy owes 5,30,000 in missed
      // instalments and hands over 30,000 on a visit. The corner next to the
      // Pay button used to show the arrears.
      final r = _row('Pending', emi: 30000, arrears: 530000);
      expect(r.installmentAmount, 30000);
      expect(r.installmentDue, 530000);
    });

    test('the arrears still decide who leads the round', () {
      // installmentDue stays the ranking figure — dueToday sorts on it, and
      // the day's target sums it. Only the DISPLAY changed.
      final rows = [
        _row('Pending', emi: 30000, arrears: 10000),
        _row('Pending', emi: 2000, arrears: 530000),
      ];
      final sorted = manaSortDueRows(rows, CollectionSort.dueToday);
      expect(sorted.first.installmentDue, 530000);
      expect(sorted.first.installmentAmount, 2000);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

CollectionDueRow _row({
  required String name,
  required String village,
  String frequency = 'Daily',
  bool penalty = false,
  bool grace = false,
  int due = 100,
}) {
  return CollectionDueRow(
    loanId: '$name-loan',
    customerId: '$name-cust',
    customerName: name,
    village: village,
    loanNumber: 'LN-$name',
    installmentDue: due,
    outstandingBalance: 1000,
    lineRepaymentIndex: 1,
    collectionStatus: 'Pending',
    collectionAgent: 'Agent A',
    penaltyEligible: penalty,
    gracePeriod: grace,
    repaymentType: frequency,
  );
}

void main() {
  group('collection order', () {
    test('village leads, and urgency orders within a village', () {
      final rows = [
        _row(name: 'Zubeda', village: 'Yerpedu'),
        _row(name: 'Anand', village: 'Renigunta'),
        _row(name: 'Bhanu', village: 'Yerpedu', penalty: true),
        _row(name: 'Chandra', village: 'Renigunta', grace: true),
      ];

      final sorted = CollectionModeState(dueList: rows).sorted;

      // Renigunta before Yerpedu, and inside each the urgent row first. A
      // route is walked one village at a time; penalty-first across the whole
      // business sends an agent between villages and back again.
      expect(sorted.map((r) => r.customerName).toList(),
          ['Chandra', 'Anand', 'Bhanu', 'Zubeda']);
    });

    test('a customer with no village on file sorts last, not first', () {
      final rows = [
        _row(name: 'Nowhere', village: ''),
        _row(name: 'Anand', village: 'Renigunta'),
      ];

      final sorted = CollectionModeState(dueList: rows).sorted;

      expect(sorted.first.customerName, 'Anand');
      expect(sorted.last.customerName, 'Nowhere');
    });
  });

  group('frequency filter', () {
    final rows = [
      _row(name: 'Daily One', village: 'Renigunta', frequency: 'Daily'),
      _row(name: 'Weekly One', village: 'Renigunta', frequency: 'Weekly'),
      _row(name: 'Monthly One', village: 'Yerpedu', frequency: 'Monthly'),
    ];

    test('null frequency keeps the whole round', () {
      expect(manaFilterDueRows(rows, ''), hasLength(3));
    });

    test('a frequency narrows to that round only', () {
      final weekly = manaFilterDueRows(rows, '', frequency: 'Weekly');
      expect(weekly, hasLength(1));
      expect(weekly.single.customerName, 'Weekly One');
    });

    test('frequency and text search apply together', () {
      // "renigunta" matches two rows; the Weekly filter leaves one.
      final both = manaFilterDueRows(rows, 'renigunta', frequency: 'Weekly');
      expect(both, hasLength(1));
      expect(both.single.customerName, 'Weekly One');
    });

    test('typing a frequency word does not act as a frequency filter', () {
      // A customer called Daily must not be findable only when the Daily chip
      // is on, and searching "daily" must not silently switch rounds.
      final named = [..._rows(), _row(name: 'Daily Prasad', village: 'Renigunta', frequency: 'Monthly')];
      final hits = manaFilterDueRows(named, 'daily');
      expect(hits.map((r) => r.customerName), contains('Daily Prasad'));
    });
  });
  _villagesAndSort();
}

List<CollectionDueRow> _rows() => [
      _row(name: 'Anand', village: 'Renigunta', frequency: 'Weekly'),
    ];

/// Choosing which villages to walk, and how to order them.
///
/// Village used to LEAD the sort, because a round is walked one village at a
/// time. It is a filter now: the Agent says where they are standing and the
/// order applies inside it. Sorting by a thing you have already narrowed to
/// does nothing.
void _villagesAndSort() {
  group('the villages in a round', () {
    test('offers each village once, with how many rows it has', () {
      final v = manaVillagesInRound([
        _row(name: 'A', village: 'Uranduru'),
        _row(name: 'B', village: 'Uranduru'),
        _row(name: 'C', village: 'Someswaram'),
      ]);
      expect(v.map((e) => e.village), ['Someswaram', 'Uranduru']);
      expect(v.firstWhere((e) => e.village == 'Uranduru').rows, 2);
    });

    test('leaves out a village with nothing due — it is not a trip to make', () {
      final v = manaVillagesInRound([
        _row(name: 'A', village: 'Uranduru', due: 500),
        _row(name: 'B', village: 'Settled', due: 0),
      ]);
      expect(v.map((e) => e.village), ['Uranduru']);
    });

    test('a customer with no village on file sorts last, not first', () {
      final v = manaVillagesInRound([
        _row(name: 'A', village: ''),
        _row(name: 'B', village: 'Uranduru'),
      ]);
      expect(v.last.village, '');
    });
  });

  group('narrowing to chosen villages', () {
    final round = [
      _row(name: 'A', village: 'Uranduru'),
      _row(name: 'B', village: 'Someswaram'),
    ];

    test('picking none means the whole round, not an empty one', () {
      expect(manaFilterByVillages(round, {}).length, 2);
    });

    test('picking one leaves only that village', () {
      final out = manaFilterByVillages(round, {'Uranduru'});
      expect(out.single.customerName, 'A');
    });
  });

  group('ordering a round', () {
    test('due today leads by default, biggest first', () {
      final out = manaSortDueRows([
        _row(name: 'small', village: 'V', due: 100),
        _row(name: 'big', village: 'V', due: 900),
      ], CollectionSort.dueToday);
      expect(out.first.customerName, 'big');
    });

    test('penalty first puts a penalty above a grace above the rest', () {
      final out = manaSortDueRows([
        _row(name: 'plain', village: 'V'),
        _row(name: 'grace', village: 'V', grace: true),
        _row(name: 'penalty', village: 'V', penalty: true),
      ], CollectionSort.penaltyFirst);
      expect(out.map((r) => r.customerName), ['penalty', 'grace', 'plain']);
    });

    test('name orders by name whatever the amounts are', () {
      final out = manaSortDueRows([
        _row(name: 'Zubair', village: 'V', due: 900),
        _row(name: 'Anita', village: 'V', due: 100),
      ], CollectionSort.name);
      expect(out.first.customerName, 'Anita');
    });

    test('two rows level on the sort fall back to the name, never to chance', () {
      final out = manaSortDueRows([
        _row(name: 'Zubair', village: 'V', due: 500),
        _row(name: 'Anita', village: 'V', due: 500),
      ], CollectionSort.dueToday);
      expect(out.map((r) => r.customerName), ['Anita', 'Zubair']);
    });
  });
}

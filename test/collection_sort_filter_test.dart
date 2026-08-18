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
}

List<CollectionDueRow> _rows() => [
      _row(name: 'Anand', village: 'Renigunta', frequency: 'Weekly'),
    ];

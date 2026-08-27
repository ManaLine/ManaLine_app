import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

/// What this pins: a door already answered is not work, so it sinks.
///
/// The round is worked from the top. With finished doors left interleaved,
/// an Agent halfway through a village scrolls past this morning to find this
/// afternoon, and the longer the round the worse it gets.
///
/// They still appear -- an Agent checking whether they visited somebody has to
/// be able to find them. They are simply last.
CollectionDueRow _row(
  String name, {
  required String status,
  int due = 1000,
  int outstanding = 50000,
  bool penalty = false,
}) =>
    CollectionDueRow(
      loanId: 'l-$name',
      customerId: 'c-$name',
      customerName: name,
      village: 'Uranduru',
      loanNumber: 'LN-$name',
      installmentDue: due,
      outstandingBalance: outstanding,
      lineRepaymentIndex: 0,
      collectionStatus: status,
      collectionAgent: 'm1',
      penaltyEligible: penalty,
    );

void main() {
  group('finished doors sink, whatever the sort', () {
    for (final mode in CollectionSort.values) {
      test('under ${mode.name}', () {
        final rows = [
          _row('Collected One', status: 'Collected', due: 9000, outstanding: 900000, penalty: true),
          _row('Pending One', status: 'Pending', due: 100, outstanding: 100),
          _row('Skipped One', status: 'Skipped', due: 8000, outstanding: 800000, penalty: true),
          _row('Partial One', status: 'Partial', due: 7000, outstanding: 700000),
          _row('Pending Two', status: 'Pending', due: 200, outstanding: 200),
        ];

        final sorted = manaSortDueRows(rows, mode);
        final settled = sorted.map(manaRowSettled).toList();

        // Every unfinished row comes before every finished one. Deliberately
        // asserted for EVERY sort mode: the seeded figures are rigged so that
        // due-today, outstanding and penalty-first would each pull a finished
        // row to the top if the rule were not applied first.
        final firstSettled = settled.indexOf(true);
        expect(firstSettled, isNot(-1), reason: 'the seed has settled rows');
        expect(settled.sublist(firstSettled).every((s) => s), isTrue,
            reason: 'a pending door appeared after a finished one under '
                '${mode.name}');
      });
    }

    test('nothing is dropped', () {
      final rows = [
        _row('A', status: 'Collected'),
        _row('B', status: 'Pending'),
        _row('C', status: 'Skipped'),
      ];
      final sorted = manaSortDueRows(rows, CollectionSort.dueToday);
      expect(sorted.length, 3,
          reason: 'finished doors move to the end, they do not disappear -- an '
              'Agent checking whether they visited somebody must find them');
    });

    test('a door not yet knocked on is not settled', () {
      expect(manaRowSettled(_row('X', status: 'Pending')), isFalse);
    });

    test('visited and paid nothing IS settled', () {
      // Skipped means somebody went and recorded an outcome. That is done
      // work, and it is not the same as a door nobody has reached.
      expect(manaRowSettled(_row('X', status: 'Skipped')), isTrue);
    });
  });
}

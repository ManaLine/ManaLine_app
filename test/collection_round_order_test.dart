import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/collection_mode_state.dart';

/// What counts as a finished door, and where finished doors go.
///
/// The round only ever knew about TODAY: `today_result` is scoped to
/// CURRENT_DATE. So a Weekly customer collected from yesterday came back to
/// the top of this morning's round as unanswered work — and the server then
/// refused the entry, because a Weekly loan's one-entry window is the account
/// cycle, not the day. The Agent was being sent to a door the database would
/// not let them record.
CollectionDueRow _row(
  String name, {
  String? today,
  String? cycle,
  DateTime? firstAt,
  int due = 1000,
  int cycleCollected = 0,
  int outstanding = 10000,
}) =>
    CollectionDueRow(
      loanId: 'l-$name',
      customerId: 'c-$name',
      customerName: name,
      village: 'Panagallu',
      loanNumber: 'LN-$name',
      mlid: 'MLCU$name',
      installmentDue: due,
      installmentAmount: due,
      outstandingBalance: outstanding,
      lineRepaymentIndex: 0,
      collectionStatus: today ?? 'Pending',
      cycleStatus: cycle,
      cycleCollected: cycleCollected,
      cycleFirstAt: firstAt,
      collectionAgent: 'm1',
    );

void main() {
  group('what counts as a finished door', () {
    test('the whole instalment paid earlier in the cycle is finished', () {
      // Paid the full Rs 1,000 on Tuesday; nothing owed again until next
      // cycle, so the door is done however many days are left in it.
      final r = _row('Paid In Full',
          cycle: 'Collected',
          cycleCollected: 1000,
          firstAt: DateTime(2026, 8, 27, 9));
      expect(manaRowSettled(r), isTrue);
    });

    test('PART of the instalment paid in the cycle is still work', () {
      // Rs 100 a day against a Rs 1,000 weekly instalment. This is the case
      // that used to sink after the first payment, so the Agent had to hunt
      // for them on each of the next five mornings.
      final r = _row('Paying Daily',
          cycle: 'Partial',
          cycleCollected: 200,
          firstAt: DateTime(2026, 8, 27, 9));
      expect(manaRowSettled(r), isFalse,
          reason: 'Rs 200 of Rs 1,000 is not a finished door');
    });

    test('but once today has been answered it sinks, part-paid or not', () {
      final r = _row('Paid Today',
          today: 'Partial', cycle: 'Partial', cycleCollected: 300);
      expect(manaRowSettled(r), isTrue,
          reason: 'the Agent has already stood at this door today');
    });

    test('never collected in the window is still work', () {
      expect(manaRowSettled(_row('Untouched')), isFalse);
    });

    test('a visit that collected nothing today is answered too', () {
      expect(manaRowSettled(_row('Skipped', today: 'Skipped')), isTrue);
    });

    test('a loan with nothing left owing is finished', () {
      expect(manaRowSettled(_row('Cleared', outstanding: 0)), isTrue);
    });

    test('a daily collection sinks today and is back on top tomorrow', () {
      // A Daily loan's window IS the day, so today's Rs 100 meets today's
      // instalment and the door sinks.
      final today = _row('Daily Payer',
          due: 100, today: 'Collected', cycle: 'Collected', cycleCollected: 100);
      expect(manaRowSettled(today), isTrue);

      // Tomorrow the same row comes back: today_result is scoped to the
      // current date and the window has rolled, so nothing has been answered
      // yet and Rs 100 is owed again.
      final tomorrow = _row('Daily Payer', due: 100);
      expect(manaRowSettled(tomorrow), isFalse,
          reason: 'a daily customer is work again every morning');
    });
  });

  group('where the finished doors sit', () {
    test('settled sink below unanswered, first-answered furthest down', () {
      final rows = [
        _row('Answered First',
            cycle: 'Collected',
            cycleCollected: 1000,
            firstAt: DateTime(2026, 8, 28, 9)),
        _row('Still Due A'),
        _row('Answered Last',
            cycle: 'Collected',
            cycleCollected: 1000,
            firstAt: DateTime(2026, 8, 28, 17)),
        _row('Still Due B'),
      ];

      final sorted = manaSortDueRows(rows, CollectionSort.name);
      final names = sorted.map((r) => r.customerName).toList();

      // Work first, in the chosen order.
      expect(names.take(2), ['Still Due A', 'Still Due B']);
      // Then the answered ones, newest first — so the one answered at 9am is
      // at the very bottom, where the Agent is least likely to be looking.
      expect(names.skip(2), ['Answered Last', 'Answered First']);
    });

    test('reversing the sort does not float finished doors back up', () {
      final rows = [
        _row('Answered',
            cycle: 'Collected',
            cycleCollected: 1000,
            firstAt: DateTime(2026, 8, 28, 9)),
        _row('Still Due'),
      ];

      for (final ascending in [true, false]) {
        final names = manaSortDueRows(rows, CollectionSort.name,
                ascending: ascending)
            .map((r) => r.customerName)
            .toList();
        expect(names.last, 'Answered',
            reason: 'direction applies to the work, not to what is done');
      }
    });
  });
}

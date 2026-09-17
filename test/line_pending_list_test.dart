import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_line_pending_list.dart';
import 'package:mana_line/features/owner_workspace/state/line_pending_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

PendingLoanRow _row({
  required String id,
  String name = 'Venkata Subrahmanyam',
  String careOf = 'Satyanarayana Murthy',
  String village = 'Pedanandipadu',
  String pin = '522235',
  int balance = 6000,
  String type = 'Weekly',
  DateTime? issued,
  int overdue = 3,
  DateTime? lastPaid,
}) =>
    PendingLoanRow(
      loanId: id,
      customerId: 'c-$id',
      fullName: name,
      careOf: careOf,
      village: village,
      pinCode: pin,
      balance: balance,
      installmentAmount: 500,
      repaymentType: type,
      issued: issued ?? DateTime(2026, 5, 1),
      periodsOverdue: overdue,
      lastPaid: lastPaid,
    );

class _Seeded extends LinePendingNotifier {
  static late LinePendingState seed;
  @override
  LinePendingState build() => seed;
  @override
  Future<void> load(String businessId) async {}
}

void main() {
  group('the sort the Owner picked', () {
    final rows = [
      _row(id: 'a', name: 'Anil', balance: 1000, village: 'Zeta', pin: '500001',
          issued: DateTime(2026, 1, 1), lastPaid: DateTime(2026, 8, 1)),
      _row(id: 'b', name: 'Zara', balance: 9000, village: 'Alpha', pin: '500002',
          issued: DateTime(2026, 6, 1), lastPaid: DateTime(2026, 2, 1)),
      _row(id: 'c', name: 'Meena', balance: 5000, village: 'Alpha', pin: '500001',
          issued: DateTime(2026, 3, 1), lastPaid: null),
    ];
    LinePendingState s(PendingSort sort) =>
        LinePendingState(rows: rows, sort: sort);

    test('Amount is highest balance first', () {
      expect(s(PendingSort.amount).sorted.map((r) => r.loanId),
          ['b', 'c', 'a']);
    });

    test('New is the newest loan, Old is the oldest', () {
      expect(s(PendingSort.newest).sorted.first.loanId, 'b');
      expect(s(PendingSort.oldest).sorted.first.loanId, 'a');
    });

    test('Longest Unpaid puts someone who NEVER paid at the top', () {
      // A null last-payment is the longest anybody has gone without paying.
      // Sorted as a missing value it would drift to the bottom, which is the
      // opposite of the truth and hides the worst row on the list.
      expect(s(PendingSort.lastPaid).sorted.map((r) => r.loanId),
          ['c', 'b', 'a']);
    });

    test('Name is case-insensitive', () {
      expect(s(PendingSort.name).sorted.map((r) => r.fullName),
          ['Anil', 'Meena', 'Zara']);
    });

    test('Village then PIN, so one village stays together', () {
      final out = s(PendingSort.villagePin).sorted;
      expect(out.map((r) => r.village), ['Alpha', 'Alpha', 'Zeta']);
      // Within Alpha, the lower PIN first -- the two are one sort, not two.
      expect(out.take(2).map((r) => r.pinCode), ['500001', '500002']);
    });

    test('every sort is stable on a tie', () {
      // Two rows alike in every sorted field. Without the loan-id fallback
      // they swap places between rebuilds, under somebody's thumb.
      final tied = [
        _row(id: 'x', name: 'Same', balance: 100, village: 'V', pin: '1',
            issued: DateTime(2026, 1, 1), lastPaid: DateTime(2026, 1, 1)),
        _row(id: 'y', name: 'Same', balance: 100, village: 'V', pin: '1',
            issued: DateTime(2026, 1, 1), lastPaid: DateTime(2026, 1, 1)),
      ];
      for (final sort in PendingSort.values) {
        expect(
            LinePendingState(rows: tied, sort: sort)
                .sorted
                .map((r) => r.loanId),
            ['x', 'y'],
            reason: '$sort is not stable');
      }
    });

    test('sorting never drops or adds a row', () {
      for (final sort in PendingSort.values) {
        expect(s(sort).sorted.length, rows.length, reason: '$sort');
        expect(s(sort).sorted.map((r) => r.loanId).toSet(),
            {'a', 'b', 'c'}, reason: '$sort');
      }
    });
  });

  group('what the screen claims about itself', () {
    test('a narrowed list knows it is narrowed', () {
      // An Owner reading a filtered pending list as the whole book believes
      // their line is in better shape than it is, so the rail marks it.
      expect(const LinePendingState().isNarrowed, isFalse);
      expect(const LinePendingState(minBalance: 500).isNarrowed, isTrue);
      expect(const LinePendingState(minPeriods: 4).isNarrowed, isTrue);
      expect(LinePendingState(from: DateTime(2026)).isNarrowed, isTrue);
      // A sort is not a narrowing.
      expect(const LinePendingState(sort: PendingSort.amount).isNarrowed,
          isFalse);
    });

    test('the total is the sum of what is shown', () {
      expect(
          LinePendingState(rows: [
            _row(id: 'a', balance: 1000),
            _row(id: 'b', balance: 2500),
          ]).totalOutstanding,
          3500);
    });
  });

  group('it lays out', () {
    for (final scale in kManaTextScales) {
      for (final lang in ManaLanguage.values) {
        testWidgets('pending list at ${scale}x in ${lang.name}',
            (tester) async {
          _Seeded.seed = LinePendingState(rows: [
            // A Daily loan, so the unit placeholder is exercised, and a
            // never-paid row, which renders a different string.
            _row(id: 'a', type: 'Daily', overdue: 205, lastPaid: null),
            _row(id: 'b', balance: 126000, overdue: 34),
            _row(id: 'c', type: 'Monthly', overdue: 4,
                lastPaid: DateTime(2026, 7, 4)),
          ], minBalance: 500, minPeriods: 4);

          await pumpManaScreen(
            tester,
            const LinePendingListScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [linePendingProvider.overrideWith(_Seeded.new)],
          );
          expectNoLayoutFault(
              tester, 'line pending list at ${scale}x in ${lang.name}');
        });
      }
    }

    // TWO TESTS, NOT ONE. Pumping a second screen inside one testWidgets
    // left the first one's skeleton animation running -- "A Timer is still
    // pending even after the widget tree was disposed" -- which fails the
    // test for a reason that has nothing to do with what it checks.
    //
    // Nothing pending is good news; nothing matching a filter is not. A screen
    // that told somebody who had simply filtered too hard that every loan was
    // settled would be lying about the state of their line.
    testWidgets('an empty book says the book is settled', (tester) async {
      _Seeded.seed = const LinePendingState(rows: []);
      await pumpManaScreen(
        tester,
        const LinePendingListScreen(businessId: 'b1'),
        overrides: [linePendingProvider.overrideWith(_Seeded.new)],
      );
      expect(find.textContaining('settled'), findsOneWidget);
    });

    testWidgets('an over-filtered list does not claim the book is settled',
        (tester) async {
      _Seeded.seed = const LinePendingState(rows: [], minBalance: 5000);
      await pumpManaScreen(
        tester,
        const LinePendingListScreen(businessId: 'b1'),
        overrides: [linePendingProvider.overrideWith(_Seeded.new)],
      );
      expect(find.textContaining('settled'), findsNothing);
      expect(find.textContaining('match these filters'), findsOneWidget);
    });
  });
}

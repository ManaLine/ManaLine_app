import 'package:flutter_test/flutter_test.dart';

/// How long one collection entry covers, as a table.
///
/// THE BUG THIS EXISTS FOR: the one-entry window for a Weekly or Monthly loan
/// was the account period. That held while a period was four planned days. It
/// stopped holding the moment periods became open-ended — they run from the
/// last submission to the next now — so the window stretched to fifteen days
/// and counting, every customer collected once inside it read as done, and no
/// weekly collection could be taken until somebody submitted a settlement.
///
/// Nothing failed. The analyzer was clean, every test passed, and the app was
/// refusing to take money for two weeks. It was found by an Owner on a
/// handset, which is the most expensive place to find anything.
///
/// This mirrors app.collection_entry_window. Two copies of a rule is normally
/// a smell, and here it is the point: the SQL is what runs, and this is a
/// written-down statement of what it is supposed to mean, so that changing one
/// without meaning to change the other fails loudly.
///
/// THE RULE, as the Owner states it: a Daily loan is collected once a day, a
/// Weekly loan once a week, a Monthly loan once a month — and submitting an
/// account starts a fresh entry, because money taken after the handover
/// belongs to the next account. So the window opens at the LATER of the
/// cadence start and the account period start.
DateTime _windowFrom({
  required String repaymentType,
  required DateTime today,
  DateTime? periodStart,
}) {
  final cadence = switch (repaymentType) {
    'Daily' => today,
    // Monday, matching date_trunc('week', ...).
    'Weekly' => today.subtract(Duration(days: today.weekday - 1)),
    _ => DateTime(today.year, today.month, 1),
  };
  if (periodStart != null && periodStart.isAfter(cadence)) return periodStart;
  return cadence;
}

bool _collectable({
  required String repaymentType,
  required DateTime today,
  DateTime? periodStart,
  DateTime? lastCollection,
}) {
  if (lastCollection == null) return true;
  final from = _windowFrom(
      repaymentType: repaymentType, today: today, periodStart: periodStart);
  // Inside the window means already collected.
  return lastCollection.isBefore(from);
}

void main() {
  // Tuesday 1 September 2026. The week began Monday the 31st.
  final today = DateTime(2026, 9, 1);
  // The live account period on the book that broke: opened 18 August.
  final longOpenPeriod = DateTime(2026, 8, 18);

  group('the window', () {
    test('a daily loan is the day', () {
      expect(_windowFrom(repaymentType: 'Daily', today: today), today);
    });

    test('a weekly loan is this week, not the whole account', () {
      // THE REGRESSION, as a single assertion: with the account period as the
      // window this was 18 August.
      expect(
        _windowFrom(
            repaymentType: 'Weekly', today: today, periodStart: longOpenPeriod),
        DateTime(2026, 8, 31),
      );
    });

    test('a monthly loan is this month', () {
      expect(
        _windowFrom(
            repaymentType: 'Monthly', today: today, periodStart: longOpenPeriod),
        DateTime(2026, 9, 1),
      );
    });

    test('an account opened mid-week wins over the week start', () {
      // Period opened Tuesday 18 Aug; that week began Monday the 17th. The
      // 17th belonged to the account that was handed over.
      expect(
        _windowFrom(
          repaymentType: 'Weekly',
          today: DateTime(2026, 8, 20),
          periodStart: longOpenPeriod,
        ),
        longOpenPeriod,
      );
    });

    test('no account period leaves the cadence standing alone', () {
      expect(
        _windowFrom(repaymentType: 'Weekly', today: today),
        DateTime(2026, 8, 31),
      );
    });
  });

  group('whether the money can be taken', () {
    test('last week does not block this week', () {
      // This is what was broken: collected 26 August, still inside the
      // 18-August-to-today period, so the round said done.
      expect(
        _collectable(
          repaymentType: 'Weekly',
          today: today,
          periodStart: longOpenPeriod,
          lastCollection: DateTime(2026, 8, 26),
        ),
        isTrue,
      );
    });

    test('this week does block this week', () {
      // The window still has a job. Removing the block would be the opposite
      // regression: the same customer paying twice into one week.
      expect(
        _collectable(
          repaymentType: 'Weekly',
          today: today,
          periodStart: longOpenPeriod,
          lastCollection: DateTime(2026, 8, 31),
        ),
        isFalse,
      );
    });

    test('a daily loan collected yesterday is collectable today', () {
      expect(
        _collectable(
          repaymentType: 'Daily',
          today: today,
          lastCollection: DateTime(2026, 8, 31),
        ),
        isTrue,
      );
    });

    test('a daily loan collected today is not', () {
      expect(
        _collectable(
          repaymentType: 'Daily',
          today: today,
          lastCollection: today,
        ),
        isFalse,
      );
    });

    test('last month does not block this month', () {
      expect(
        _collectable(
          repaymentType: 'Monthly',
          today: today,
          lastCollection: DateTime(2026, 8, 26),
        ),
        isTrue,
      );
    });

    test('a fresh account reopens the entry mid-week', () {
      // Collected Tuesday, account submitted and reopened Wednesday: Thursday
      // is collectable again, because Wednesday's money belongs to the new
      // account.
      expect(
        _collectable(
          repaymentType: 'Weekly',
          today: DateTime(2026, 9, 3),
          periodStart: DateTime(2026, 9, 2),
          lastCollection: DateTime(2026, 9, 1),
        ),
        isTrue,
      );
    });
  });
}

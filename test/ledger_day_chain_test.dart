import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/ledger_history_service.dart';

LedgerEvent _out(String date, int amount) => LedgerEvent(
      id: '$date-out-$amount',
      type: LedgerEventType.loanDistribution,
      businessDate: date,
      occurredAt: DateTime.parse('${date}T10:00:00'),
      amount: amount,
    );

LedgerEvent _in(String date, int amount) => LedgerEvent(
      id: '$date-in-$amount',
      type: LedgerEventType.investorDeposit,
      businessDate: date,
      occurredAt: DateTime.parse('${date}T10:00:00'),
      amount: amount,
    );

LedgerDay _day(List<LedgerDay> days, String date) =>
    days.firstWhere((d) => d.businessDate == date);

void main() {
  group('the book is weekly, and each day opens on the last carried forward', () {
    // The live book, exactly as the Owner described it:
    //   1 Jan  opens 0        -> 3 loans out, 68,600      -> carries -68,600
    //   2 Jan  opens -68,600  -> deposit and loans        -> carries 491,380
    //   8 Jan  opens 491,380  -> ...
    //   9 Jan                                             -> carries 181,440
    //
    // 2 Jan and 9 Jan are account dates: the book states their closing, and
    // that figure wins over anything the events add up to, because the
    // migrated events are only a partial reconstruction of the week.
    final events = [
      _out('2026-01-01', 68600),
      _in('2026-01-02', 1000000),
      _out('2026-01-02', 263580),
      _out('2026-01-08', 215600),
      _out('2026-01-09', 92040),
    ];
    const balances = {
      '2026-01-02': LedgerDayBalance(opening: 0, closing: 491380),
      '2026-01-09': LedgerDayBalance(opening: 491380, closing: 181440),
    };

    final days = groupByBusinessDate(events, balances: balances);

    test('a day the book never closed carries its own movements', () {
      expect(_day(days, '2026-01-01').openingBf, 0);
      // Negative on purpose. The deposit that covers it is dated to the
      // account date, which is how the book was kept — not an error to hide.
      expect(_day(days, '2026-01-01').closingBf, -68600);
    });

    test('the next day opens on that carried forward, negative and all', () {
      expect(_day(days, '2026-01-02').openingBf, -68600);
    });

    test("an account date carries the BOOK's closing, not the sum of events", () {
      // Events alone would give -68,600 + 1,000,000 - 263,580 = 667,820.
      // The book says 491,380, and the book is what is right: the week's
      // collections and some of its loans were never imported row by row.
      expect(_day(days, '2026-01-02').netOfLoadedEvents, 736420);
      expect(_day(days, '2026-01-02').closingBf, 491380);
    });

    test('the new week opens on the book, not on the old accumulation', () {
      expect(_day(days, '2026-01-08').openingBf, 491380);
      expect(_day(days, '2026-01-08').closingBf, 491380 - 215600);
    });

    test('and closes on the book again', () {
      expect(_day(days, '2026-01-09').openingBf, 491380 - 215600);
      expect(_day(days, '2026-01-09').closingBf, 181440);
    });
  });

  group('after the migrated span every day is its own account date', () {
    test('opening and carried forward both come from that day', () {
      final days = groupByBusinessDate(
        [_out('2026-08-24', 5000), _in('2026-08-25', 2000)],
        balances: const {
          '2026-08-24': LedgerDayBalance(opening: 10000, closing: 5000),
          '2026-08-25': LedgerDayBalance(opening: 5000, closing: 7000),
        },
      );
      expect(_day(days, '2026-08-24').openingBf, 10000);
      expect(_day(days, '2026-08-24').closingBf, 5000);
      expect(_day(days, '2026-08-25').openingBf, 5000);
      expect(_day(days, '2026-08-25').closingBf, 7000);
    });
  });

  group('what it refuses to invent', () {
    test('no balances at all means no opening is claimed', () {
      // A feed with nothing closed around it cannot know what it opened on,
      // and a zero would read as "the till was empty".
      final days = groupByBusinessDate([_out('2026-01-01', 500)]);
      expect(_day(days, '2026-01-01').openingBf, isNull);
      expect(_day(days, '2026-01-01').closingBf, isNull);
    });

    test('days after the last closed week still chain forward', () {
      final days = groupByBusinessDate(
        [_out('2026-01-02', 1000), _out('2026-01-03', 400)],
        balances: const {
          '2026-01-02': LedgerDayBalance(opening: 0, closing: 5000),
        },
      );
      expect(_day(days, '2026-01-02').closingBf, 5000);
      expect(_day(days, '2026-01-03').openingBf, 5000);
      expect(_day(days, '2026-01-03').closingBf, 4600);
    });
  });
}

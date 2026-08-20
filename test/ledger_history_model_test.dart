import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/ledger_history_service.dart';

/// Phase 0 of the history redesign: the shared ledger model.
///
/// These pin the parts that decide whether money reads correctly on screen —
/// direction per event type, business-day grouping, and the deliberate
/// separation between "net of what is loaded" and a real balance.
Map<String, dynamic> _row({
  required String id,
  required String type,
  required String date,
  required String at,
  required num amount,
  String? counterparty,
  String? reference,
  String? method,
}) =>
    {
      'event_id': id,
      'event_type': type,
      'business_date': date,
      'occurred_at': at,
      'amount': amount,
      'counterparty': counterparty,
      'reference': reference,
      'method': method,
    };

void main() {
  group('event types carry their own direction', () {
    test('every wire value maps to exactly one type', () {
      const wires = <String>[
        'bf_grant',
        'collection',
        'loan_distribution',
        'expense',
        'investor_deposit',
        'investor_withdrawal',
        'cheti_paid',
        'cheti_received',
        'adjustment_short',
        'adjustment_excess',
      ];
      for (final w in wires) {
        expect(LedgerEventType.fromWire(w).wire, w);
      }
      // day_ledger names eight money categories; short/excess split the
      // adjustment one into two directions, and BF — the float a round is
      // funded by — is the tenth.
      expect(LedgerEventType.values.length, wires.length);
    });

    test('money in and money out are assigned correctly', () {
      const moneyIn = {
        LedgerEventType.collection,
        LedgerEventType.investorDeposit,
        LedgerEventType.chetiReceived,
        LedgerEventType.adjustmentExcess,
      };
      // A BF grant is neither: it moves cash between two pockets of the same
      // business and must reach no total.
      const transfers = {LedgerEventType.bfGrant};

      for (final t in LedgerEventType.values) {
        final expected = transfers.contains(t)
            ? LedgerDirection.transfer
            : moneyIn.contains(t)
                ? LedgerDirection.moneyIn
                : LedgerDirection.moneyOut;
        expect(t.direction, expected, reason: '${t.wire} has the wrong direction');
      }
    });

    test('an unknown type throws rather than being guessed', () {
      // Silently dropping it would shorten a money list; defaulting it to a
      // direction would put a debit on the credit side. Both are worse than
      // a loud failure.
      expect(() => LedgerEventType.fromWire('crypto_airdrop'), throwsArgumentError);
    });
  });

  group('LedgerEvent', () {
    test('parses a server row', () {
      final e = LedgerEvent.fromRow(_row(
        id: 'collection:abc',
        type: 'collection',
        date: '2026-08-12',
        at: '2026-08-12T09:32:00',
        amount: 4500,
        counterparty: 'Venkat Rao',
        reference: 'L-1042',
        method: 'Full',
      ));
      expect(e.id, 'collection:abc');
      expect(e.type, LedgerEventType.collection);
      expect(e.isMoneyIn, isTrue);
      expect(e.amount, 4500);
      expect(e.signedAmount, 4500);
      expect(e.businessDate, '2026-08-12');
      expect(e.counterparty, 'Venkat Rao');
    });

    test('money out signs negative for arithmetic', () {
      final e = LedgerEvent.fromRow(_row(
        id: 'loan:x',
        type: 'loan_distribution',
        date: '2026-08-12',
        at: '2026-08-12T08:15:00',
        amount: 8800,
      ));
      expect(e.isMoneyIn, isFalse);
      expect(e.signedAmount, -8800);
      // The raw figure stays positive — the UI shows direction by tone and
      // position, not by printing a minus on every debit.
      expect(e.amount, 8800);
    });

    test('rounds to whole rupees, since paise cannot be stored', () {
      final e = LedgerEvent.fromRow(_row(
        id: 'expense:x',
        type: 'expense',
        date: '2026-08-12',
        at: '2026-08-12T10:00:00',
        amount: 300.4,
      ));
      expect(e.amount, 300);
    });
  });

  group('grouping', () {
    test('groups by business date, keeping feed order', () {
      final events = [
        LedgerEvent.fromRow(_row(id: 'a', type: 'collection', date: '2026-08-12', at: '2026-08-12T12:00:00', amount: 100)),
        LedgerEvent.fromRow(_row(id: 'b', type: 'expense', date: '2026-08-12', at: '2026-08-12T09:00:00', amount: 40)),
        LedgerEvent.fromRow(_row(id: 'c', type: 'collection', date: '2026-08-11', at: '2026-08-11T18:00:00', amount: 70)),
      ];
      final days = groupByBusinessDate(events);
      expect(days.map((d) => d.businessDate).toList(), ['2026-08-12', '2026-08-11']);
      expect(days.first.events.length, 2);
      expect(days.last.events.single.id, 'c');
    });

    test('groups on business date, not on the timestamp local date', () {
      // A collection taken at 00:30 IST belongs to that Indian day. If
      // grouping ever derives the day from occurred_at instead of
      // business_date, this is the case that catches it.
      final events = [
        LedgerEvent.fromRow(_row(
          id: 'late', type: 'collection', date: '2026-08-13',
          at: '2026-08-13T00:30:00', amount: 500)),
        LedgerEvent.fromRow(_row(
          id: 'earlier', type: 'collection', date: '2026-08-12',
          at: '2026-08-12T23:45:00', amount: 300)),
      ];
      final days = groupByBusinessDate(events);
      expect(days.length, 2);
      expect(days.first.businessDate, '2026-08-13');
    });

    test('day totals split in and out, and net them', () {
      final day = groupByBusinessDate([
        LedgerEvent.fromRow(_row(id: 'a', type: 'collection', date: '2026-08-12', at: '2026-08-12T09:00:00', amount: 4500)),
        LedgerEvent.fromRow(_row(id: 'b', type: 'loan_distribution', date: '2026-08-12', at: '2026-08-12T08:00:00', amount: 8800)),
        LedgerEvent.fromRow(_row(id: 'c', type: 'expense', date: '2026-08-12', at: '2026-08-12T10:00:00', amount: 300)),
      ]).single;

      expect(day.moneyIn, 4500);
      expect(day.moneyOut, 9100);
      expect(day.netOfLoadedEvents, -4600);
    });
  });

  group('LedgerMonthSummary', () {
    test('an empty month is distinguishable from a month that netted zero', () {
      final empty = LedgerMonthSummary.fromRow({
        'month_start': '2026-08-01',
        'received': 0, 'spent': 0, 'net': 0,
        'opening_balance': null, 'closing_balance': null, 'days_recorded': 0,
      });
      final balanced = LedgerMonthSummary.fromRow({
        'month_start': '2026-08-01',
        'received': 5000, 'spent': 5000, 'net': 0,
        'opening_balance': 100, 'closing_balance': 100, 'days_recorded': 11,
      });

      expect(empty.isEmpty, isTrue);
      expect(balanced.isEmpty, isFalse);
      expect(balanced.net, 0);
      // Both show ₹0 net. Only one of them means "nothing happened", and the
      // screen has to be able to tell them apart.
      expect(empty.net, balanced.net);
    });

    test('carries opening and closing balances when the ledger has them', () {
      final s = LedgerMonthSummary.fromRow({
        'month_start': '2026-08-01',
        'received': 152500, 'spent': 82447, 'net': 70053,
        'opening_balance': 250000, 'closing_balance': 320053, 'days_recorded': 11,
      });
      expect(s.openingBalance, 250000);
      expect(s.closingBalance, 320053);
      expect(s.received - s.spent, s.net);
    });
  });
}

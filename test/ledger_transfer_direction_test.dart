import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/ledger_history_service.dart';

LedgerEvent _e(LedgerEventType t, int amount) => LedgerEvent(
      id: '${t.wire}:$amount',
      type: t,
      businessDate: '2026-08-20',
      occurredAt: DateTime(2026, 8, 20),
      amount: amount,
    );

/// A BF grant hands cash from the Owner's till to an Agent's pocket inside one
/// business. Nothing enters or leaves, so it must reach no total.
///
/// Caught live: History showed "Thu 20 Aug, Day Net +₹11,000" from three BF
/// grants while the month header — read from day_ledger, the business's actual
/// book — correctly showed August flat at ₹0. Two sources disagreeing about
/// money on one screen is the failure this app cannot have.
void main() {
  test('a BF grant is a transfer, not income', () {
    expect(LedgerEventType.bfGrant.direction, LedgerDirection.transfer);
    expect(_e(LedgerEventType.bfGrant, 5000).isTransfer, isTrue);
    expect(_e(LedgerEventType.bfGrant, 5000).signedAmount, 0);
  });

  test('a day of nothing but BF grants nets zero, matching day_ledger', () {
    final day = LedgerDay(businessDate: '2026-08-20', events: [
      _e(LedgerEventType.bfGrant, 5000),
      _e(LedgerEventType.bfGrant, 1000),
      _e(LedgerEventType.bfGrant, 5000),
    ]);

    expect(day.netOfLoadedEvents, 0);
    expect(day.moneyIn, 0);
    expect(day.moneyOut, 0);
  });

  test('transfers do not distort a day that also has real movement', () {
    final day = LedgerDay(businessDate: '2026-08-20', events: [
      _e(LedgerEventType.bfGrant, 5000),      // ignored
      _e(LedgerEventType.collection, 2000),   // +2000
      _e(LedgerEventType.expense, 500),       // -500
    ]);

    expect(day.moneyIn, 2000);
    expect(day.moneyOut, 500);
    expect(day.netOfLoadedEvents, 1500);
  });

  test('every other type still counts', () {
    for (final t in LedgerEventType.values) {
      if (t == LedgerEventType.bfGrant) continue;
      expect(_e(t, 100).signedAmount, isNot(0), reason: '${t.wire} must count');
    }
  });
}

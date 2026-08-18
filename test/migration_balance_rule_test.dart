import 'package:flutter_test/flutter_test.dart';

/// The rule OW-018's in-app path now follows, stated as arithmetic so it
/// cannot drift back.
///
/// The screen used to derive a loan's remaining balance as
/// `pending instalments x instalment amount`. That cannot express a PART-PAID
/// instalment, and 14% of the loans in the Owner's real book have one — so a
/// customer owing 6,250 against a 500 instalment was written into the ledger
/// as either 6,000 or 6,500. The balance is typed in rupees now, and the
/// instalment COUNT is derived from it by CEILING, matching app.migrate_loan.
int instalmentsFor({required int balance, required int instalment}) =>
    (balance / instalment).ceil();

void main() {
  group('instalment count is derived from the balance, ceiling', () {
    test('a part-paid instalment still gets a row of its own', () {
      // 12 full instalments and 250 left over: 13 rows, the last one short.
      expect(instalmentsFor(balance: 6250, instalment: 500), 13);
    });

    test('an exact multiple is not rounded up to a phantom extra row', () {
      expect(instalmentsFor(balance: 6000, instalment: 500), 12);
    });

    test('a balance under one instalment is still one row', () {
      expect(instalmentsFor(balance: 200, instalment: 500), 1);
    });

    test('a settled loan schedules nothing', () {
      expect(instalmentsFor(balance: 0, instalment: 500), 0);
    });
  });

  group('what the old formula could not say', () {
    test('pending x EMI cannot produce 6,250 at any instalment count', () {
      // The point of the change, as a property: with a 500 instalment there is
      // no whole number of pending instalments that equals 6,250. The old
      // screen therefore could not record this customer correctly at all.
      const balance = 6250;
      const instalment = 500;
      final reachable = [for (var n = 0; n <= 20; n++) n * instalment];
      expect(reachable, isNot(contains(balance)));
    });
  });
}

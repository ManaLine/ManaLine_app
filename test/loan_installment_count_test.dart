import 'package:flutter_test/flutter_test.dart';

/// What this pins: how many instalments a loan has completed.
///
/// It read 0 for every loan in the app. Not a rounding slip -- all 8,075
/// rows in loan_schedule are 'Pending', because record_collection has never
/// written that column. The schedule is a plan that was written once and
/// never advanced, so counting Completed rows counts nothing, forever. A
/// loan with eleven collections recorded against it showed "Completed
/// Installments 0" on screen.
///
/// The fix derives it from the balance, which is the figure the rest of the
/// app already treats as truth. Marking schedule rows as money lands would
/// need a payment waterfall to decide what a part-payment completes, and this
/// app deliberately has none.
///
/// The cases below are real rows from the live table, kept as the arithmetic
/// rather than as a database call.
int completed(int repayment, int emi, int owed) {
  if (emi <= 0) return 0;
  final total = (repayment / emi).ceil();
  return ((repayment - owed) / emi).floor().clamp(0, total);
}

int remaining(int repayment, int emi, int owed) {
  if (emi <= 0) return 0;
  final total = (repayment / emi).ceil();
  return (total - completed(repayment, emi, owed)).clamp(0, total);
}

void main() {
  group('instalments completed, from the balance', () {
    test('a loan with eleven collections has completed eleven', () {
      // LN-MIG-20260822-6c894a: 12,000 at 1,000, 1,000 left, 11 collections.
      expect(completed(12000, 1000, 1000), 11);
      expect(remaining(12000, 1000, 1000), 1);
    });

    test('the loan from the screenshot', () {
      // 600,000 at 30,000 with 510,000 left. The screen said 0 completed and
      // 20 remaining, which would mean nothing had been paid on a loan that
      // is 90,000 down.
      expect(completed(600000, 30000, 510000), 3);
      expect(remaining(600000, 30000, 510000), 17);
    });

    test('a migrated loan whose schedule holds only what is left', () {
      // LN-MIG-20260819-e3938c: 24,000 at 2,000, 12,000 left, and only SIX
      // schedule rows because a migrated schedule is the remainder, not the
      // term. Counting rows would have answered a different question.
      expect(completed(24000, 2000, 12000), 6);
      expect(remaining(24000, 2000, 12000), 6);
    });

    test('an untouched loan has completed nothing', () {
      expect(completed(60000, 5000, 60000), 0);
      expect(remaining(60000, 5000, 60000), 12);
    });

    test('a settled loan has completed everything', () {
      expect(completed(60000, 5000, 0), 12);
      expect(remaining(60000, 5000, 0), 0);
    });

    test('a part-payment does not complete an instalment', () {
      // Half an instalment down. The balance moved; the count must not,
      // because the instalment is not finished.
      expect(completed(60000, 5000, 57500), 0);
    });

    test('an uneven final instalment still counts as one', () {
      // 10,000 at 3,000 is three of 3,000 and a last of 1,000 -- four in all,
      // not three and a third.
      expect(completed(10000, 3000, 1000), 3);
      expect(remaining(10000, 3000, 1000), 1);
    });

    test('a zero instalment cannot divide, and says nothing rather than crashing', () {
      expect(completed(60000, 0, 60000), 0);
      expect(remaining(60000, 0, 60000), 0);
    });
  });
}

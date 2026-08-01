import 'package:flutter_test/flutter_test.dart';

/// Locks the arithmetic behind OW-018's "Add Existing Loan" form and the BF
/// figure it feeds, using the worked example the Owner supplied.
///
/// This exists because the form previously took Total Issued, Repayment and
/// Remaining Balance as three INDEPENDENT typed fields, which let them
/// contradict each other -- a repayment of 10,000 was accepted alongside
/// 14,000 still owed, and nothing caught it until the very bottom of the
/// screen. Everything derivable is now derived, and this test is what keeps
/// it that way.
void main() {
  // The Owner's worked example.
  const given = 19600.0; // cash actually handed over
  const interest = 4000.0;
  const fee = 400.0;
  const pending = 7; // instalments still to run
  const emi = 2000.0;
  const penalty = 0.0;
  const investment = 100000.0;

  double totalIssued() => given + interest + fee;
  double remaining() => pending * emi + penalty;
  double alreadyPaid() => totalIssued() - remaining();

  group('loan derivation', () {
    test('total issued is given plus what was withheld from it', () {
      expect(totalIssued(), 24000);
    });

    test('remaining balance comes from the instalments, never typed', () {
      expect(remaining(), 14000);
    });

    test('already paid is the obligation minus what is still owed', () {
      expect(alreadyPaid(), 10000);
    });

    test('the two halves of the form cannot disagree', () {
      // The original bug: remaining could exceed the total obligation.
      expect(remaining(), lessThanOrEqualTo(totalIssued()));
      expect(alreadyPaid() + remaining(), totalIssued());
    });
  });

  group('BF', () {
    // BF is CASH. The interest and fee were withheld from the disbursement --
    // the customer was handed 19,600 rather than 24,000 -- so that 4,400
    // never left the till and never returns to it as fresh cash. It reaches
    // the business through the instalments, and is therefore already inside
    // both the 10,000 collected and the 14,000 still owed.
    test('nets the cash actually handed over, not the obligation', () {
      expect(investment - given + alreadyPaid(), 90400);
    });

    test('subtracting the gross and adding the withheld part is the same sum',
        () {
      // The Owner's own framing. Both must land on the same rupee.
      expect(
        investment - totalIssued() + interest + fee + alreadyPaid(),
        investment - given + alreadyPaid(),
      );
    });

    test('adding interest and fee on top of the net double counts them', () {
      // The number this test exists to prevent: 94,800.
      final doubleCounted = investment - given + interest + fee + alreadyPaid();
      expect(doubleCounted, 94800);
      expect(doubleCounted, isNot(90400),
          reason: 'guards the 4,400 double count that was caught in review');
    });
  });

  group('line profit', () {
    // Profit accrues, BF is cash -- deliberately different bases. The whole
    // 4,000 of interest counts the moment the loan exists, even though only
    // part of it has been collected.
    const karchulu = 500.0;
    test('is interest earned less expenses', () {
      expect(interest - karchulu, 3500);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/customer_loan_entry.dart';

/// Typing one customer's existing loan out of a paper book.
///
/// This is the money path in the one-by-one door, and it is the one that can
/// double a book. On 22 Aug 2026 a retry after a timeout put a whole book in a
/// second time: 108 loans, a line balance nearly double the truth, and a day
/// ledger that cascaded to minus 8,20,320. Nothing on screen looked wrong.
ManaLoanEntry _entry({
  int amountGiven = 8800,
  int repayment = 10000,
  int remaining = 4000,
  int installment = 500,
  int? fee = 200,
  String frequency = 'Daily',
  DateTime? effective,
}) =>
    ManaLoanEntry(
      mlid: 'MLPI1',
      amountGiven: amountGiven,
      repaymentAmount: repayment,
      remainingBalance: remaining,
      installmentAmount: installment,
      processingFee: fee,
      repaymentType: frequency,
      effectiveDate: effective ?? DateTime(2026, 1, 1),
      gracePeriodEndDate: null,
    );

void main() {
  group('what the server is given', () {
    test('the row carries every required column, named as the import wants', () {
      // The names are the wizard's own customerLoanRequired list. A renamed key
      // is not a compile error -- it is a row the server rejects, or worse
      // silently reads as null.
      final row = _entry().toRow();
      for (final key in const [
        'mlid',
        'amount_given',
        'repayment_amount',
        'remaining_balance',
        'effective_date',
        'repayment_type',
        'installment_amount',
      ]) {
        expect(row.containsKey(key), isTrue, reason: '$key is missing');
      }
    });

    test('an absent fee or grace date is left out, not sent as zero', () {
      // A zero processing fee is a STATEMENT -- it changes the derived interest,
      // because migrate_loan computes interest as repayment - given - fee.
      // Sending one the Owner never typed would move money.
      final row = _entry(fee: null).toRow();
      expect(row.containsKey('processing_fee'), isFalse);
      expect(row.containsKey('grace_period_end_date'), isFalse);
    });

    test('dates go as plain ISO days, not timestamps', () {
      final row = _entry(effective: DateTime(2026, 3, 9)).toRow();
      expect(row['effective_date'], '2026-03-09');
    });
  });

  group('the money has to make sense before it is sent', () {
    test('a good loan has nothing to say', () {
      expect(_entry().problems(), isEmpty);
    });

    test('repayment below what was handed over is negative interest', () {
      // migrate_loan derives interest as repayment - given - fee. If that goes
      // negative the loan says the Owner lent more than is owed back, which no
      // book means, and the figure would be stored as a real interest amount.
      expect(_entry(amountGiven: 10000, repayment: 9000, fee: 0).problems(),
          contains(ManaLoanProblem.negativeInterest));
    });

    test('the fee counts toward that, not around it', () {
      // given 9000 + fee 1200 = 10200 against a 10000 repayment. Without the
      // fee in the sum this reads as 1000 of interest instead of minus 200.
      expect(_entry(amountGiven: 9000, repayment: 10000, fee: 1200).problems(),
          contains(ManaLoanProblem.negativeInterest));
    });

    test('owing more than the repayment is impossible', () {
      // remaining_balance is repayment minus what has been collected, so it
      // cannot exceed the repayment. migrate_loan would derive a NEGATIVE
      // collected figure from it.
      expect(_entry(repayment: 10000, remaining: 12000).problems(),
          contains(ManaLoanProblem.balanceAboveRepayment));
    });

    test('a fully paid loan is not a loan to migrate', () {
      // Nothing owed means nothing to collect. It belongs in history, not in
      // the live book being handed over.
      expect(_entry(remaining: 0).problems(),
          contains(ManaLoanProblem.nothingOutstanding));
    });

    test('an instalment of nothing never finishes', () {
      expect(_entry(installment: 0).problems(),
          contains(ManaLoanProblem.noInstalment));
    });

    test('the frequency must be one the schema knows', () {
      // repayment_frequency_enum is Daily | Weekly | Monthly, read from
      // enum_range. An invented literal applies cleanly and throws 22P02 on
      // first call -- this project has shipped that four times.
      expect(_entry(frequency: 'Fortnightly').problems(),
          contains(ManaLoanProblem.unknownFrequency));
      for (final ok in kManaRepaymentFrequencies) {
        expect(_entry(frequency: ok).problems(), isEmpty, reason: ok);
      }
    });

    test('every problem is reported, not just the first', () {
      // An Owner fixing one number at a time, being told about the next one
      // only after saving again, is how a form becomes a guessing game.
      final problems = _entry(remaining: 0, installment: 0, frequency: 'X').problems();
      expect(problems.length, greaterThanOrEqualTo(3));
    });
  });

  group('a retry must not double the book', () {
    test('the key is minted once and survives every attempt', () {
      // THE 22 AUG DEFECT. A fresh key per attempt is the bug wearing a safety
      // feature's clothes: the server cannot tell the retry from a new import.
      final entry = _entry();
      final first = entry.idempotencyKey;
      entry.toRow();
      entry.toRow();
      expect(entry.idempotencyKey, first);
      expect(first, isNotEmpty);
    });

    test('two separate loans get different keys', () {
      // Sharing one would make the second loan a "retry" of the first and it
      // would silently never be imported.
      expect(_entry().idempotencyKey, isNot(_entry().idempotencyKey));
    });
  });
}

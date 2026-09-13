/// One customer's existing loan, typed out of a paper book.
///
/// This is the money path in the one-by-one door, and the one that can double a
/// book. On 22 Aug 2026 a retry after a timeout put a whole book in a second
/// time -- 108 loans, a line balance nearly double the truth, and a day ledger
/// that cascaded to minus 8,20,320 -- and nothing on screen looked wrong.
library;

import '../../../shared/idempotency.dart';

/// The values `repayment_frequency_enum` actually holds.
///
/// Read out of enum_range, not guessed. An invented literal applies perfectly
/// and throws 22P02 on first call; this project has shipped that four times.
const List<String> kManaRepaymentFrequencies = ['Daily', 'Weekly', 'Monthly'];

/// Everything that can be wrong with a typed loan.
///
/// An enum rather than sentences, so the screen can word them and the rules can
/// be tested without pumping one.
enum ManaLoanProblem {
  /// repayment - given - fee is below zero: the book would be saying the Owner
  /// lent more than is owed back.
  negativeInterest,

  /// remaining_balance above the repayment. migrate_loan derives collected as
  /// `repayment - remaining`, so this stores a NEGATIVE amount collected.
  balanceAboveRepayment,

  /// Nothing left to collect. It belongs in history, not in the live book.
  nothingOutstanding,

  /// An instalment of nothing never finishes.
  noInstalment,

  /// Not a value repayment_frequency_enum holds.
  unknownFrequency,
}

/// A loan the Owner has typed, with the key that makes retrying it safe.
class ManaLoanEntry {
  final String mlid;

  /// Cash actually handed over. NOT the generated column of the same name:
  /// app.migrate_loan takes this as an INPUT and derives the interest from it
  /// as `repayment - given - fee`. The Owner types what they gave and what is
  /// owed back; the interest falls out.
  final int amountGiven;

  /// What is owed back in total, interest and fee included.
  final int repaymentAmount;

  /// What is still owed today. This IS repayment minus everything collected --
  /// migrate_loan says so itself: `v_collected := v_repay - v_remain`.
  final int remainingBalance;

  final int installmentAmount;

  /// Optional, and absent is not zero: a zero fee changes the derived interest,
  /// so sending one the Owner never typed moves money.
  final int? processingFee;

  /// Daily, Weekly or Monthly.
  final String repaymentType;

  final DateTime effectiveDate;

  /// A DATE, because that is what a paper ledger records. The day count the
  /// schema stores is derived server-side.
  final DateTime? gracePeriodEndDate;

  /// Minted ONCE, at construction, and reused by every attempt.
  ///
  /// That is the whole contract. submitCustomerLoans is idempotent on this key,
  /// so a retry after a timeout is a no-op rather than a second import. A fresh
  /// key per attempt is the 22 Aug bug wearing a safety feature's clothes: the
  /// server cannot tell the retry from a new import.
  final String idempotencyKey;

  ManaLoanEntry({
    required this.mlid,
    required this.amountGiven,
    required this.repaymentAmount,
    required this.remainingBalance,
    required this.installmentAmount,
    required this.processingFee,
    required this.repaymentType,
    required this.effectiveDate,
    required this.gracePeriodEndDate,
  }) : idempotencyKey = manaIdempotencyKey();

  /// Everything wrong with this loan, not merely the first thing.
  ///
  /// An Owner fixing one number at a time, told about the next only after
  /// saving again, is how a form becomes a guessing game.
  List<ManaLoanProblem> problems() {
    final found = <ManaLoanProblem>[];

    // The fee counts toward the interest, not around it: given 9,000 plus a
    // 1,200 fee against a 10,000 repayment is minus 200 of interest, not
    // 1,000 of it.
    if (repaymentAmount - amountGiven - (processingFee ?? 0) < 0) {
      found.add(ManaLoanProblem.negativeInterest);
    }
    if (remainingBalance > repaymentAmount) {
      found.add(ManaLoanProblem.balanceAboveRepayment);
    }
    if (remainingBalance <= 0) found.add(ManaLoanProblem.nothingOutstanding);
    if (installmentAmount <= 0) found.add(ManaLoanProblem.noInstalment);
    if (!kManaRepaymentFrequencies.contains(repaymentType)) {
      found.add(ManaLoanProblem.unknownFrequency);
    }
    return found;
  }

  /// The row `submitCustomerLoans` takes.
  ///
  /// Keys are the wizard's own customerLoanRequired/Optional names. A renamed
  /// one is not a compile error -- it is a row the server rejects, or worse
  /// reads as null.
  Map<String, dynamic> toRow() => {
        'mlid': mlid,
        'amount_given': amountGiven,
        'repayment_amount': repaymentAmount,
        'remaining_balance': remainingBalance,
        'effective_date': _day(effectiveDate),
        'repayment_type': repaymentType,
        'installment_amount': installmentAmount,
        // Absent, not zero. Both of these change what the server derives.
        if (processingFee != null) 'processing_fee': processingFee,
        if (gracePeriodEndDate != null)
          'grace_period_end_date': _day(gracePeriodEndDate!),
      };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

import '../../../design/components/mana_account_sheet.dart';
import 'record_book_state.dart' show DayLedgerRow;

/// Which lines an account sheet can carry, and which of them are fixed.
///
/// THE OWNER'S ORDER, and their instruction: "actual rows required in account
/// sheet are first BF, then collection (vasool) then loans (karchu),
/// remaining all to be add options."
enum ManaSheetLine {
  /// Always shown, always first. The paper sheet's Brought Forward Cash.
  broughtForward,

  /// Always shown. Vasool -- what came in off the round.
  vasool,

  /// Always shown. Karchu -- what went out as loans.
  karchu,

  /// Vaddi. Adding it re-expresses Karchu; see [manaAccountSheetRows].
  vaddi,

  /// Processing fee. Same: a decomposition of Karchu, not an inflow.
  processingFee,

  investorDeposit,
  investorWithdrawal,
  chetiReceived,
  chetiPaid,
  expenses,
  shortExcess;

  /// Fixed rows cannot be removed.
  bool get isFixed =>
      this == broughtForward || this == vasool || this == karchu;

  /// This line RE-EXPRESSES Karchu rather than moving money of its own.
  ///
  /// The distinction is the whole reason the sheet can be drawn two ways and
  /// still close on the same figure. Vaddi and the processing fee are not
  /// cash arriving -- interest is withheld from the disbursement, confirmed
  /// by the Owner on 2026-09-17 -- so showing them raises Karchu to the face
  /// amount by exactly what they credit back.
  bool get decomposesKarchu => this == vaddi || this == processingFee;
}

/// What a day's loans were made of. From app.day_loan_income.
class ManaDayLoanIncome {
  final int face;
  final int interest;
  final int fee;
  final int net;

  const ManaDayLoanIncome({
    required this.face,
    required this.interest,
    required this.fee,
    required this.net,
  });

  static const zero =
      ManaDayLoanIncome(face: 0, interest: 0, fee: 0, net: 0);
}

/// Build one day's sheet.
///
/// THE RULE THAT MAKES BOTH FORMS SAFE. Karchu is drawn as
///
///     face - (interest, unless Vaddi is shown) - (fee, unless Fee is shown)
///
/// so whichever of the two are on screen, credits minus debits is the same
/// number. With neither shown Karchu is the net cash handed over (4,900 in
/// the Owner's example); with both, it is the face (6,000) with 1,000 and 100
/// credited back. With only one shown it is still exact -- 5,900 against a
/// credit of 1,000 -- which is why the two are independent rather than a
/// single "show loan income" toggle.
///
/// [manaSheetNets] proves it for every combination.
///
/// A ROW CARRYING MONEY IS NEVER HIDDEN. [shown] says which OPTIONAL lines
/// the reader has asked for, and it is honoured for lines that are zero. A
/// line that moved money appears regardless: a sheet that printed a Closing
/// while silently omitting an investor's fifty thousand rupees would be
/// stating a total it had not counted. The only lines exempt are the two that
/// decompose Karchu, because they move nothing.
List<ManaSheetRow> manaAccountSheetRows({
  required DayLedgerRow ledger,
  required ManaDayLoanIncome income,
  required Set<ManaSheetLine> shown,
  required String Function(ManaSheetLine line) label,
  void Function(ManaSheetLine line)? onTap,
}) {
  final showVaddi = shown.contains(ManaSheetLine.vaddi);
  final showFee = shown.contains(ManaSheetLine.processingFee);

  final karchu = income.face -
      (showVaddi ? 0 : income.interest) -
      (showFee ? 0 : income.fee);

  int amountOf(ManaSheetLine line) => switch (line) {
        ManaSheetLine.broughtForward => ledger.openingBalance,
        ManaSheetLine.vasool => ledger.totalCollections,
        ManaSheetLine.karchu => karchu,
        ManaSheetLine.vaddi => income.interest,
        ManaSheetLine.processingFee => income.fee,
        ManaSheetLine.investorDeposit => ledger.investorDeposits,
        ManaSheetLine.investorWithdrawal => ledger.investorWithdrawals,
        ManaSheetLine.chetiReceived => ledger.chetiReceived,
        ManaSheetLine.chetiPaid => ledger.chetiPaid,
        ManaSheetLine.expenses => ledger.totalExpenses,
        // One row, whichever way it fell -- the paper sheet writes
        // "Excess / Sort (If any)" once with the figure on the side it
        // belongs to. Two cells that are always zero together is a row
        // wasted on a 360dp screen.
        ManaSheetLine.shortExcess =>
          ledger.excessAmount > 0 ? ledger.excessAmount : ledger.shortAmount,
      };

  bool isCredit(ManaSheetLine line) => switch (line) {
        ManaSheetLine.broughtForward => true,
        ManaSheetLine.vasool => true,
        ManaSheetLine.vaddi => true,
        ManaSheetLine.processingFee => true,
        ManaSheetLine.investorDeposit => true,
        ManaSheetLine.chetiReceived => true,
        // An excess is cash in hand that the round did not account for, a
        // short is cash missing. Same row, opposite sides.
        ManaSheetLine.shortExcess => ledger.excessAmount > 0,
        ManaSheetLine.karchu => false,
        ManaSheetLine.investorWithdrawal => false,
        ManaSheetLine.chetiPaid => false,
        ManaSheetLine.expenses => false,
      };

  final rows = <ManaSheetRow>[];
  for (final line in ManaSheetLine.values) {
    final amount = amountOf(line);
    final asked = line.isFixed || shown.contains(line);

    if (!asked) {
      // Not asked for. It still appears if it moved money -- unless it is one
      // of the two that only re-express Karchu, which move nothing and whose
      // absence is already accounted for in the Karchu figure above.
      if (line.decomposesKarchu || amount == 0) continue;
    }

    rows.add(ManaSheetRow(
      label: label(line),
      amount: amount,
      isCredit: isCredit(line),
      alwaysWhenNonZero: !line.decomposesKarchu,
      caution: line == ManaSheetLine.shortExcess && amount != 0,
      onTap: onTap == null ? null : () => onTap(line),
    ));
  }
  return rows;
}

/// Credits minus debits, for the rows as drawn.
///
/// Exists so a test can assert the thing the whole design rests on: that this
/// number does not move when Vaddi or the processing fee are shown or hidden.
int manaSheetNets(List<ManaSheetRow> rows) =>
    ManaAccountSheet.creditsOf(rows) - ManaAccountSheet.debitsOf(rows);

/// PENALTY IS DELIBERATELY NOT A LINE, and the reason is worth keeping.
///
/// It was one of the thirteen figures on the old screen, with a comment beside
/// it: "these rupees arrived as part of ordinary collections and are already
/// counted there and in Closing. This line classifies them as penalty income;
/// it is not a separate inflow."
///
/// A wrap of labelled figures can carry that distinction in a comment, because
/// nothing adds the figures up. A two-column sheet adds its columns up. Put
/// penalty in Credits and the day is overstated by exactly the penalties
/// collected -- a double count that would look like a healthy day.
///
/// So it is drawn BESIDE the sheet, as a note on Vasool, by
/// [manaPenaltyNote]. Same information, no arithmetic.
String manaPenaltyNote(DayLedgerRow ledger, String Function(String) t) =>
    ledger.penaltyCollected == 0
        ? ''
        : t('of_which_penalty');

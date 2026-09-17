import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/account_sheet_rows.dart';
import 'package:mana_line/features/owner_workspace/state/record_book_state.dart';

/// The account sheet's arithmetic, which is the whole reason it can be drawn
/// two ways.
///
/// The Owner's instruction, 2026-09-17: "user can select only karchu or
/// karchu+vaddi+processing fees option, for eg. - only karchu selected show
/// 4900, if selected karchu+vaddi+processing fees - 6000,1000,100."
///
/// Interest is WITHHELD, not collected at issue -- confirmed the same day. So
/// showing Vaddi must not add cash that never arrived: it raises Karchu to
/// the face amount by exactly what it credits back, and the day closes on the
/// same figure either way.
DayLedgerRow ledger({
  int opening = 0,
  int collections = 0,
  int loans = 0,
  int deposits = 0,
  int withdrawals = 0,
  int expenses = 0,
  int chetiPaid = 0,
  int chetiReceived = 0,
  int short = 0,
  int excess = 0,
  int penalty = 0,
}) =>
    DayLedgerRow(
      businessDate: DateTime(2026, 9, 17),
      openingBalance: opening,
      totalCollections: collections,
      totalLoanDistribution: loans,
      investorDeposits: deposits,
      investorWithdrawals: withdrawals,
      totalExpenses: expenses,
      chetiPaid: chetiPaid,
      chetiReceived: chetiReceived,
      shortAmount: short,
      excessAmount: excess,
      penaltyCollected: penalty,
      closingBalance: 0,
      status: 'Open',
    );

String label(ManaSheetLine l) => l.name;

void main() {
  // The Owner's own example, and a real day: 17 Sep 2026 on sri
  // satyanarayana business. app.day_loan_income returns exactly these.
  const theirExample =
      ManaDayLoanIncome(face: 6000, interest: 1000, fee: 100, net: 4900);

  List<dynamic> rowsWith(Set<ManaSheetLine> shown, {DayLedgerRow? l}) =>
      manaAccountSheetRows(
        ledger: l ?? ledger(opening: 100, collections: 208700, loans: 4900),
        income: theirExample,
        shown: shown,
        label: label,
      );

  group('Karchu, drawn two ways', () {
    test('neither shown: the net cash handed over', () {
      final rows = rowsWith({});
      final karchu = rows.firstWhere((r) => r.label == 'karchu');
      expect(karchu.amount, 4900, reason: "the Owner's own figure");
      expect(karchu.isCredit, isFalse);
      expect(rows.any((r) => r.label == 'vaddi'), isFalse);
      expect(rows.any((r) => r.label == 'processingFee'), isFalse);
    });

    test('both shown: the face, with the income credited back', () {
      final rows = rowsWith(
          {ManaSheetLine.vaddi, ManaSheetLine.processingFee});
      expect(rows.firstWhere((r) => r.label == 'karchu').amount, 6000);
      final vaddi = rows.firstWhere((r) => r.label == 'vaddi');
      final fee = rows.firstWhere((r) => r.label == 'processingFee');
      expect(vaddi.amount, 1000);
      expect(fee.amount, 100);
      expect(vaddi.isCredit, isTrue,
          reason: 'on the paper sheet Vaddi sits in the credit column');
      expect(fee.isCredit, isTrue);
    });

    test('only Vaddi: still exact, at 5,900 against 1,000', () {
      // This is why the two are independent rather than one toggle. If Karchu
      // jumped to the full face while only Vaddi was credited, the sheet
      // would be out by the fee.
      final rows = rowsWith({ManaSheetLine.vaddi});
      expect(rows.firstWhere((r) => r.label == 'karchu').amount, 5900);
      expect(rows.firstWhere((r) => r.label == 'vaddi').amount, 1000);
    });

    test('THE INVARIANT: the day closes the same, every combination', () {
      // If this ever fails, one of the four forms is inventing or destroying
      // money -- and the one that does it is the one somebody will believe.
      final nets = <String, int>{};
      for (final shown in <Set<ManaSheetLine>>[
        {},
        {ManaSheetLine.vaddi},
        {ManaSheetLine.processingFee},
        {ManaSheetLine.vaddi, ManaSheetLine.processingFee},
      ]) {
        nets[shown.map((e) => e.name).join('+')] =
            manaSheetNets(rowsWith(shown).cast());
      }
      expect(nets.values.toSet(), hasLength(1),
          reason: 'credits minus debits moved when a decomposition row was '
              'shown or hidden: $nets');
      // And it is the right number: 100 + 208700 - 4900.
      expect(nets.values.first, 203900);
    });

    test('the invariant holds when there were no loans at all', () {
      final rows = manaAccountSheetRows(
        ledger: ledger(opening: 500, collections: 1000),
        income: ManaDayLoanIncome.zero,
        shown: {ManaSheetLine.vaddi, ManaSheetLine.processingFee},
        label: label,
      );
      expect(manaSheetNets(rows), 1500);
      expect(rows.firstWhere((r) => r.label == 'karchu').amount, 0);
    });
  });

  group('a row carrying money is never hidden', () {
    test('an investor deposit nobody added still appears', () {
      // The sheet prints a Closing. A Closing that silently omitted fifty
      // thousand rupees would be a total it had not counted.
      final rows = manaAccountSheetRows(
        ledger: ledger(opening: 100, deposits: 50000),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      final dep = rows.firstWhere((r) => r.label == 'investorDeposit');
      expect(dep.amount, 50000);
      expect(dep.isCredit, isTrue);
      expect(manaSheetNets(rows), 50100);
    });

    test('but a zero one stays off until it is added', () {
      final rows = manaAccountSheetRows(
        ledger: ledger(opening: 100),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      expect(rows.any((r) => r.label == 'investorDeposit'), isFalse);
      expect(rows.map((r) => r.label),
          containsAllInOrder(['broughtForward', 'vasool', 'karchu']),
          reason: "the Owner's three, in the Owner's order");
    });

    test('the two decomposition rows are the only ones that may hide money',
        () {
      // They move nothing -- Karchu already accounts for their absence -- so
      // they are exempt. Nothing else is.
      for (final line in ManaSheetLine.values) {
        if (line.isFixed) continue;
        expect(line.decomposesKarchu,
            line == ManaSheetLine.vaddi ||
                line == ManaSheetLine.processingFee);
      }
    });
  });

  group('the three fixed rows', () {
    test('are always drawn, even at zero, in order', () {
      final rows = manaAccountSheetRows(
        ledger: ledger(),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      expect(rows.map((r) => r.label).toList(),
          ['broughtForward', 'vasool', 'karchu']);
    });

    test('cannot be removed by leaving them out of `shown`', () {
      for (final line in ManaSheetLine.values.where((l) => l.isFixed)) {
        expect(
            manaAccountSheetRows(
              ledger: ledger(),
              income: ManaDayLoanIncome.zero,
              shown: const {},
              label: label,
            ).any((r) => r.label == line.name),
            isTrue);
      }
    });
  });

  group('short and excess share one row', () {
    test('an excess is a credit', () {
      final rows = manaAccountSheetRows(
        ledger: ledger(excess: 300),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      final r = rows.firstWhere((e) => e.label == 'shortExcess');
      expect(r.amount, 300);
      expect(r.isCredit, isTrue);
      expect(r.caution, isTrue);
    });

    test('a short is a debit', () {
      final rows = manaAccountSheetRows(
        ledger: ledger(short: 300),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      final r = rows.firstWhere((e) => e.label == 'shortExcess');
      expect(r.amount, 300);
      expect(r.isCredit, isFalse);
    });
  });

  group('penalty is not a line', () {
    test('it never becomes a row, however the sheet is drawn', () {
      // It is already inside collections. In a wrap of figures that could be
      // handled with a comment; in a sheet that ADDS ITS COLUMNS UP it would
      // overstate the day by exactly the penalties collected.
      expect(ManaSheetLine.values.map((e) => e.name),
          isNot(contains('penaltyCollected')));
      final rows = manaAccountSheetRows(
        ledger: ledger(opening: 100, collections: 5000, penalty: 400),
        income: ManaDayLoanIncome.zero,
        shown: const {},
        label: label,
      );
      expect(manaSheetNets(rows), 5100,
          reason: 'the 400 is inside the 5000, so the day is 100 + 5000');
    });
  });
}

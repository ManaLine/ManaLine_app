import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/village_book_summary.dart';

/// Reconciling a village against the paper book it came from.
///
/// The Owner enters a pre-existing book village by village -- 200 customers is
/// not a 200-screen wall, it is a dozen villages of about seventeen -- and
/// after each village checks the app against the page in front of them: how
/// many customers, what is still owed, and how much of that is money nobody
/// has paid in months.
///
/// The Owner's own definition, in their words:
///   Running = total loans given - collections received to date - struck
/// which is the same partition as Total = Running + Struck, because
/// remaining_balance IS repayment minus collections -- app.migrate_loan says
/// so itself: `v_collected := v_repay - v_remain`.
ManaLoanPosition _loan({
  String village = 'Uranduru',
  bool inArea = true,
  String mlid = 'MLPI1',
  String name = 'Ravi',
  int balance = 1000,
  DateTime? lastCollection,
  String loanId = 'loan',
  DateTime? expectedEnd,
}) =>
    ManaLoanPosition(
      personId: mlid,
      mlid: mlid,
      fullName: name,
      village: village,
      inOperatingArea: inArea,
      loanId: loanId.isEmpty ? '' : '$mlid-$loanId',
      balance: balance,
      lastCollection: lastCollection,
      expectedEnd: expectedEnd,
    );

void main() {
  final cutoff = DateTime(2026, 3, 13); // six months before 2026-09-13

  group('the three figures', () {
    test('running and struck always add up to the total', () {
      // THE INVARIANT. A loan that lands in neither bucket, or both, makes the
      // summary quietly wrong about money -- and a confidently wrong number on
      // a money screen is worse than a crash, because nobody notices it.
      final summary = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: DateTime(2026, 9, 1)),
        _loan(mlid: 'MLPI2', balance: 3000, lastCollection: DateTime(2025, 1, 1)),
        _loan(mlid: 'MLPI3', balance: 2000, lastCollection: null),
      ], cutoff: cutoff)
          .single;

      expect(summary.totalBalance, 10000);
      expect(summary.runningBalance + summary.struckBalance, summary.totalBalance);
    });

    test('a loan collected since the cutoff is running', () {
      final s = manaVillageSummaries(
          [_loan(balance: 5000, lastCollection: DateTime(2026, 9, 1))],
          cutoff: cutoff).single;
      expect(s.runningBalance, 5000);
      expect(s.struckBalance, 0);
    });

    test('a loan not collected since the cutoff is struck', () {
      final s = manaVillageSummaries(
          [_loan(balance: 3000, lastCollection: DateTime(2025, 1, 1))],
          cutoff: cutoff).single;
      expect(s.struckBalance, 3000);
      expect(s.runningBalance, 0);
    });

    test('a loan never collected at all is struck, not invisible', () {
      // SUM over an empty filtered set is NULL in Postgres, which is how a
      // rupee figure becomes a blank on screen. Counted as zero here, and the
      // never-collected loan is counted as struck rather than dropped.
      final s = manaVillageSummaries([_loan(balance: 2000, lastCollection: null)],
          cutoff: cutoff).single;
      expect(s.struckBalance, 2000);
      expect(s.runningBalance, 0);
    });

    test('a village with nothing owed reports zeroes, never nulls', () {
      final s = manaVillageSummaries(const [], cutoff: cutoff);
      expect(s, isEmpty, reason: 'no loans means no village rows at all');
    });

    test('collection exactly on the cutoff counts as running', () {
      // "Not recovered in six months" means nothing since that day. A payment
      // ON the day is a payment, and an off-by-one here moves real money into
      // the column an Owner reads as dead.
      final s = manaVillageSummaries(
          [_loan(balance: 1000, lastCollection: cutoff)], cutoff: cutoff).single;
      expect(s.runningBalance, 1000);
      expect(s.struckBalance, 0);
    });
  });

  group('struck is counted at loan level, customers are named', () {
    test('one customer paying one loan and not another is both', () {
      // The Owner was specific: struck is decided per LOAN. Collapsing to a
      // customer total would hide the loan worth chasing.
      final summary = manaVillageSummaries([
        _loan(mlid: 'MLPI1', name: 'Ravi', balance: 4000,
            lastCollection: DateTime(2026, 9, 1)),
        ManaLoanPosition(
          personId: 'MLPI1',
          mlid: 'MLPI1',
          fullName: 'Ravi',
          village: 'Uranduru',
          inOperatingArea: true,
          loanId: 'MLPI1-second',
          balance: 6000,
          lastCollection: DateTime(2024, 1, 1),
          expectedEnd: null,
        ),
      ], cutoff: cutoff)
          .single;

      expect(summary.runningBalance, 4000);
      expect(summary.struckBalance, 6000);
      expect(summary.struckCustomers.map((c) => c.fullName), ['Ravi'],
          reason: 'one person, counted once, however many struck loans');
    });

    test('the struck customers are named so they can be chased', () {
      final summary = manaVillageSummaries([
        _loan(mlid: 'A', name: 'Ravi', balance: 1000, lastCollection: null),
        _loan(mlid: 'B', name: 'Sita', balance: 2000,
            lastCollection: DateTime(2024, 5, 5)),
        _loan(mlid: 'C', name: 'Kumar', balance: 3000,
            lastCollection: DateTime(2026, 9, 1)),
      ], cutoff: cutoff)
          .single;

      expect(summary.struckCustomers, hasLength(2));
      expect(summary.struckCustomers.map((c) => c.fullName).toList(),
          ['Ravi', 'Sita'],
          reason: 'named in the order they are listed, and Kumar is paying');
    });
  });

  group('villages', () {
    test('sorted A to Z, with customer counts', () {
      final summaries = manaVillageSummaries([
        _loan(village: 'Uranduru', mlid: 'A'),
        _loan(village: 'Panagal', mlid: 'B'),
        _loan(village: 'Panagal', mlid: 'C'),
      ], cutoff: cutoff);

      expect(summaries.map((s) => s.village).toList(), ['Panagal', 'Uranduru']);
      expect(summaries.first.customerCount, 2);
      expect(summaries.last.customerCount, 1);
    });

    test('a customer outside every operating area is grouped, not hidden', () {
      // With 200 customers, silently dropping one is how somebody goes missing
      // from their own book. The group is also the app saying an operating
      // area is absent.
      final summaries = manaVillageSummaries([
        _loan(village: 'Uranduru', mlid: 'A'),
        _loan(village: 'Nowhere', mlid: 'B', inArea: false),
      ], cutoff: cutoff);

      expect(summaries, hasLength(2));
      expect(summaries.last.inOperatingArea, isFalse,
          reason: 'the out-of-area group sorts last, after the worked ones');
      expect(summaries.last.village, 'Nowhere');
    });

    test('a customer with no address at all still appears', () {
      // village NULL from the RPC. Dropping the row would lose a real loan.
      final summaries = manaVillageSummaries(
          [_loan(village: '', mlid: 'A', inArea: false)],
          cutoff: cutoff);
      expect(summaries, hasLength(1));
      expect(summaries.single.customerCount, 1);
    });
  });

  group('the cutoff', () {
    test('the offered spans are the ones the Owner asked for', () {
      expect(kManaStruckMonthOptions, [3, 6, 9, 12, 24, 36]);
      expect(kManaStruckDefaultMonths, 6);
    });
  });

  group('a customer with no loan yet', () {
    test('is counted in the village but owes nothing', () {
      // The RPC returns them so their village shows a head count and the Owner
      // has a way IN to enter them. Nine such people were invisible in the
      // first real book this ran against.
      final s = manaVillageSummaries([
        _loan(mlid: 'A', balance: 4000, lastCollection: DateTime(2026, 9, 1)),
        _loan(mlid: 'B', balance: 0, loanId: ''),
      ], cutoff: DateTime(2026, 3, 13))
          .single;

      expect(s.customerCount, 2, reason: 'they are in the village');
      expect(s.totalBalance, 4000);
    });

    test('is never named among the struck', () {
      // Their lastCollection is null by definition. Without the hasLoan guard
      // they would be listed as somebody who stopped paying -- for a loan that
      // does not exist.
      final s = manaVillageSummaries([
        _loan(mlid: 'B', balance: 0, loanId: ''),
      ], cutoff: DateTime(2026, 3, 13))
          .single;

      expect(s.struckCustomers, isEmpty,
          reason: 'nobody has stopped paying a loan nobody has entered');
      expect(s.struckBalance, 0);
      expect(s.runningBalance, 0);
    });
  });

  group('a migrated loan with no collections at all', () {
    // app.migrate_loan writes the instalment schedule but NO collections -- it
    // will not fabricate money into day_ledger on days it never arrived. So
    // every loan typed in balance-only has a null last-collection, and the
    // plain rule "nothing since the cutoff" would call an entire freshly
    // entered book dead.
    //
    // The Owner's answer: infer activity from the loan's own dates. The
    // yardstick is its OWN term, not a fixed window -- a monthly loan eighteen
    // months into a two-year term is healthy, and a fixed six months would
    // have called it struck.

    test('a loan past its due date is struck', () {
      // 12 weeks given 18 months ago: due 15 months ago, still carrying a
      // balance. Nobody has to guess -- it should have finished.
      final s = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: null,
            expectedEnd: DateTime(2025, 6, 1)),
      ], cutoff: cutoff).single;
      expect(s.struckBalance, 5000);
    });

    test('a loan still inside its term is running', () {
      // THE CASE A FIXED WINDOW GETS WRONG. 24 months given 18 months ago:
      // due six months from now, three-quarters paid, perfectly healthy.
      final s = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: null,
            expectedEnd: DateTime(2027, 3, 1)),
      ], cutoff: cutoff).single;
      expect(s.runningBalance, 5000);
      expect(s.struckBalance, 0);
    });

    test('a real collection always beats the estimate', () {
      // Once anything is collected in the app the guess stops mattering. Here
      // the loan is long overdue by its terms but was paid last week.
      final s = manaVillageSummaries([
        _loan(balance: 5000,
            lastCollection: DateTime(2026, 9, 8),
            expectedEnd: DateTime(2024, 1, 1)),
      ], cutoff: cutoff).single;
      expect(s.runningBalance, 5000, reason: 'they paid; the estimate is moot');
    });

    test('no collections and no due date is struck, not invisible', () {
      // installment_amount missing or zero, so the server returned no date
      // rather than dividing by zero. Nothing is known -- and an unknown loan
      // belongs in front of the Owner, not quietly in Running.
      final s = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: null, expectedEnd: null),
      ], cutoff: cutoff).single;
      expect(s.struckBalance, 5000);
    });

    test('a village says when its struck figure is an estimate', () {
      // A struck total from loan terms is a good guess; one from collections
      // is a fact. Reading a guess as a fact is how somebody knocks on the
      // wrong door.
      final estimated = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: null,
            expectedEnd: DateTime(2025, 6, 1)),
      ], cutoff: cutoff).single;
      expect(estimated.struckIsEstimated, isTrue);

      final known = manaVillageSummaries([
        _loan(balance: 5000, lastCollection: DateTime(2024, 1, 1)),
      ], cutoff: cutoff).single;
      expect(known.struckIsEstimated, isFalse);
    });
  });
}

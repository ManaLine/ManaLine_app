/// Reconciling a pre-existing book against the paper it came from, one village
/// at a time.
///
/// The Owner enters a book village by village, because 200 customers is not a
/// 200-screen wall -- it is a dozen villages of about seventeen, one sitting
/// each. After each village they check the app against the page in front of
/// them: how many customers, what is still owed, and how much of that is money
/// nobody has paid in months.
library;

/// The spans the Owner asked to choose between when deciding what counts as
/// money that has stopped moving.
const List<int> kManaStruckMonthOptions = [3, 6, 9, 12, 24, 36];

/// Six months, the Owner's default.
const int kManaStruckDefaultMonths = 6;

/// One live loan, as `app.migration_customer_positions` returns it.
///
/// Per LOAN, not per customer, because the Owner was specific that struck is
/// decided at loan level: one person can be paying one loan and have stopped
/// paying another, and collapsing them to a customer total would hide exactly
/// the loan worth chasing.
class ManaLoanPosition {
  final String personId;
  final String mlid;
  final String fullName;

  /// The village of the person's CURRENT address. Empty when they have no
  /// address on file -- a real state, and not a reason to drop the loan.
  final String village;

  /// Whether that village is one this business works.
  ///
  /// Answered by the server rather than by matching names on the phone:
  /// operatingVillages() formats them for display as "Uranduru (517640)", and
  /// parsing a display string back into data is how a spelling variant quietly
  /// becomes a different village.
  final bool inOperatingArea;

  /// Empty when this customer has no live loan yet -- the RPC returns them as
  /// a row so their village can show a head count and the Owner has a way in
  /// to enter them. Nine such people were invisible in the first real book
  /// this was run against.
  final String loanId;

  /// Whether there is a loan here at all.
  bool get hasLoan => loanId.isNotEmpty;

  /// What is still owed. remaining_balance IS repayment minus collections --
  /// app.migrate_loan says so itself: `v_collected := v_repay - v_remain`.
  final int balance;

  /// The last day anything was collected against this loan. Null when nothing
  /// ever has been -- which is the NORMAL state of a freshly migrated loan,
  /// because app.migrate_loan writes the instalment schedule and no
  /// collections. It will not fabricate money into day_ledger on days it never
  /// arrived.
  final DateTime? lastCollection;

  /// When this loan was due to finish, from its own terms.
  ///
  /// The yardstick for a loan with no collection history. The Owner's rule,
  /// refined: comparing the GIVEN date against a fixed six months is right for
  /// a twelve-week loan and wrong for a twenty-four-month one -- a monthly loan
  /// eighteen months into a two-year term is healthy, and a fixed window would
  /// call it dead. Its own term is the honest measure.
  ///
  /// Null when the instalment is missing or zero: the server returns no date
  /// rather than dividing by zero and dressing the result up as one.
  final DateTime? expectedEnd;

  const ManaLoanPosition({
    required this.personId,
    required this.mlid,
    required this.fullName,
    required this.village,
    required this.inOperatingArea,
    required this.loanId,
    required this.balance,
    required this.lastCollection,
    this.expectedEnd,
  });

  /// True when nothing has ever been collected, so any verdict about this loan
  /// is inferred from its dates rather than read from its history.
  bool get isEstimated => hasLoan && lastCollection == null;

  /// Nothing since the cutoff, or nothing ever.
  ///
  /// A collection ON the cutoff day counts as running. "Not recovered in six
  /// months" means nothing since that day, and an off-by-one here moves real
  /// money into the column an Owner reads as dead.
  ///
  /// A customer with NO loan is never struck. Their lastCollection is null by
  /// definition, so without this they would be named among the people who have
  /// stopped paying -- for a loan that does not exist. They have not stopped
  /// paying anything; nobody has typed their loan in yet.
  /// A REAL COLLECTION ALWAYS WINS. Once anything has been collected in the
  /// app the estimate stops mattering, which is what makes this self-correcting
  /// -- the first collection an Owner records replaces the guess for good.
  ///
  /// With no collections, the loan's own due date stands in: past it and still
  /// carrying a balance means it should have finished and has not. A loan
  /// younger than the cutoff is provably running rather than guessed so --
  /// it cannot have gone six months unpaid when it has existed for two.
  ///
  /// No collections AND no due date is struck. Nothing is known, and an unknown
  /// loan belongs in front of the Owner rather than quietly in Running.
  bool isStruck(DateTime cutoff) {
    if (!hasLoan) return false;
    if (lastCollection != null) return lastCollection!.isBefore(cutoff);
    if (expectedEnd == null) return true;
    return expectedEnd!.isBefore(DateTime.now());
  }
}

/// A person with at least one struck loan, named so they can be chased.
class ManaStruckCustomer {
  final String mlid;
  final String fullName;
  final int struckBalance;
  const ManaStruckCustomer({
    required this.mlid,
    required this.fullName,
    required this.struckBalance,
  });
}

/// One village's position, as the Owner reconciles it.
class ManaVillageSummary {
  final String village;
  final bool inOperatingArea;

  /// Distinct people, not loans. The Owner counts heads against the page.
  final int customerCount;

  final int totalBalance;

  /// Still being paid: the Owner's "total given − collected − struck", which
  /// is the same thing as total minus struck, because remaining_balance has
  /// already had the collections taken off it.
  final int runningBalance;

  final int struckBalance;

  /// Who the struck money belongs to. Named rather than counted, because a
  /// figure an Owner cannot act on is a figure they will ignore.
  final List<ManaStruckCustomer> struckCustomers;

  /// True when any struck loan here was judged by its due date rather than by
  /// its collection history.
  ///
  /// A struck total from loan terms is a good estimate; one from collections is
  /// a fact. The screen has to be able to say which, because reading an
  /// estimate as a fact is how somebody knocks on the wrong door.
  final bool struckIsEstimated;

  const ManaVillageSummary({
    required this.village,
    required this.inOperatingArea,
    required this.customerCount,
    required this.totalBalance,
    required this.runningBalance,
    required this.struckBalance,
    required this.struckCustomers,
    required this.struckIsEstimated,
  });
}

/// Groups live loans into villages and works out what each one is carrying.
///
/// RUNNING + STRUCK ALWAYS EQUALS TOTAL, and that is asserted rather than
/// intended: a loan landing in neither bucket, or both, makes the summary
/// quietly wrong about money -- and a confidently wrong number on a money
/// screen is worse than a crash, because nobody notices it.
///
/// Villages this business works come first, A to Z; everything else follows in
/// its own group. A customer in an unworked village must be VISIBLE -- with two
/// hundred of them, silently dropping one is how somebody goes missing from
/// their own book, and the group is also the app saying an operating area is
/// absent.
List<ManaVillageSummary> manaVillageSummaries(
  List<ManaLoanPosition> loans, {
  required DateTime cutoff,
}) {
  final byVillage = <String, List<ManaLoanPosition>>{};
  for (final loan in loans) {
    // Keyed on the area flag too: the same village name could in principle
    // appear both worked and not, and merging them would put money in a group
    // the Owner does not work.
    byVillage.putIfAbsent('${loan.inOperatingArea}|${loan.village}', () => []).add(loan);
  }

  final summaries = <ManaVillageSummary>[];
  byVillage.forEach((_, group) {
    final struck = group.where((l) => l.isStruck(cutoff)).toList();
    final total = group.fold<int>(0, (sum, l) => sum + l.balance);
    final struckTotal = struck.fold<int>(0, (sum, l) => sum + l.balance);

    // One entry per person, however many struck loans they hold.
    final byPerson = <String, ManaStruckCustomer>{};
    for (final loan in struck) {
      final existing = byPerson[loan.personId];
      byPerson[loan.personId] = ManaStruckCustomer(
        mlid: loan.mlid,
        fullName: loan.fullName,
        struckBalance: (existing?.struckBalance ?? 0) + loan.balance,
      );
    }

    final summary = ManaVillageSummary(
      village: group.first.village,
      inOperatingArea: group.first.inOperatingArea,
      customerCount: group.map((l) => l.personId).toSet().length,
      totalBalance: total,
      runningBalance: total - struckTotal,
      struckBalance: struckTotal,
      struckCustomers: byPerson.values.toList(),
      struckIsEstimated: struck.any((l) => l.isEstimated),
    );

    // The invariant, checked where it is computed rather than trusted.
    assert(
      summary.runningBalance + summary.struckBalance == summary.totalBalance,
      'village ${summary.village}: running ${summary.runningBalance} + struck '
      '${summary.struckBalance} != total ${summary.totalBalance}',
    );
    summaries.add(summary);
  });

  summaries.sort((a, b) {
    // Worked villages first, then the out-of-area group.
    if (a.inOperatingArea != b.inOperatingArea) {
      return a.inOperatingArea ? -1 : 1;
    }
    return a.village.toLowerCase().compareTo(b.village.toLowerCase());
  });
  return summaries;
}

/// The day before which a loan counts as struck.
///
/// Months back from today, using DateTime's own month arithmetic so a cutoff
/// six months before the 31st lands on a real date rather than rolling.
DateTime manaStruckCutoff({required int months, DateTime? from}) {
  final today = from ?? DateTime.now();
  return DateTime(today.year, today.month - months, today.day);
}

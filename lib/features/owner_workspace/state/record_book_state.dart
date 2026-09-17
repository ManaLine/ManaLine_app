import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_sheet_rows.dart' show ManaDayLoanIncome;

/// OW-009 Daily Record Book — real Supabase wiring over Module 8 §8.2
/// (day_ledger). `day_ledger` is system-derived and never directly written
/// by any client call except `remarks` (BR-097, and confirmed here: that
/// column genuinely exists and is nullable/TEXT, unlike the gap found in
/// loan_details_state.dart's loans table this session). Day-detail's
/// sub-entry rows (collections/loans/expenses/deposits/withdrawals) are
/// fetched as real, minimal per-table queries scoped to business_date —
/// full native rows belong to their own owning screens (OW-006/OW-007/
/// etc.), matching the stub's own "no dedicated write endpoint" note.
class RecordBookApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<DayLedgerRow>> fetchLedgerRows({
    required String businessId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
  }) async {
    var q = _db.from('day_ledger').select().eq('business_id', businessId);
    if (dateFrom != null) q = q.gte('business_date', manaIsoDate(dateFrom));
    if (dateTo != null) q = q.lte('business_date', manaIsoDate(dateTo));
    if (status != null) q = q.eq('status', status);
    // PERF: the ledger rows and the penalty totals are independent, so both
    // go out together instead of one waiting on the other.
    final results = await Future.wait<dynamic>([
      q.order('business_date', ascending: false),
      _penaltyByDay(businessId: businessId, from: dateFrom, to: dateTo),
    ]);
    final rows = results[0] as List;
    final penalties = results[1] as Map<String, int>;
    return rows.map((r) => _rowFromMap(r as Map<String, dynamic>, penalties)).toList();
  }

  /// What each day's loans were made of, keyed by ISO business date.
  ///
  /// SEPARATE FROM THE LEDGER ROW, deliberately. day_ledger holds the NET
  /// cash a day's loans cost (total_loan_distribution, the sum of
  /// amount_given); this is the decomposition of that same figure into face,
  /// interest and fee. Folding it into DayLedgerRow would put interest beside
  /// the cash columns, which is the shape that invites somebody to add it to
  /// one -- the double count CLAUDE.md keeps a test against.
  ///
  /// Days with no loans are simply absent, and read as zero.
  Future<Map<String, ManaDayLoanIncome>> fetchLoanIncome({
    required String businessId,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _db.schema('app').rpc('day_loan_income', params: {
      'p_business_id': businessId,
      // A null range would be a NULL comparison in BETWEEN, which matches
      // nothing. The defaults cover any book this app will hold.
      'p_from': manaIsoDate(from ?? DateTime(2000)),
      'p_to': manaIsoDate(to ?? DateTime(2099)),
    });
    final out = <String, ManaDayLoanIncome>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      out[r['business_date'] as String] = ManaDayLoanIncome(
        face: (r['face'] as num?)?.round() ?? 0,
        interest: (r['interest'] as num?)?.round() ?? 0,
        fee: (r['fee'] as num?)?.round() ?? 0,
        net: (r['net'] as num?)?.round() ?? 0,
      );
    }
    return out;
  }

  /// The ISO dates this book actually did something on.
  ///
  /// THE OWNER'S RULE, 2026-09-17: "show only submitted accounts (with any of
  /// these - an active collection or loan or an expense)". Before this, OW-009
  /// listed every `day_ledger` row, and `day_ledger` has a row for every day
  /// its recompute trigger has ever touched -- 82 rows across the five live
  /// books, of which 20 are accounts and 62 are empty days. Three whole books
  /// showed nothing else.
  ///
  /// SERVER-SIDE, not a filter over the rows already in hand. The rule is
  /// "a source row exists", and a day can have a live collection while every
  /// figure on it reads zero -- a no-payment visit is a day somebody worked.
  /// Deciding it from the ledger's own totals would hide exactly that day.
  /// app.active_account_dates carries the full rule, including the migrated
  /// weekly accounts that have money but no source rows behind them.
  Future<Set<String>> fetchActiveDates({
    required String businessId,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _db.schema('app').rpc('active_account_dates', params: {
      'p_business_id': businessId,
      'p_from': from == null ? null : manaIsoDate(from),
      'p_to': to == null ? null : manaIsoDate(to),
    });
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['business_date'] as String,
    };
  }

  /// Recognised penalty totals keyed by ISO business date. One call for the
  /// whole range rather than per row — the RPC returns only days that
  /// actually have penalties, so absent days read as zero.
  Future<Map<String, int>> _penaltyByDay({
    required String businessId,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _db.schema('app').rpc('penalty_collected_by_day', params: {
      'p_business_id': businessId,
      'p_from': from == null ? null : manaIsoDate(from),
      'p_to': to == null ? null : manaIsoDate(to),
    });
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['business_date'] as String: (r['penalty_collected'] as num).toInt(),
    };
  }

  DayLedgerRow _rowFromMap(Map<String, dynamic> r, [Map<String, int> penalties = const {}]) => DayLedgerRow(
        businessDate: DateTime.parse(r['business_date'] as String),
        openingBalance: (r['opening_balance'] as num).toInt(),
        totalCollections: (r['total_collections'] as num).toInt(),
        totalLoanDistribution: (r['total_loan_distribution'] as num).toInt(),
        investorDeposits: (r['investor_deposits'] as num).toInt(),
        investorWithdrawals: (r['investor_withdrawals'] as num).toInt(),
        totalExpenses: (r['total_expenses'] as num).toInt(),
        // Default to 0 rather than a hard cast: these two columns were added
        // in migration 20260801192125, after the 4 existing ledger rows.
        chetiPaid: (r['cheti_paid'] as num?)?.toInt() ?? 0,
        chetiReceived: (r['cheti_received'] as num?)?.toInt() ?? 0,
        shortAmount: (r['short_amount'] as num).toInt(),
        excessAmount: (r['excess_amount'] as num).toInt(),
        closingBalance: (r['closing_balance'] as num).toInt(),
        status: r['status'] as String,
        remarks: r['remarks'] as String?,
        penaltyCollected: penalties[r['business_date'] as String] ?? 0,
      );

  Future<DayDetail> fetchDayDetail({
    required String businessId,
    required DateTime businessDate,
  }) async {
    final date = manaIsoDate(businessDate);

    // PERF: all six reads are scoped to the same business and date and none
    // depends on another, so they go out as one batch instead of six
    // sequential round trips. Future.wait (not record `.wait`) so a failure
    // propagates the original PostgrestException — NetworkErrorHandler
    // wouldn't recognise a ParallelWaitError as server-reached and would
    // replace the real message with a generic one.
    final results = await Future.wait<dynamic>([
      _db.from('day_ledger').select().eq('business_id', businessId).eq('business_date', date).single(),
      _db
          .from('collections')
          // WHO PAID, not just that somebody did. collections carries its
          // own customer_id -- a single FK, so `customers(...)` needs no FK
          // name -- which is a shorter and more reliable path than reaching
          // through the loan. `customers` has one FK to persons, and persons
          // to person_addresses, so nothing here is one of the eleven
          // ambiguous pairs ambiguous_embed_guard_test lists.
          .select('''
            collection_id, collected_amount, entry_timestamp, loan_id,
            loans!inner(business_id),
            customers(persons!inner(full_name, father_husband_name,
              person_addresses(is_current, locations(village_town_name))))
          ''')
          .eq('business_date', date)
          .eq('loans.business_id', businessId)
          // 612 of 862 collections on the live book are soft-deleted. A day's
          // record book that counts them shows money that was taken back.
          .isFilter('deleted_at', null),
      _db
          .from('loans')
          // WHO IT WENT TO. loans has one FK to customers.
          .select('''
            loan_id, repayment_amount, entry_timestamp,
            customers(persons!inner(full_name, father_husband_name,
              person_addresses(is_current, locations(village_town_name))))
          ''')
          .eq('business_id', businessId)
          .eq('issue_business_date', date)
          .isFilter('deleted_at', null),
      _db
          .from('expenses')
          // WHO RECORDED IT. An expense has no customer -- fuel and tea are
          // not owed by anybody -- so the person who identifies it is the
          // member who entered it. expenses has TWO FKs to business_members
          // (recorded_by and deleted_by), so the FK is named or PostgREST
          // answers PGRST201 and the tab just says it could not load.
          .select('''
            expense_id, amount, entry_timestamp, category,
            business_members!expenses_recorded_by_membership_id_fkey(
              persons(full_name))
          ''')
          .eq('business_id', businessId)
          .eq('business_date', date),
      _db
          .from('settlement_adjustments')
          .select('adjustment_id, amount, business_date, adjustment_type, '
              'account_settlements!inner(account_periods!inner(business_id))')
          .eq('business_date', date)
          .eq('account_settlements.account_periods.business_id', businessId),
      _penaltyByDay(businessId: businessId, from: businessDate, to: businessDate),
    ]);

    final ledgerRow = results[0] as Map<String, dynamic>;
    final collectionRows = results[1] as List;
    final loanRows = results[2] as List;
    final expenseRows = results[3] as List;
    final adjustmentRows = results[4] as List;
    final penalties = results[5] as Map<String, int>;

    return DayDetail(
      ledger: _rowFromMap(ledgerRow, penalties),
      collections: collectionRows.cast<Map<String, dynamic>>().map((c) {
        final who = _identity(c['customers']);
        return DayDetailEntry(
          id: c['collection_id'] as String,
          label: 'Collection',
          amount: (c['collected_amount'] as num).toInt(),
          timestamp: DateTime.parse(c['entry_timestamp'] as String),
          sourceLoanId: c['loan_id'] as String?,
          personName: who?.name,
          careOf: who?.careOf,
          village: who?.village,
        );
      }).toList(),
      loans: loanRows.cast<Map<String, dynamic>>().map((l) {
        final who = _identity(l['customers']);
        return DayDetailEntry(
          id: l['loan_id'] as String,
          label: 'Loan Distribution',
          amount: (l['repayment_amount'] as num).toInt(),
          timestamp: DateTime.parse(l['entry_timestamp'] as String),
          sourceLoanId: l['loan_id'] as String,
          personName: who?.name,
          careOf: who?.careOf,
          village: who?.village,
        );
      }).toList(),
      expenses: expenseRows.cast<Map<String, dynamic>>().map((e) {
        // No C/o and no village: this names the member who recorded the
        // expense, not a customer, and a colleague's father's name is not
        // what identifies a fuel bill.
        final member = e['business_members'] as Map<String, dynamic>?;
        final person = member?['persons'] as Map<String, dynamic>?;
        return DayDetailEntry(
          id: e['expense_id'] as String,
          label: e['category'] as String? ?? 'Expense',
          amount: (e['amount'] as num).toInt(),
          timestamp: DateTime.parse(e['entry_timestamp'] as String),
          personName: person?['full_name'] as String?,
        );
      }).toList(),
      deposits: const [], // requires an investments query scoped to business_date — not fetched by this summary view
      withdrawals: const [], // requires an investment_withdrawals query scoped to business_date — not fetched by this summary view
      adjustments: adjustmentRows.cast<Map<String, dynamic>>().map((a) => DayDetailEntry(
            id: a['adjustment_id'] as String,
            label: a['adjustment_type'] as String? ?? 'Adjustment',
            amount: (a['amount'] as num).toInt(),
            timestamp: DateTime.parse(a['business_date'] as String),
            isCorrection: true,
          )).toList(),
      auditLog: const [], // BR-124/158 admin/security only — requires a dedicated audit_log query, not fetched by this summary view
    );
  }

  /// Name, C/o and village out of an embedded `customers` row.
  ///
  /// ONE READER FOR BOTH PATHS. Collections and loans reach a customer by
  /// different foreign keys but unwrap identically, and CLAUDE.md's rule about
  /// shared contracts cuts both ways: two copies of this is how the loans tab
  /// comes to show a village the collections tab does not.
  ///
  /// The current address, or the first one if none is flagged current -- the
  /// same fallback agent_customer_state.dart uses, and for the same reason: a
  /// person whose address rows predate the is_current flag still lives
  /// somewhere, and showing no village is worse than showing an old one.
  static _Identity? _identity(dynamic customer) {
    final c = customer as Map<String, dynamic>?;
    final person = c?['persons'] as Map<String, dynamic>?;
    if (person == null) return null;
    final addresses = (person['person_addresses'] as List?) ?? const [];
    final current = addresses.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a?['is_current'] == true,
          orElse: () =>
              addresses.isNotEmpty ? addresses.first as Map<String, dynamic> : null,
        );
    return _Identity(
      name: person['full_name'] as String?,
      careOf: person['father_husband_name'] as String?,
      village: (current?['locations'] as Map<String, dynamic>?)?['village_town_name']
          as String?,
    );
  }

  Future<void> updateRemarks({
    required String businessId,
    required DateTime businessDate,
    required String remarks,
  }) async {
    await _db
        .from('day_ledger')
        .update({'remarks': remarks})
        .eq('business_id', businessId)
        .eq('business_date', manaIsoDate(businessDate));
  }
}

/// The key day_ledger and app.day_loan_income are both keyed by.
///
/// Public because the screen matches a ledger row to its loan decomposition
/// with it, and two copies of a date format is how two maps come to disagree
/// about which day it is.
String manaIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One row per Business Date, per BR-094 (`day_ledger` UNIQUE(business_id,
/// business_date)). Field names map 1:1 to `day_ledger` columns per
/// 03_Database_Schema.md §8.2.
class DayLedgerRow {
  final DateTime businessDate;
  final int openingBalance; // BF Cash
  final int totalCollections;
  final int totalLoanDistribution;
  final int investorDeposits;
  final int investorWithdrawals;
  final int totalExpenses;

  /// Cheti instalments handed over on this business day — a BF outflow that is
  /// not a loan, an expense or an investor withdrawal, so none of the columns
  /// above can hold it. Without this, closing balance drifts by the instalment
  /// every period a cheti runs.
  ///
  /// This is CASH MOVED, not the cheti's worth. A cheti is an asset (the money
  /// comes back as a lumpsum), and its standing value is `netPosition` on the
  /// Cheti model, shown separately beside LB. Booking it as an expense — as
  /// BR-061 originally said — would sink line profit every period and then
  /// show one phantom gain at availing.
  final int chetiPaid;

  /// The lumpsum availed on this business day. A BF inflow that is neither a
  /// collection nor an investor deposit.
  final int chetiReceived;

  final int shortAmount;
  final int excessAmount;
  final int closingBalance;
  final String status; // Open | Closed
  final String? remarks;
  /// Penalty income recognised on this business day — penalties on loans
  /// that were closed today having already been paid down to zero.
  ///
  /// NOT part of closingBalance and NOT subtracted out of totalCollections:
  /// those penalty rupees physically arrived inside ordinary collections and
  /// are already counted once in the cash flow that reconciles against
  /// day_closures. This is a classification of money already in the ledger,
  /// not an extra inflow — adding it to any total would double-count it.
  ///
  /// Sourced from `app.penalty_collected_by_day`, which sums
  /// penalty_entries.recognised_business_date. It is deliberately not a
  /// day_ledger column: nothing in this codebase inserts day_ledger rows, so
  /// a penalty recognised on a day with no ledger row would have had nowhere
  /// to live. See migration 0055's header.
  final int penaltyCollected;

  DayLedgerRow({
    required this.businessDate,
    required this.openingBalance,
    required this.totalCollections,
    required this.totalLoanDistribution,
    required this.investorDeposits,
    required this.investorWithdrawals,
    required this.totalExpenses,
    required this.shortAmount,
    required this.excessAmount,
    required this.closingBalance,
    required this.status,
    this.chetiPaid = 0,
    this.chetiReceived = 0,
    this.remarks,
    this.penaltyCollected = 0,
  });

  int get difference => excessAmount - shortAmount;

  bool get isClosed => status == 'Closed';
}

class DayDetail {
  final DayLedgerRow ledger;
  final List<DayDetailEntry> collections;
  final List<DayDetailEntry> loans;
  final List<DayDetailEntry> expenses;
  final List<DayDetailEntry> deposits;
  final List<DayDetailEntry> withdrawals;
  final List<DayDetailEntry> adjustments;
  final List<AuditLogEntry> auditLog;

  DayDetail({
    required this.ledger,
    this.collections = const [],
    this.loans = const [],
    this.expenses = const [],
    this.deposits = const [],
    this.withdrawals = const [],
    this.adjustments = const [],
    this.auditLog = const [],
  });

  List<DayDetailEntry> get timeline {
    final all = [
      ...collections,
      ...loans,
      ...expenses,
      ...deposits,
      ...withdrawals,
      ...adjustments,
    ];
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return all;
  }
}

class DayDetailEntry {
  final String id;

  /// What KIND of entry this is -- 'Collection', an expense's category, an
  /// adjustment's type. Never who it was with; that is [personName].
  final String label;

  final int amount;
  final DateTime timestamp;
  final bool isCorrection;
  final String? sourceLoanId;

  /// WHO. Reported from a handset, 2026-09-17: "in screenshot it's showing
  /// collection but it should at least show name, c/o, village along with
  /// date & time to identify from whom collected from and same applies to
  /// others too loans, expenses, timeline."
  ///
  /// A day's collections used to read "Collection, Collection, Collection"
  /// down the sheet with an amount beside each. An Owner checking an agent's
  /// day could see that eleven payments came in and nothing about whose they
  /// were -- so the one question the screen exists to answer, "is this
  /// right?", could not be asked of it.
  ///
  /// NULL, NOT EMPTY, when there is no person: an expense has a category and
  /// a payee, not a customer. Empty string would draw a blank line where the
  /// name goes and read as a missing name rather than an entry that never had
  /// one.
  final String? personName;

  /// C/o -- the father or husband name. Two people in one village share a
  /// given name often enough that this is how the book tells them apart, and
  /// it is why persons has the column NOT NULL.
  final String? careOf;

  /// The village, which is the third part of the same answer: a name and a
  /// C/o still collide across villages on a line that works several.
  final String? village;

  DayDetailEntry({
    required this.id,
    required this.label,
    required this.amount,
    required this.timestamp,
    this.isCorrection = false,
    this.sourceLoanId,
    this.personName,
    this.careOf,
    this.village,
  });
}

class _Identity {
  final String? name;
  final String? careOf;
  final String? village;
  const _Identity({this.name, this.careOf, this.village});
}

class AuditLogEntry {
  final String auditId;
  final String actionType;
  final String entityType;
  final String entityId;
  final DateTime entryTimestamp;

  AuditLogEntry({
    required this.auditId,
    required this.actionType,
    required this.entityType,
    required this.entityId,
    required this.entryTimestamp,
  });
}

final recordBookApiServiceProvider = Provider<RecordBookApiService>((ref) {
  return RecordBookApiService();
});

class RecordBookState {
  final List<DayLedgerRow> rows;

  /// Each day's loans broken into face, interest and fee, keyed by ISO date.
  ///
  /// EMPTY IS NOT ZERO. An empty map means the decomposition was not
  /// fetched -- or could not be -- and the sheet then draws Karchu as the
  /// ledger's net figure and offers neither Vaddi nor the fee, because it
  /// does not know them. A day that genuinely had no loans is absent from a
  /// map that HAS been fetched, which reads as zero and is correct.
  final Map<String, ManaDayLoanIncome> loanIncome;

  /// Every ISO date this book has an account on, for the WHOLE book.
  ///
  /// NOT DERIVED FROM `rows`, deliberately, and this is the second attempt.
  /// Deriving it looked airtight -- the calendar could then only ever offer a
  /// day the list holds -- until picking a date narrows the loaded window to
  /// that day, at which point the calendar would shrink to a single
  /// selectable date and the Owner would be stranded on it. So this is
  /// fetched with no range and left alone while the window moves.
  final Set<String> activeDates;

  final bool loading;
  final String? error;
  final String? statusFilter;

  final DateTime? selectedDate;
  final DayDetail? dayDetail;
  final bool detailLoading;
  final String? detailError;

  const RecordBookState({
    this.rows = const [],
    this.loanIncome = const {},
    this.activeDates = const {},
    this.loading = false,
    this.error,
    this.statusFilter,
    this.selectedDate,
    this.dayDetail,
    this.detailLoading = false,
    this.detailError,
  });

  RecordBookState copyWith({
    List<DayLedgerRow>? rows,
    Map<String, ManaDayLoanIncome>? loanIncome,
    Set<String>? activeDates,
    bool? loading,
    String? error,
    bool clearError = false,
    String? statusFilter,
    bool clearStatusFilter = false,
    DateTime? selectedDate,
    bool clearSelectedDate = false,
    DayDetail? dayDetail,
    bool clearDayDetail = false,
    bool? detailLoading,
    String? detailError,
    bool clearDetailError = false,
  }) {
    return RecordBookState(
      rows: rows ?? this.rows,
      loanIncome: loanIncome ?? this.loanIncome,
      activeDates: activeDates ?? this.activeDates,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      selectedDate: clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
      dayDetail: clearDayDetail ? null : (dayDetail ?? this.dayDetail),
      detailLoading: detailLoading ?? this.detailLoading,
      detailError: clearDetailError ? null : (detailError ?? this.detailError),
    );
  }
}

class RecordBookNotifier extends Notifier<RecordBookState> {
  @override
  RecordBookState build() => const RecordBookState();

  Future<void> load(
    String businessId, {
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
  }) async {
    state = state.copyWith(loading: true, clearError: true, statusFilter: status);
    try {
      final api = ref.read(recordBookApiServiceProvider);
      // Both together. The decomposition is independent of the ledger rows,
      // so making one wait on the other would double the time an Owner
      // spends looking at a skeleton on a village connection.
      final results = await Future.wait<dynamic>([
        api.fetchLedgerRows(
          businessId: businessId,
          dateFrom: dateFrom,
          dateTo: dateTo,
          status: status,
        ),
        api.fetchLoanIncome(
            businessId: businessId, from: dateFrom, to: dateTo),
        // NO RANGE, on purpose, while the other two are windowed. This set
        // feeds the date picker, which must keep offering the whole book even
        // after picking a date has narrowed the loaded window to one day --
        // otherwise the first jump strands the Owner on the day they jumped
        // to, with a calendar that now offers only it.
        api.fetchActiveDates(businessId: businessId),
      ]);
      final active = results[2] as Set<String>;
      // ONE RULE, APPLIED ONCE. The list shows these days and the picker
      // offers these days -- "only show dates that are actively submitted
      // account dates" -- so a day can never be selectable without being
      // showable.
      state = state.copyWith(
        rows: (results[0] as List<DayLedgerRow>)
            .where((r) => active.contains(manaIsoDate(r.businessDate)))
            .toList(),
        loanIncome: results[1] as Map<String, ManaDayLoanIncome>,
        activeDates: active,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> openDayDetails(String businessId, DateTime businessDate) async {
    state = state.copyWith(
      selectedDate: businessDate,
      detailLoading: true,
      clearDetailError: true,
      clearDayDetail: true,
    );
    try {
      final api = ref.read(recordBookApiServiceProvider);
      final detail = await api.fetchDayDetail(businessId: businessId, businessDate: businessDate);
      state = state.copyWith(dayDetail: detail, detailLoading: false);
    } catch (e) {
      state = state.copyWith(detailLoading: false, detailError: e.toString());
    }
  }

  void closeDayDetails() {
    state = state.copyWith(clearSelectedDate: true, clearDayDetail: true, clearDetailError: true);
  }

  Future<bool> updateRemarks(String businessId, DateTime businessDate, String remarks) async {
    try {
      await ref.read(recordBookApiServiceProvider).updateRemarks(
            businessId: businessId,
            businessDate: businessDate,
            remarks: remarks,
          );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final recordBookProvider = NotifierProvider<RecordBookNotifier, RecordBookState>(
  RecordBookNotifier.new,
);

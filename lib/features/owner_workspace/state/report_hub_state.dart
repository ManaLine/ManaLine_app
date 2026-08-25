import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OW-010 Report Hub (Digital Record Book) — real Supabase wiring.
///
/// SCHEMA/DOC MISMATCH FOUND (flag, significant): the class-level design
/// this file was built against assumes `day_closures.account_group_id`
/// exists ("added live in Supabase per ADDENDUM v4 §9") — it does NOT.
/// The live `day_closures` table (0009_module8_finance_cash.sql) has no
/// `account_group_id` column and no `remarks` column at all. This means:
///   - Multi-day grouping (the whole "business-day-account" concept,
///     `spansMultipleDays`) cannot be implemented against the real schema
///     as designed — wired here as ONE ROW PER `day_closures` entry
///     (dateFrom == dateTo always) instead, which is a real behavior
///     change from the original design, not a cosmetic one.
///   - Remarks are read/written on `day_ledger.remarks` (same row
///     `record_book_state.dart`'s RecordBookApiService already uses),
///     since that's the only remarks column that actually exists
///     anywhere near this data — NOT stored "once at the group level"
///     as the original comment claimed.
/// This needs master chat confirmation: either the account_group_id
/// column needs to be added in a follow-up migration (and this file
/// re-wired to use it), or the "business-day-account" grouping concept
/// in OW-010's spec needs to be formally dropped in favor of one-row-
/// per-business-date, which is what ships here.
class ReportHubApiService {
  SupabaseClient get _db => Supabase.instance.client;

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<RecordBookPage> fetchRecordBook({
    required String businessId,
    int? year,
    int? month,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 30,
  }) async {
    var q = _db
        .from('day_closures')
        .select('closure_id, business_date, difference')
        .eq('business_id', businessId);
    if (year != null && month != null) {
      final from = DateTime(year, month, 1);
      final to = DateTime(year, month + 1, 0);
      q = q.gte('business_date', _isoDate(from)).lte('business_date', _isoDate(to));
    } else if (startDate != null && endDate != null) {
      q = q.gte('business_date', _isoDate(startDate)).lte('business_date', _isoDate(endDate));
    }
    final from = (page - 1) * pageSize;
    final to = from + pageSize - 1;
    final closureRows =
        await q.order('business_date', ascending: false).range(from, to) as List;

    if (closureRows.isEmpty) {
      return RecordBookPage(data: const [], page: page, pageSize: pageSize, totalCount: 0, totalPages: 0);
    }

    final dates = closureRows.map((r) => (r as Map)['business_date'] as String).toList();
    final ledgerRows = await _db
        .from('day_ledger')
        .select('business_date, total_collections, total_loan_distribution, total_expenses, '
            'closing_balance, remarks')
        .eq('business_id', businessId)
        .inFilter('business_date', dates) as List;
    final ledgerByDate = {
      for (final l in ledgerRows) (l as Map)['business_date'] as String: l as Map<String, dynamic>
    };

    final rows = closureRows.map((r) {
      final m = r as Map<String, dynamic>;
      final dateStr = m['business_date'] as String;
      final ledger = ledgerByDate[dateStr];
      final diff = (m['difference'] as num).toInt();
      return RecordBookRow(
        businessDayAccountId: m['closure_id'] as String, // see class-level SCHEMA/DOC MISMATCH note — closure_id, not account_group_id
        dateFrom: DateTime.parse(dateStr),
        dateTo: DateTime.parse(dateStr),
        collectionsTotal: (ledger?['total_collections'] as num?)?.toInt() ?? 0,
        loansGivenTotal: (ledger?['total_loan_distribution'] as num?)?.toInt() ?? 0,
        expensesTotal: (ledger?['total_expenses'] as num?)?.toInt() ?? 0,
        closingCash: (ledger?['closing_balance'] as num?)?.toInt() ?? 0,
        agentBalanceStatus: diff == 0 ? 'Balanced' : (diff > 0 ? 'Excess' : 'Short'),
        // FLAGGED: no table tracks "pending customers" (customers with an
        // unpaid due as of that business date) as a stored/queryable
        // count — would need a schedule/collection cross-reference per
        // historical date, which this list endpoint doesn't do per-row
        // for performance reasons. Left at 0 rather than an expensive
        // N-date recomputation; flag if the screen needs this live.
        pendingCustomersCount: 0,
        remarks: ledger?['remarks'] as String?,
      );
    }).toList();

    final countResponse = await _db
        .from('day_closures')
        .select('closure_id')
        .eq('business_id', businessId)
        .count();
    final totalCount = countResponse.count;

    MonthlySummary? monthlySummary;
    MonthlyClosing? monthlyClosing;
    if (year != null && month != null) {
      final totalCollections = rows.fold<int>(0, (s, r) => s + r.collectionsTotal);
      final totalLoansGiven = rows.fold<int>(0, (s, r) => s + r.loansGivenTotal);
      final totalExpenses = rows.fold<int>(0, (s, r) => s + r.expensesTotal);
      monthlySummary = MonthlySummary(
        year: year,
        month: month,
        businessDayAccounts: rows.length,
        totalCollections: totalCollections,
        totalLoansGiven: totalLoansGiven,
        totalExpenses: totalExpenses,
        pendingCustomers: 0, // see per-row note above
        outstandingAmount: 0, // FLAGGED: month-end outstanding needs a loans snapshot as-of month end; not computed here, needs an RPC/view decision
      );
      monthlyClosing = MonthlyClosing(
        year: year,
        month: month,
        businessDayAccounts: rows.length,
        collections: totalCollections,
        loansGiven: totalLoansGiven,
        expenses: totalExpenses,
        netCashMovement: totalCollections - totalLoansGiven - totalExpenses,
      );
    }

    return RecordBookPage(
      data: rows,
      page: page,
      pageSize: pageSize,
      totalCount: totalCount,
      totalPages: (totalCount / pageSize).ceil(),
      monthlySummary: monthlySummary,
      monthlyClosing: monthlyClosing,
    );
  }

  // businessDayAccountId is a day_closures.closure_id per the class-level
  // note — resolved back to its business_date, then the same underlying
  // data record_book_state.dart's fetchDayDetail already assembles.
  Future<RecordBookRowDetail> fetchRecordBookDetail({
    required String businessId,
    required String businessDayAccountId,
  }) async {
    final closure = await _db
        .from('day_closures')
        .select('closure_id, business_date, difference')
        .eq('closure_id', businessDayAccountId)
        .single();
    final dateStr = closure['business_date'] as String;

    final ledger = await _db
        .from('day_ledger')
        .select('total_collections, total_loan_distribution, total_expenses, closing_balance, remarks')
        .eq('business_id', businessId)
        .eq('business_date', dateStr)
        .maybeSingle();

    final collectionRows = await _db
        .from('collections')
        .select('collection_id, collected_amount, loans!inner(business_id)')
        .eq('business_date', dateStr)
        .eq('loans.business_id', businessId)
        .isFilter('deleted_at', null) as List;
    final loanRows = await _db
        .from('loans')
        .select('loan_id, amount_given')
        .eq('business_id', businessId)
        .eq('issue_business_date', dateStr)
        .isFilter('deleted_at', null) as List;
    final expenseRows = await _db
        .from('expenses')
        .select('expense_id, amount, category')
        .eq('business_id', businessId)
        .eq('business_date', dateStr) as List;

    final diff = (closure['difference'] as num).toInt();
    final row = RecordBookRow(
      businessDayAccountId: closure['closure_id'] as String,
      dateFrom: DateTime.parse(dateStr),
      dateTo: DateTime.parse(dateStr),
      collectionsTotal: (ledger?['total_collections'] as num?)?.toInt() ?? 0,
      loansGivenTotal: (ledger?['total_loan_distribution'] as num?)?.toInt() ?? 0,
      expensesTotal: (ledger?['total_expenses'] as num?)?.toInt() ?? 0,
      closingCash: (ledger?['closing_balance'] as num?)?.toInt() ?? 0,
      agentBalanceStatus: diff == 0 ? 'Balanced' : (diff > 0 ? 'Excess' : 'Short'),
      pendingCustomersCount: 0,
      remarks: ledger?['remarks'] as String?,
    );

    return RecordBookRowDetail(
      row: row,
      collections: collectionRows
          .map((r) => ReportHubLineItem(
              id: (r as Map)['collection_id'] as String,
              label: 'Collection',
              amount: (r['collected_amount'] as num).toInt()))
          .toList(),
      loans: loanRows
          .map((r) => ReportHubLineItem(
              id: (r as Map)['loan_id'] as String,
              label: 'Loan Distribution',
              amount: (r['amount_given'] as num).toInt()))
          .toList(),
      expenses: expenseRows
          .map((r) => ReportHubLineItem(
              id: (r as Map)['expense_id'] as String,
              label: r['category'] as String,
              amount: (r['amount'] as num).toInt()))
          .toList(),
      agentSummary: '', // FLAGGED: no single "agent summary" text field/column exists; screen would need to compose this from agent_salary_ledger/settlement rows, not fetched here
      pendingCustomers: const [], // see pendingCustomersCount note above
      corrections: const [], // FLAGGED: "Corrections" per CORRECTIONS (Option B) are offsetting entries within collections/loans themselves, not a separate table — would need an is_correction-style flag that doesn't exist in the schema; left empty rather than guessed
      dayClosureDetails:
          'Physical/UPI/Bank/Cheque vs Expected — difference: $diff', // best-effort summary string; full breakdown lives in day_closures columns not all selected here
    );
  }

  // Writes to day_ledger.remarks — see class-level SCHEMA/DOC MISMATCH
  // note; day_closures has no remarks column of its own.
  Future<void> updateRemarks({
    required String businessId,
    required String businessDayAccountId,
    required String remarks,
  }) async {
    final closure = await _db
        .from('day_closures')
        .select('business_date')
        .eq('closure_id', businessDayAccountId)
        .single();
    await _db
        .from('day_ledger')
        .update({'remarks': remarks})
        .eq('business_id', businessId)
        .eq('business_date', closure['business_date']);
  }
}

/// One row = one closed business-day-account (grouped by
/// `account_group_id`), per OW-010_Report_Hub.md "Row contents".
class RecordBookRow {
  final String businessDayAccountId; // account_group_id, or ungrouped single-day id
  final DateTime dateFrom;
  final DateTime dateTo;
  final int collectionsTotal;
  final int loansGivenTotal;
  final int expensesTotal;
  final int closingCash;
  final String agentBalanceStatus; // Balanced | Short | Excess — factual only
  final int pendingCustomersCount;
  final String? remarks;

  RecordBookRow({
    required this.businessDayAccountId,
    required this.dateFrom,
    required this.dateTo,
    required this.collectionsTotal,
    required this.loansGivenTotal,
    required this.expensesTotal,
    required this.closingCash,
    required this.agentBalanceStatus,
    required this.pendingCustomersCount,
    this.remarks,
  });

  /// Whether Day Closure was delayed across multiple calendar days for
  /// this business-day-account, per OW-010's "Key concept" section.
  bool get spansMultipleDays => dateFrom.year != dateTo.year ||
      dateFrom.month != dateTo.month ||
      dateFrom.day != dateTo.day;
}

/// `monthly_summary` block, returned only when ?year=&month= is used.
class MonthlySummary {
  final int year;
  final int month;
  final int businessDayAccounts;
  final int totalCollections;
  final int totalLoansGiven;
  final int totalExpenses;
  final int pendingCustomers;
  final int outstandingAmount;

  MonthlySummary({
    required this.year,
    required this.month,
    required this.businessDayAccounts,
    required this.totalCollections,
    required this.totalLoansGiven,
    required this.totalExpenses,
    required this.pendingCustomers,
    required this.outstandingAmount,
  });
}

/// `monthly_closing` block — automatic row appended at the end of each
/// month's rows, per OW-010's "Monthly Closing" section.
class MonthlyClosing {
  final int year;
  final int month;
  final int businessDayAccounts;
  final int collections;
  final int loansGiven;
  final int expenses;
  final int netCashMovement;

  MonthlyClosing({
    required this.year,
    required this.month,
    required this.businessDayAccounts,
    required this.collections,
    required this.loansGiven,
    required this.expenses,
    required this.netCashMovement,
  });
}

/// Standard `{ data, page, page_size, total_count, total_pages }`
/// envelope, per ADDENDUM v5 §11.
class RecordBookPage {
  final List<RecordBookRow> data;
  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final MonthlySummary? monthlySummary;
  final MonthlyClosing? monthlyClosing;

  RecordBookPage({
    required this.data,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    this.monthlySummary,
    this.monthlyClosing,
  });
}

/// Row drill-down: "full Daily Business Report detail" per ADDENDUM v5
/// §11 — Collections, Loans, Expenses, Agent Summary, Pending Customers,
/// Corrections, Day Closure Details. Kept as generic summary line items
/// here (see record_book_state.dart's DayDetailEntry note) rather than
/// replicating full native table shapes owned by other screens.
class RecordBookRowDetail {
  final RecordBookRow row;
  final List<ReportHubLineItem> collections;
  final List<ReportHubLineItem> loans;
  final List<ReportHubLineItem> expenses;
  final String agentSummary;
  final List<ReportHubLineItem> pendingCustomers;
  final List<ReportHubLineItem> corrections;
  final String dayClosureDetails;

  RecordBookRowDetail({
    required this.row,
    this.collections = const [],
    this.loans = const [],
    this.expenses = const [],
    this.agentSummary = '',
    this.pendingCustomers = const [],
    this.corrections = const [],
    this.dayClosureDetails = '',
  });
}

class ReportHubLineItem {
  final String id;
  final String label;
  final int amount;

  ReportHubLineItem({required this.id, required this.label, required this.amount});
}

final reportHubApiServiceProvider = Provider<ReportHubApiService>((ref) {
  return ReportHubApiService();
});

class ReportHubState {
  final int selectedYear;
  final int selectedMonth;
  final List<RecordBookRow> rows;
  final MonthlySummary? monthlySummary;
  final MonthlyClosing? monthlyClosing;
  final bool loading;
  final String? error;

  final String? selectedBusinessDayAccountId;
  final RecordBookRowDetail? detail;
  final bool detailLoading;
  final String? detailError;

  const ReportHubState({
    required this.selectedYear,
    required this.selectedMonth,
    this.rows = const [],
    this.monthlySummary,
    this.monthlyClosing,
    this.loading = false,
    this.error,
    this.selectedBusinessDayAccountId,
    this.detail,
    this.detailLoading = false,
    this.detailError,
  });

  ReportHubState copyWith({
    int? selectedYear,
    int? selectedMonth,
    List<RecordBookRow>? rows,
    MonthlySummary? monthlySummary,
    bool clearMonthlySummary = false,
    MonthlyClosing? monthlyClosing,
    bool clearMonthlyClosing = false,
    bool? loading,
    String? error,
    bool clearError = false,
    String? selectedBusinessDayAccountId,
    bool clearSelectedId = false,
    RecordBookRowDetail? detail,
    bool clearDetail = false,
    bool? detailLoading,
    String? detailError,
    bool clearDetailError = false,
  }) {
    return ReportHubState(
      selectedYear: selectedYear ?? this.selectedYear,
      selectedMonth: selectedMonth ?? this.selectedMonth,
      rows: rows ?? this.rows,
      monthlySummary: clearMonthlySummary ? null : (monthlySummary ?? this.monthlySummary),
      monthlyClosing: clearMonthlyClosing ? null : (monthlyClosing ?? this.monthlyClosing),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      selectedBusinessDayAccountId:
          clearSelectedId ? null : (selectedBusinessDayAccountId ?? this.selectedBusinessDayAccountId),
      detail: clearDetail ? null : (detail ?? this.detail),
      detailLoading: detailLoading ?? this.detailLoading,
      detailError: clearDetailError ? null : (detailError ?? this.detailError),
    );
  }
}

class ReportHubNotifier extends Notifier<ReportHubState> {
  @override
  ReportHubState build() {
    final now = DateTime.now();
    return ReportHubState(selectedYear: now.year, selectedMonth: now.month);
  }

  Future<void> loadMonth(String businessId, {int? year, int? month}) async {
    final y = year ?? state.selectedYear;
    final m = month ?? state.selectedMonth;
    state = state.copyWith(
      selectedYear: y,
      selectedMonth: m,
      loading: true,
      clearError: true,
    );
    try {
      final api = ref.read(reportHubApiServiceProvider);
      final page = await api.fetchRecordBook(businessId: businessId, year: y, month: m);
      state = state.copyWith(
        rows: page.data,
        monthlySummary: page.monthlySummary,
        clearMonthlySummary: page.monthlySummary == null,
        monthlyClosing: page.monthlyClosing,
        clearMonthlyClosing: page.monthlyClosing == null,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> openRowDetail(String businessId, String businessDayAccountId) async {
    state = state.copyWith(
      selectedBusinessDayAccountId: businessDayAccountId,
      detailLoading: true,
      clearDetailError: true,
      clearDetail: true,
    );
    try {
      final api = ref.read(reportHubApiServiceProvider);
      final detail = await api.fetchRecordBookDetail(
        businessId: businessId,
        businessDayAccountId: businessDayAccountId,
      );
      state = state.copyWith(detail: detail, detailLoading: false);
    } catch (e) {
      state = state.copyWith(detailLoading: false, detailError: e.toString());
    }
  }

  void closeRowDetail() {
    state = state.copyWith(clearSelectedId: true, clearDetail: true, clearDetailError: true);
  }

  Future<bool> updateRemarks(String businessId, String businessDayAccountId, String remarks) async {
    try {
      await ref.read(reportHubApiServiceProvider).updateRemarks(
            businessId: businessId,
            businessDayAccountId: businessDayAccountId,
            remarks: remarks,
          );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final reportHubProvider = NotifierProvider<ReportHubNotifier, ReportHubState>(
  ReportHubNotifier.new,
);

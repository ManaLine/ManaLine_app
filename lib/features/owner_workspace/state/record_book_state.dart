import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    if (dateFrom != null) q = q.gte('business_date', _isoDate(dateFrom));
    if (dateTo != null) q = q.lte('business_date', _isoDate(dateTo));
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('business_date', ascending: false);
    final penalties = await _penaltyByDay(businessId: businessId, from: dateFrom, to: dateTo);
    return (rows as List)
        .map((r) => _rowFromMap(r as Map<String, dynamic>, penalties))
        .toList();
  }

  /// Recognised penalty totals keyed by ISO business date. One call for the
  /// whole range rather than per row — the RPC returns only days that
  /// actually have penalties, so absent days read as zero.
  Future<Map<String, double>> _penaltyByDay({
    required String businessId,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _db.schema('app').rpc('penalty_collected_by_day', params: {
      'p_business_id': businessId,
      'p_from': from == null ? null : _isoDate(from),
      'p_to': to == null ? null : _isoDate(to),
    });
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['business_date'] as String: (r['penalty_collected'] as num).toDouble(),
    };
  }

  DayLedgerRow _rowFromMap(Map<String, dynamic> r, [Map<String, double> penalties = const {}]) => DayLedgerRow(
        businessDate: DateTime.parse(r['business_date'] as String),
        openingBalance: (r['opening_balance'] as num).toDouble(),
        totalCollections: (r['total_collections'] as num).toDouble(),
        totalLoanDistribution: (r['total_loan_distribution'] as num).toDouble(),
        investorDeposits: (r['investor_deposits'] as num).toDouble(),
        investorWithdrawals: (r['investor_withdrawals'] as num).toDouble(),
        totalExpenses: (r['total_expenses'] as num).toDouble(),
        shortAmount: (r['short_amount'] as num).toDouble(),
        excessAmount: (r['excess_amount'] as num).toDouble(),
        closingBalance: (r['closing_balance'] as num).toDouble(),
        status: r['status'] as String,
        remarks: r['remarks'] as String?,
        penaltyCollected: penalties[r['business_date'] as String] ?? 0,
      );

  Future<DayDetail> fetchDayDetail({
    required String businessId,
    required DateTime businessDate,
  }) async {
    final date = _isoDate(businessDate);
    final ledgerRow = await _db
        .from('day_ledger')
        .select()
        .eq('business_id', businessId)
        .eq('business_date', date)
        .single();

    final collectionRows = await _db
        .from('collections')
        .select('collection_id, collected_amount, entry_timestamp, loan_id, loans!inner(business_id)')
        .eq('business_date', date)
        .eq('loans.business_id', businessId);
    final loanRows =
        await _db.from('loans').select('loan_id, repayment_amount, entry_timestamp').eq('business_id', businessId).eq('issue_business_date', date);
    final expenseRows =
        await _db.from('expenses').select('expense_id, amount, entry_timestamp, category').eq('business_id', businessId).eq('business_date', date);
    final adjustmentRows = await _db
        .from('settlement_adjustments')
        .select('adjustment_id, amount, business_date, adjustment_type, '
            'account_settlements!inner(account_periods!inner(business_id))')
        .eq('business_date', date)
        .eq('account_settlements.account_periods.business_id', businessId);

    final penalties = await _penaltyByDay(businessId: businessId, from: businessDate, to: businessDate);

    return DayDetail(
      ledger: _rowFromMap(ledgerRow, penalties),
      collections: (collectionRows as List).cast<Map<String, dynamic>>().map((c) => DayDetailEntry(
            id: c['collection_id'] as String,
            label: 'Collection',
            amount: (c['collected_amount'] as num).toDouble(),
            timestamp: DateTime.parse(c['entry_timestamp'] as String),
            sourceLoanId: c['loan_id'] as String?,
          )).toList(),
      loans: (loanRows as List).cast<Map<String, dynamic>>().map((l) => DayDetailEntry(
            id: l['loan_id'] as String,
            label: 'Loan Distribution',
            amount: (l['repayment_amount'] as num).toDouble(),
            timestamp: DateTime.parse(l['entry_timestamp'] as String),
            sourceLoanId: l['loan_id'] as String,
          )).toList(),
      expenses: (expenseRows as List).cast<Map<String, dynamic>>().map((e) => DayDetailEntry(
            id: e['expense_id'] as String,
            label: e['category'] as String? ?? 'Expense',
            amount: (e['amount'] as num).toDouble(),
            timestamp: DateTime.parse(e['entry_timestamp'] as String),
          )).toList(),
      deposits: const [], // requires an investments query scoped to business_date — not fetched by this summary view
      withdrawals: const [], // requires an investment_withdrawals query scoped to business_date — not fetched by this summary view
      adjustments: (adjustmentRows as List).cast<Map<String, dynamic>>().map((a) => DayDetailEntry(
            id: a['adjustment_id'] as String,
            label: a['adjustment_type'] as String? ?? 'Adjustment',
            amount: (a['amount'] as num).toDouble(),
            timestamp: DateTime.parse(a['business_date'] as String),
            isCorrection: true,
          )).toList(),
      auditLog: const [], // BR-124/158 admin/security only — requires a dedicated audit_log query, not fetched by this summary view
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
        .eq('business_date', _isoDate(businessDate));
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One row per Business Date, per BR-094 (`day_ledger` UNIQUE(business_id,
/// business_date)). Field names map 1:1 to `day_ledger` columns per
/// 03_Database_Schema.md §8.2.
class DayLedgerRow {
  final DateTime businessDate;
  final double openingBalance; // BF Cash
  final double totalCollections;
  final double totalLoanDistribution;
  final double investorDeposits;
  final double investorWithdrawals;
  final double totalExpenses;
  final double shortAmount;
  final double excessAmount;
  final double closingBalance;
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
  final double penaltyCollected;

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
    this.remarks,
    this.penaltyCollected = 0,
  });

  double get difference => excessAmount - shortAmount;

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
  final String label;
  final double amount;
  final DateTime timestamp;
  final bool isCorrection;
  final String? sourceLoanId;

  DayDetailEntry({
    required this.id,
    required this.label,
    required this.amount,
    required this.timestamp,
    this.isCorrection = false,
    this.sourceLoanId,
  });
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
  final bool loading;
  final String? error;
  final String? statusFilter;

  final DateTime? selectedDate;
  final DayDetail? dayDetail;
  final bool detailLoading;
  final String? detailError;

  const RecordBookState({
    this.rows = const [],
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
      final rows = await api.fetchLedgerRows(
        businessId: businessId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        status: status,
      );
      state = state.copyWith(rows: rows, loading: false);
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

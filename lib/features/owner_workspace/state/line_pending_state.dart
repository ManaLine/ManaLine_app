import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_book_state.dart' show manaIsoDate;

/// The Line Pending List — design document 2.6.1.1, reached from the Account
/// Sheet.
///
/// Four filters, in the document's own words: "From date - to date. Bal Amount
/// Min.- Eg. 0, 500, 5000. Select No. of pending Weeks/Months- Eg. Last
/// 10weeks/Last 3Months. Add Sort by option (New,Old,Date,Amount,Name,Village
/// name & Pin)."
///
/// THE THREE NARROWING FILTERS ARE THE SERVER'S and the sort is the client's.
/// Narrowing changes which rows exist and belongs beside the authorization
/// that decides which rows may be seen at all; sorting only reorders what is
/// already in hand, and making an Owner wait for a round trip to see the same
/// 52 rows in a different order would be a worse screen on a village
/// connection.
class LinePendingApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<PendingLoanRow>> fetch({
    required String businessId,
    DateTime? from,
    DateTime? to,
    int minBalance = 0,
    int minPeriods = 0,
  }) async {
    final rows = await _db.schema('app').rpc('line_pending_list', params: {
      'p_business_id': businessId,
      'p_from': from == null ? null : manaIsoDate(from),
      'p_to': to == null ? null : manaIsoDate(to),
      'p_min_balance': minBalance,
      'p_min_periods': minPeriods,
    });
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PendingLoanRow.fromMap)
        .toList();
  }
}

class PendingLoanRow {
  final String loanId;
  final String customerId;
  final String fullName;

  /// The father or husband name. Two people in one village share a given name
  /// often enough that a pending list without this names the wrong debtor.
  final String careOf;

  final String village;
  final String pinCode;
  final int balance;
  final int installmentAmount;

  /// 'Daily' | 'Weekly' | 'Monthly' — what one overdue period MEANS on this
  /// loan, which is why [periodsOverdue] is drawn with its unit and never as a
  /// bare number.
  final String repaymentType;

  final DateTime issued;

  /// Instalments that have come due and have not been paid.
  ///
  /// NOT instalments remaining. The two differ by the whole age of the loan,
  /// and the easy one is useless: computed against the live book it calls a
  /// Daily loan 984 weeks pending and puts a loan issued yesterday at the top.
  /// See the migration for the arithmetic.
  final int periodsOverdue;

  /// The last day anything was collected against this loan, or null if nothing
  /// ever was. Null is the worse case and the list says so rather than
  /// substituting the issue date.
  final DateTime? lastPaid;

  const PendingLoanRow({
    required this.loanId,
    required this.customerId,
    required this.fullName,
    required this.careOf,
    required this.village,
    required this.pinCode,
    required this.balance,
    required this.installmentAmount,
    required this.repaymentType,
    required this.issued,
    required this.periodsOverdue,
    required this.lastPaid,
  });

  factory PendingLoanRow.fromMap(Map<String, dynamic> r) => PendingLoanRow(
        loanId: r['loan_id'] as String,
        customerId: r['customer_id'] as String,
        fullName: r['full_name'] as String? ?? '',
        careOf: r['care_of'] as String? ?? '',
        village: r['village'] as String? ?? '',
        pinCode: r['pin_code'] as String? ?? '',
        balance: (r['balance'] as num?)?.round() ?? 0,
        installmentAmount: (r['installment_amount'] as num?)?.round() ?? 0,
        repaymentType: r['repayment_type'] as String? ?? 'Weekly',
        issued: DateTime.parse(r['issued'] as String),
        periodsOverdue: (r['periods_overdue'] as num?)?.round() ?? 0,
        lastPaid: r['last_paid'] == null
            ? null
            : DateTime.parse(r['last_paid'] as String),
      );
}

/// The document's six, read as follows.
///
/// "New,Old,Date,Amount,Name,Village name & Pin". New and Old are the loan's
/// age -- newest first and oldest first -- which is how the Loan Request list
/// on page 5 uses the same pair, "Coustmer Old-New". That leaves Date to mean
/// something the other two do not, and the only other date on a pending row is
/// when the customer last paid. It is also the most useful of the three: the
/// top of that order is whoever has gone longest without paying anything.
enum PendingSort { newest, oldest, lastPaid, amount, name, villagePin }

class LinePendingState {
  final List<PendingLoanRow> rows;
  final bool loading;
  final String? error;

  final DateTime? from;
  final DateTime? to;
  final int minBalance;
  final int minPeriods;
  final PendingSort sort;

  const LinePendingState({
    this.rows = const [],
    this.loading = false,
    this.error,
    this.from,
    this.to,
    this.minBalance = 0,
    this.minPeriods = 0,
    this.sort = PendingSort.lastPaid,
  });

  /// True when a filter is narrowing the list.
  ///
  /// The rail draws an active filter differently on purpose -- an Owner
  /// reading a filtered pending list as the whole book would believe their
  /// line is in better shape than it is.
  bool get isNarrowed =>
      from != null || to != null || minBalance > 0 || minPeriods > 0;

  int get totalOutstanding =>
      rows.fold<int>(0, (sum, r) => sum + r.balance);

  /// The rows in the chosen order.
  ///
  /// SORTED HERE, not in SQL, and stably: every comparison falls back to the
  /// loan id so two customers with the same name or the same balance keep a
  /// fixed order between rebuilds instead of swapping places under a thumb.
  List<PendingLoanRow> get sorted {
    final out = [...rows];
    int tie(PendingLoanRow a, PendingLoanRow b) => a.loanId.compareTo(b.loanId);
    out.sort((a, b) {
      final c = switch (sort) {
        PendingSort.newest => b.issued.compareTo(a.issued),
        PendingSort.oldest => a.issued.compareTo(b.issued),
        // Never paid sorts to the top: null is the longest anyone has gone
        // without paying, not a missing value to shuffle to the end.
        PendingSort.lastPaid => (a.lastPaid ?? DateTime(1900))
            .compareTo(b.lastPaid ?? DateTime(1900)),
        PendingSort.amount => b.balance.compareTo(a.balance),
        PendingSort.name =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        PendingSort.villagePin => () {
            final v = a.village.toLowerCase().compareTo(b.village.toLowerCase());
            return v != 0 ? v : a.pinCode.compareTo(b.pinCode);
          }(),
      };
      return c != 0 ? c : tie(a, b);
    });
    return out;
  }

  LinePendingState copyWith({
    List<PendingLoanRow>? rows,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    int? minBalance,
    int? minPeriods,
    PendingSort? sort,
  }) =>
      LinePendingState(
        rows: rows ?? this.rows,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        minBalance: minBalance ?? this.minBalance,
        minPeriods: minPeriods ?? this.minPeriods,
        sort: sort ?? this.sort,
      );
}

final linePendingApiServiceProvider =
    Provider<LinePendingApiService>((ref) => LinePendingApiService());

class LinePendingNotifier extends AutoDisposeNotifier<LinePendingState> {
  @override
  LinePendingState build() => const LinePendingState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await ref.read(linePendingApiServiceProvider).fetch(
            businessId: businessId,
            from: state.from,
            to: state.to,
            minBalance: state.minBalance,
            minPeriods: state.minPeriods,
          );
      state = state.copyWith(rows: rows, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Sorting does NOT refetch -- it reorders what is already here.
  void setSort(PendingSort sort) => state = state.copyWith(sort: sort);

  Future<void> setMinBalance(String businessId, int v) async {
    state = state.copyWith(minBalance: v);
    await load(businessId);
  }

  Future<void> setMinPeriods(String businessId, int v) async {
    state = state.copyWith(minPeriods: v);
    await load(businessId);
  }

  Future<void> setDates(String businessId, DateTime? from, DateTime? to) async {
    state = from == null && to == null
        ? state.copyWith(clearDates: true)
        : state.copyWith(from: from, to: to);
    await load(businessId);
  }
}

final linePendingProvider =
    AutoDisposeNotifierProvider<LinePendingNotifier, LinePendingState>(
        LinePendingNotifier.new);

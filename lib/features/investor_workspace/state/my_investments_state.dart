import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// IW-003 My Investments — real Supabase wiring over Module 5
/// (investments, investment_interest_ledger, investment_withdrawals,
/// distribution_declarations, distribution_payments).
///
/// RLS: `investments_investor_select_own` / `investment_interest_ledger_
/// investor_select_own` / `investment_withdrawals_investor_select_own` /
/// `distribution_declarations_investor_select_own` /
/// `distribution_payments_investor_select_own` (0014/0015_rls...sql) all
/// already scope every one of these tables to the calling Investor's own
/// rows via `app.is_own_investment_row()` / `investors.person_id =
/// app.current_person_id()`. No client-side person_id/investor_id filter
/// is added on top of that — same "don't add a redundant filter" approach
/// already used in owner_workspace/state/investor_state.dart, just doing
/// double duty here (RLS narrows it to this investor even though the
/// investor_id param is still used to pick the right investments row set).
///
/// SCHEMA MISMATCH FLAGGED (found this session): owner_workspace/state/
/// investor_state.dart selects `investments.remaining_balance`, but the
/// locked schema (0006_module5_investor_domain.sql) has NO
/// `remaining_balance` column on `investments`. Per that migration's own
/// column comment, `principal_amount` IS the single combined
/// Principal+Interest running balance (Merged Addendum item 2), and
/// `original_principal_amount` is the frozen-at-creation Agreement
/// Snapshot value (BR-034). This file uses those two real columns
/// correctly rather than repeating investor_state.dart's query — flagged
/// for master chat to fix investor_state.dart to match, not the other way
/// around.
///
/// MONEY / PRECISION FLAG: principal_amount, original_principal_amount,
/// and all amount columns referenced below are DECIMAL(14,0) — whole
/// rupees, no decimal places (per Merged Addendum item 1). Mapping to
/// Dart `double` is safe for whole-rupee values within that range, but
/// note this is NOT sub-rupee-precision currency; do not introduce paise/
/// cents anywhere reading these columns.
class MyInvestmentsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<InvestorInvestmentSummary>> fetchInvestments({
    required String businessId,
    required String investorId,
  }) async {
    final rows = await _db
        .from('investments')
        .select('investment_id, principal_amount, original_principal_amount, roi_rate, '
            'interest_type, effective_date, status, last_interest_payment_date')
        .eq('business_id', businessId)
        .eq('investor_id', investorId)
        .order('effective_date', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return InvestorInvestmentSummary(
        investmentId: r['investment_id'] as String,
        principalAmount: (r['principal_amount'] as num).toDouble(),
        roiRate: (r['roi_rate'] as num).toDouble(),
        interestMethod: r['interest_type'] as String,
        effectiveDate: DateTime.parse(r['effective_date'] as String),
        // interestAccrued is deliberately NOT computed here — BR-032/BR-234
        // define it as a LIVE calculation (Calculation Engine §3: Simple vs
        // Yearly Compound formulas against days-elapsed), not a stored
        // column. Same simplification already accepted in
        // owner_workspace/state/investor_state.dart's `interestDue: 0`
        // (that file's own comment: "requires investment_interest_ledger
        // aggregation"). A real fix needs either a Postgres view/RPC that
        // runs the Calc Engine formula server-side, or client-side
        // reimplementation of §3 here — not invented in this pass.
        interestAccrued: 0,
        interestPaid: 0,
        status: r['status'] as String,
      );
    }).toList();
  }

  Future<InvestmentDetail> fetchInvestmentDetail({required String investmentId}) async {
    final row = await _db
        .from('investments')
        .select('investment_id, original_principal_amount, roi_rate, interest_type, '
            'effective_date, profit_share_percent')
        .eq('investment_id', investmentId)
        .single();

    final agreementSnapshot = AgreementSnapshot(
      originalPrincipalAmount: (row['original_principal_amount'] as num).toDouble(),
      roiRate: (row['roi_rate'] as num).toDouble(),
      interestType: row['interest_type'] as String,
      effectiveDate: DateTime.parse(row['effective_date'] as String),
    );
    final profitSharePercent = (row['profit_share_percent'] as num?)?.toDouble();

    final ledgerRows = await _db
        .from('investment_interest_ledger')
        .select('entry_type, amount, business_date, owner_verified, remarks')
        .eq('investment_id', investmentId)
        .order('business_date', ascending: false);

    final interestLedger = (ledgerRows as List).cast<Map<String, dynamic>>().map((r) {
      return InterestLedgerEntry(
        entryType: r['entry_type'] as String,
        amount: (r['amount'] as num).toDouble(),
        businessDate: DateTime.parse(r['business_date'] as String),
        ownerVerified: r['owner_verified'] as bool? ?? false,
        remarks: r['remarks'] as String?,
      );
    }).toList();

    // approved_by_person_id -> persons.full_name needs a join; kept as a
    // separate lookup per-row (small N per investment) rather than a
    // nested embed, since investment_withdrawals.approved_by_person_id
    // references `persons`, not `business_members` — no single embed path
    // through PostgREST for a bare persons FK the way business_members
    // joins work elsewhere in this codebase.
    final withdrawalRows = await _db
        .from('investment_withdrawals')
        .select('withdrawal_type, amount, business_date, remarks, approved_by_person_id')
        .eq('investment_id', investmentId)
        .order('business_date', ascending: false);

    final withdrawalHistory = <InvestmentWithdrawalHistoryEntry>[];
    for (final r in (withdrawalRows as List).cast<Map<String, dynamic>>()) {
      String approvedBy = '';
      final approverId = r['approved_by_person_id'];
      if (approverId != null) {
        final approver =
            await _db.from('persons').select('full_name').eq('person_id', approverId).maybeSingle();
        approvedBy = approver?['full_name'] as String? ?? '';
      }
      withdrawalHistory.add(InvestmentWithdrawalHistoryEntry(
        withdrawalType: r['withdrawal_type'] as String,
        amount: (r['amount'] as num).toDouble(),
        businessDate: DateTime.parse(r['business_date'] as String),
        approvedBy: approvedBy,
        remarks: r['remarks'] as String?,
      ));
    }

    // Declare -> Pay split (Rule #058): distribution_payments is 0..1 per
    // declaration_id (UNIQUE constraint), so a left-join-shaped fetch is
    // right here — a Declared-only row simply has no matching payment yet.
    final declarationRows = await _db
        .from('distribution_declarations')
        .select('declaration_id, declared_amount, status, business_date, '
            'distribution_payments(paid_amount, interest_amount, business_date)')
        .eq('investment_id', investmentId)
        .eq('recipient_type', 'Investor')
        .order('business_date', ascending: false);

    final distributionHistory = (declarationRows as List).cast<Map<String, dynamic>>().map((r) {
      final payments = ((r['distribution_payments'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final payment = payments.isNotEmpty ? payments.first : null;
      return DistributionHistoryEntry(
        declaredAmount: (r['declared_amount'] as num).toDouble(),
        declaredStatus: r['status'] as String,
        declaredDate: DateTime.parse(r['business_date'] as String),
        paidAmount: payment != null ? (payment['paid_amount'] as num).toDouble() : null,
        paidDate: payment != null ? DateTime.parse(payment['business_date'] as String) : null,
        // interest_amount on distribution_payments is manually Owner-
        // entered (Rule #059), never system-computed — surfaced as-is,
        // defaults to 0 per that column's own DB DEFAULT.
        paidInterestAmount: payment != null ? (payment['interest_amount'] as num).toDouble() : null,
      );
    }).toList();

    return InvestmentDetail(
      agreementSnapshot: agreementSnapshot,
      profitSharePercent: profitSharePercent,
      interestLedger: interestLedger,
      withdrawalHistory: withdrawalHistory,
      distributionHistory: distributionHistory,
    );
  }

  /// GAP FLAGGED: `GET /investments/{investment_id}/statement` (API Spec
  /// Part 2 §6.6) is documented as a pre-aggregated payment/interest
  /// history + running balance in ONE call — that shape implies a
  /// server-side view or RPC, not a raw table this Supabase client can
  /// Backed by `app.get_investment_statement` (migration 0019), added to
  /// close the gap this method used to flag. Per option (a) noted above:
  /// this is a `rpc('get_investment_statement', ...)` call, not a real
  /// PDF/file-generation endpoint (no such infra exists in this schema) —
  /// it returns the raw ledger/distribution/withdrawal rows as a JSON
  /// string for the client to format/export, not a downloadable file URL.
  /// If IW-003's screen actually needs a real file (PDF/CSV) rather than
  /// a JSON payload, that's a separate, larger scope (file storage +
  /// generation) not covered by this fix.
  Future<String?> downloadStatement({required String investmentId}) async {
    final result = await _db.rpc('get_investment_statement', params: {
      'p_investment_id': investmentId,
    });
    if (result == null) return null;
    return jsonEncode(result);
  }
}

final myInvestmentsApiServiceProvider = Provider<MyInvestmentsApiService>((ref) {
  return MyInvestmentsApiService();
});

class InvestorInvestmentSummary {
  final String investmentId;
  final double principalAmount;
  final double roiRate;
  final String interestMethod; // Simple | Yearly Compound
  final DateTime effectiveDate;
  final double interestAccrued; // system-calculated daily, BR-032/BR-055
  final double interestPaid;
  final String status; // Active | Closed

  InvestorInvestmentSummary({
    required this.investmentId,
    required this.principalAmount,
    required this.roiRate,
    required this.interestMethod,
    required this.effectiveDate,
    required this.interestAccrued,
    required this.interestPaid,
    required this.status,
  });
}

// Agreement Snapshot — frozen terms at time of investment (BR-034),
// never live-recalculated even if the underlying investment record
// changes later.
class AgreementSnapshot {
  final double originalPrincipalAmount;
  final double roiRate;
  final String interestType;
  final DateTime effectiveDate;

  AgreementSnapshot({
    required this.originalPrincipalAmount,
    required this.roiRate,
    required this.interestType,
    required this.effectiveDate,
  });
}

class InterestLedgerEntry {
  final String entryType; // Accrual Snapshot | Payment | Compounding Event
  final double amount;
  final DateTime businessDate;
  final bool ownerVerified; // BR-055
  final String? remarks;

  InterestLedgerEntry({
    required this.entryType,
    required this.amount,
    required this.businessDate,
    required this.ownerVerified,
    this.remarks,
  });
}

class InvestmentWithdrawalHistoryEntry {
  final String withdrawalType; // Interest Only | Principal Partial | Principal Full | Principal + Interest
  final double amount;
  final DateTime businessDate;
  final String approvedBy;
  final String? remarks;

  InvestmentWithdrawalHistoryEntry({
    required this.withdrawalType,
    required this.amount,
    required this.businessDate,
    required this.approvedBy,
    this.remarks,
  });
}

/// Distribution/Profit Share History row — Declared and Paid are two
/// distinct, separately timestamped records (Rule #058: Profit
/// Declaration ≠ Profit Payment). A row may exist Declared-only.
class DistributionHistoryEntry {
  final double declaredAmount;
  final String declaredStatus;
  final DateTime declaredDate;
  final double? paidAmount;
  final DateTime? paidDate;
  final double? paidInterestAmount; // interest on the unpaid gap, Rule #059, defaults ₹0, never system-calculated

  DistributionHistoryEntry({
    required this.declaredAmount,
    required this.declaredStatus,
    required this.declaredDate,
    this.paidAmount,
    this.paidDate,
    this.paidInterestAmount,
  });

  bool get isPaid => paidDate != null;
}

class InvestmentDetail {
  final AgreementSnapshot agreementSnapshot;
  final double? profitSharePercent; // read-only; null/absent = not enabled for this investment
  final List<InterestLedgerEntry> interestLedger;
  final List<InvestmentWithdrawalHistoryEntry> withdrawalHistory;
  final List<DistributionHistoryEntry> distributionHistory;

  InvestmentDetail({
    required this.agreementSnapshot,
    this.profitSharePercent,
    this.interestLedger = const [],
    this.withdrawalHistory = const [],
    this.distributionHistory = const [],
  });

  bool get hasProfitShare => profitSharePercent != null;
}

// --- List state (keyed by businessId+investorId) --------------------------

class MyInvestmentsListState {
  final List<InvestorInvestmentSummary> investments;
  final bool loading;
  final String? error;

  const MyInvestmentsListState({this.investments = const [], this.loading = false, this.error});

  // S3 Empty — Active Membership exists but Owner hasn't recorded any
  // Investment yet. Only true once a load attempt has actually
  // completed (not before initial load, not while loading, not on error).
  bool get isEmpty => !loading && error == null && investments.isEmpty;

  MyInvestmentsListState copyWith({
    List<InvestorInvestmentSummary>? investments,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return MyInvestmentsListState(
      investments: investments ?? this.investments,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

typedef MyInvestmentsKey = ({String businessId, String investorId});

class MyInvestmentsListNotifier extends FamilyNotifier<MyInvestmentsListState, MyInvestmentsKey> {
  @override
  MyInvestmentsListState build(MyInvestmentsKey arg) => const MyInvestmentsListState();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(myInvestmentsApiServiceProvider);
      final investments = await api.fetchInvestments(businessId: arg.businessId, investorId: arg.investorId);
      state = state.copyWith(investments: investments, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final myInvestmentsListProvider =
    NotifierProvider.family<MyInvestmentsListNotifier, MyInvestmentsListState, MyInvestmentsKey>(
  MyInvestmentsListNotifier.new,
);

// --- Detail state (keyed by investmentId) ----------------------------------

class InvestmentDetailNotifier extends FamilyAsyncNotifier<InvestmentDetail, String> {
  @override
  Future<InvestmentDetail> build(String investmentId) async {
    return ref.read(myInvestmentsApiServiceProvider).fetchInvestmentDetail(investmentId: investmentId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state =
        await AsyncValue.guard(() => ref.read(myInvestmentsApiServiceProvider).fetchInvestmentDetail(investmentId: arg));
  }

  Future<String?> downloadStatement() async {
    try {
      return await ref.read(myInvestmentsApiServiceProvider).downloadStatement(investmentId: arg);
    } catch (_) {
      return null;
    }
  }
}

final investmentDetailProvider =
    AsyncNotifierProvider.family<InvestmentDetailNotifier, InvestmentDetail, String>(
  InvestmentDetailNotifier.new,
);

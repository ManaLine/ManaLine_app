import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// IW-004 Request Withdrawal — real Supabase wiring.
///
/// Withdrawal Requests never auto-pay: submitRequest only creates an
/// `investment_withdrawal_requests` row at status='Pending' — actual
/// ledger update happens only when the Owner separately approves+pays
/// (`PATCH /withdrawal-requests/{id}` on the Owner side, out of scope
/// here). No status-transition logic is built here beyond that initial
/// insert, per instructions.
///
/// RLS: `investment_withdrawal_requests_investor_select_own` / `..._insert_own`
/// (0015_rls_module6... — actually declared in 0014's Module 5 section,
/// see investments_investor_select_own neighborhood) require BOTH
/// `requested_by_person_id = app.current_person_id()` AND
/// `app.is_own_investment_row(investment_id)` — so the current person_id
/// must be sent on INSERT (RLS WITH CHECK will reject the row otherwise,
/// it can't be inferred/defaulted server-side). That's why this service
/// now takes a `Ref` (matching the pattern already used in
/// owner_workspace/state/investor_state.dart's `InvestorApiService(required
/// this.ref)`), reading `authFlowProvider.personId` — the original stub's
/// constructor took no Ref, which cannot satisfy this policy. Flagging
/// this as a required, not optional, signature change to the service
/// constructor (the two public method signatures below are unchanged).
///
/// `investment_withdrawal_requests_investor_select_own` also already
/// scopes fetchInvestment-adjacent reads to the investor's own rows — no
/// redundant person_id filter added here beyond what RLS enforces.
///
/// SCHEMA NOTE (mirrors the flag raised in my_investments_state.dart):
/// `investments` has no `remaining_balance` column. "Available Balance"
/// per the schema's own comment on `investments.principal_amount` IS that
/// column — it already represents the combined Principal+accrued-Interest
/// running balance post Merged Addendum item 2. `original_principal_amount`
/// is used for the separate frozen "Principal" figure IW-004 also shows.
class WithdrawalRequestApiService {
  final Ref ref;
  WithdrawalRequestApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  // Reused read from IW-003's own investment detail data — this screen
  // only needs the Available Balance + Principal slice of that payload.
  Future<InvestmentSummary> fetchInvestment({required String investmentId}) async {
    final row = await _db
        .from('investments')
        .select('investment_id, principal_amount, original_principal_amount')
        .eq('investment_id', investmentId)
        .single();

    return InvestmentSummary(
      investmentId: row['investment_id'] as String,
      // principal_amount is the current combined Principal+Interest
      // balance (schema comment, Merged Addendum item 2) — this IS
      // "Available Balance" for withdrawal purposes.
      availableBalance: (row['principal_amount'] as num).toInt(),
      // original_principal_amount is the frozen Agreement Snapshot value
      // (BR-034) — used here for the separate "Principal" figure IW-004
      // displays alongside Available Balance.
      principalAmount: (row['original_principal_amount'] as num).toInt(),
    );
  }

  Future<WithdrawalRequestRecord> submitRequest({
    required String investmentId,
    required WithdrawalType withdrawalType,
    required int requestedAmount, // whole rupees (M8)
    String? remarks,
  }) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      throw StateError('No logged-in person_id available — cannot satisfy requested_by_person_id (RLS WITH CHECK).');
    }
    final row = await _db
        .from('investment_withdrawal_requests')
        .insert({
          'investment_id': investmentId,
          'requested_by_person_id': int.parse(personId),
          'withdrawal_type': withdrawalType.label,
          'requested_amount': requestedAmount,
          'remarks': remarks,
          'status': 'Pending',
        })
        .select('request_id, status')
        .single();

    return WithdrawalRequestRecord(
      requestId: row['request_id'] as String,
      status: row['status'] as String,
    );
  }
}

final withdrawalRequestApiServiceProvider = Provider<WithdrawalRequestApiService>((ref) {
  return WithdrawalRequestApiService(ref: ref);
});

enum WithdrawalType {
  interestOnly('Interest Only'),
  principalPartial('Principal Partial'),
  principalFull('Principal Full'),
  principalPlusInterest('Principal + Interest');

  final String label;
  const WithdrawalType(this.label);
}

class InvestmentSummary {
  final String investmentId;
  final int availableBalance; // Principal + Unpaid Interest
  final int principalAmount;

  InvestmentSummary({required this.investmentId, required this.availableBalance, required this.principalAmount});
}

class WithdrawalRequestRecord {
  final String requestId;
  final String status; // Pending | Approved-Paid | Rejected
  WithdrawalRequestRecord({required this.requestId, required this.status});
}

class WithdrawalRequestState {
  final bool loadingInvestment;
  final InvestmentSummary? investment;
  final String? error;
  final bool submitting;

  const WithdrawalRequestState({
    this.loadingInvestment = false,
    this.investment,
    this.error,
    this.submitting = false,
  });

  // S5 Withdraw Disabled — Available Balance < ₹1.00.
  bool get withdrawDisabled => investment == null || investment!.availableBalance < 1.0;

  WithdrawalRequestState copyWith({
    bool? loadingInvestment,
    InvestmentSummary? investment,
    String? error,
    bool clearError = false,
    bool? submitting,
  }) {
    return WithdrawalRequestState(
      loadingInvestment: loadingInvestment ?? this.loadingInvestment,
      investment: investment ?? this.investment,
      error: clearError ? null : (error ?? this.error),
      submitting: submitting ?? this.submitting,
    );
  }
}

class WithdrawalRequestNotifier extends Notifier<WithdrawalRequestState> {
  String? _investmentId;

  @override
  WithdrawalRequestState build() => const WithdrawalRequestState();

  /// fallbackSnapshot lets the balance render immediately (handed off
  /// from IW-003) while the fresh fetch is in flight — replaced once
  /// the real fetch resolves.
  Future<void> loadInvestment({required String investmentId, InvestmentSummary? fallbackSnapshot}) async {
    _investmentId = investmentId;
    state = state.copyWith(
      loadingInvestment: true,
      investment: fallbackSnapshot,
      clearError: true,
    );
    try {
      final api = ref.read(withdrawalRequestApiServiceProvider);
      final investment = await api.fetchInvestment(investmentId: investmentId);
      state = state.copyWith(loadingInvestment: false, investment: investment);
    } catch (e) {
      state = state.copyWith(
        loadingInvestment: false,
        error: fallbackSnapshot == null ? e.toString() : null,
      );
    }
  }

  Future<WithdrawalRequestRecord?> submit({
    required WithdrawalType withdrawalType,
    required int requestedAmount,
    String? remarks,
  }) async {
    final investmentId = _investmentId;
    if (investmentId == null) return null;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final api = ref.read(withdrawalRequestApiServiceProvider);
      final record = await api.submitRequest(
        investmentId: investmentId,
        withdrawalType: withdrawalType,
        requestedAmount: requestedAmount,
        remarks: remarks,
      );
      state = state.copyWith(submitting: false);
      return record;
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
      return null;
    }
  }
}

final withdrawalRequestProvider = NotifierProvider<WithdrawalRequestNotifier, WithdrawalRequestState>(
  WithdrawalRequestNotifier.new,
);

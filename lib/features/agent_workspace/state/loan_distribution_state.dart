import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AG-007 Loan Distribution — real Supabase wiring for the BF Cash
/// Transfer piece only (`cash_transfers` table). The 5-step loan-issuance
/// wizard itself is owner_workspace/state/loan_wizard_state.dart, reused
/// as-is per AG-007's own spec ("same 5-step wizard mechanics already
/// locked at OW-005 — no redefinition") — out of this file's scope and
/// out of this sub-chat's file ownership boundary regardless.
///
/// RLS FINDING (this pass — corrects the previous version of this file):
/// `0014_rls_module2to5_config_customer_agent_investor.sql` grants Agent
/// **SELECT only** on `cash_transfers`
/// (`cash_transfers_agent_select_party`) — there is NO Agent INSERT policy
/// and NO Agent UPDATE policy at all (`cash_transfers_owner_all` is
/// Owner-only for every other verb). The previous version of this file
/// had `initiateTransfer` issuing a raw `.insert()` — that would have
/// compiled fine but failed at runtime with an RLS-denied error on every
/// real Agent call, which is worse than an honest stub (a caller
/// debugging a silent/opaque Postgrest 403 loses more time than one
/// debugging a clear `UnimplementedError` with the RPC name). Both
/// `initiateTransfer` and `confirmTransfer` are therefore stubbed as
/// BLOCKED ON RPC below, consistent with the same treatment already used
/// in agent_dashboard_state.dart for `agent_bf_assignments`/
/// `account_periods` writes that hit the identical RLS shape.
///
/// SECOND RLS FINDING: even `listTransfers` (which Agent CAN read) cannot
/// resolve the counterparty Agent's name via a nested embed. `agents`
/// RLS (`agents_self_select`) only allows an Agent to read their OWN
/// `agents` row — there is no policy letting Agent A read Agent B's row
/// at all, regardless of any permission flag. So
/// `agents!cash_transfers_from_agent_id_fkey(persons(full_name))`-style
/// embeds will silently return null for whichever side is NOT the
/// caller, on every single call, not just some of the time. This is not
/// a bug introduced here — it's a structural consequence of the RLS as
/// delivered — but it was undocumented in the previous version, which
/// just silently defaulted the name to `''` without explaining why.
/// Flagged; not fixed, since fixing it means adding a new RLS policy or a
/// SECURITY DEFINER view/RPC exposing minimal counterparty-name lookup,
/// and this chat does not own the RLS migrations.
class CashTransferApiService {
  SupabaseClient get _db => Supabase.instance.client;

  // BLOCKED ON RPC: no Agent INSERT policy exists on `cash_transfers`
  // (see class doc above) — a raw `.insert()` here would be RLS-denied
  // every time for an Agent caller, not just architecturally undesirable.
  // Expected once built: supabase.rpc('initiate_cash_transfer', params: {
  //   'p_from_agent_id': fromAgentId,
  //   'p_to_agent_id': toAgentId,
  //   'p_amount': amount,
  //   'p_business_date': businessDate,
  // }) — a SECURITY DEFINER function that inserts the row (and should
  // itself verify the caller's person_id resolves to from_agent_id,
  // rather than trusting a client-supplied fromAgentId, exactly the same
  // "let the RPC establish identity" reasoning noted for confirmTransfer
  // below).
  // FIXED (this pass): app.initiate_cash_transfer RPC now exists
  // (migration 0021). That RPC resolves from_agent_id from the CALLER's
  // own identity server-side (matching confirmTransfer's own
  // already-established design principle below) — it does not take
  // fromAgentId as an input at all, so a client-supplied fromAgentId here
  // would be silently ignored by the RPC even if sent. Rather than pretend
  // this method still meaningfully uses that param, it's kept in the
  // signature (unused) only because the notifier caller already passes it
  // — not removed, to avoid yet another signature-change ripple, but
  // flagged. Returns only the new transfer_id (the RPC doesn't return a
  // full row) — the notifier below refreshes via loadTransfers for
  // complete, accurate display data rather than this method constructing
  // an incomplete CashTransfer object with a missing fromAgentName.
  Future<String> initiateTransfer({
    required String fromAgentId,
    required String toAgentId,
    required String toAgentName,
    required int amount, // whole rupees (M8)
    required String businessDate,
  }) async {
    final transferId = await _db.schema('app').rpc('initiate_cash_transfer', params: {
      'p_to_agent_id': toAgentId,
      'p_amount': amount,
      'p_business_date': businessDate,
    });
    return transferId as String;
  }

  Future<List<CashTransfer>> listTransfers({
    required String agentId,
    String? direction,
    String? status,
  }) async {
    var q = _db
        .from('cash_transfers')
        .select('transfer_id, from_agent_id, to_agent_id, amount, business_date, entry_timestamp, '
            'from_agent_confirmed_at, to_agent_confirmed_at, '
            'from_agent:agents!cash_transfers_from_agent_id_fkey(persons(full_name)), '
            'to_agent:agents!cash_transfers_to_agent_id_fkey(persons(full_name))');
    if (direction == 'incoming') {
      q = q.eq('to_agent_id', agentId);
    } else if (direction == 'outgoing') {
      q = q.eq('from_agent_id', agentId);
    } else {
      q = q.or('from_agent_id.eq.$agentId,to_agent_id.eq.$agentId');
    }
    final rows = await q.order('entry_timestamp', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final fromAgent = r['from_agent'] as Map<String, dynamic>?;
      final toAgent = r['to_agent'] as Map<String, dynamic>?;
      // NOTE (see class doc "SECOND RLS FINDING"): whichever side is NOT
      // `agentId` (the caller) will have its `agents` row filtered out by
      // agents_self_select before persons.full_name is even reached — the
      // name below will be '' for the counterparty on every row, not
      // just intermittently. This is a real, permanent gap, not a
      // best-effort fallback for occasional nulls.
      return _fromRow(
        r,
        fromAgentNameOverride: (fromAgent?['persons'] as Map<String, dynamic>?)?['full_name'] as String?,
        toAgentNameOverride: (toAgent?['persons'] as Map<String, dynamic>?)?['full_name'] as String?,
      );
    }).where((t) {
      if (status == null) return true;
      final actualStatus = t.isComplete ? 'Complete' : 'Pending';
      return actualStatus == status;
    }).toList();
  }

  CashTransfer _fromRow(Map<String, dynamic> r, {String? fromAgentNameOverride, String? toAgentNameOverride}) {
    return CashTransfer(
      transferId: r['transfer_id'] as String,
      fromAgentId: r['from_agent_id'] as String,
      fromAgentName: fromAgentNameOverride ?? '',
      toAgentId: r['to_agent_id'] as String,
      toAgentName: toAgentNameOverride ?? '',
      amount: (r['amount'] as num).toInt(),
      businessDate: r['business_date'] as String,
      createdAt: DateTime.parse(r['entry_timestamp'] as String),
      fromAgentConfirmedAt:
          r['from_agent_confirmed_at'] != null ? DateTime.parse(r['from_agent_confirmed_at'] as String) : null,
      toAgentConfirmedAt:
          r['to_agent_confirmed_at'] != null ? DateTime.parse(r['to_agent_confirmed_at'] as String) : null,
    );
  }

  // BLOCKED ON RPC: no Agent UPDATE policy exists on `cash_transfers`
  // either (same RLS section as initiateTransfer above) — confirming a
  // transfer means setting from_agent_confirmed_at OR
  // to_agent_confirmed_at depending on which side the caller is, and RLS
  // grants Agent zero write access to do that directly.
  //
  // DESIGN NOTE (resolves the previous version's "caller-side ambiguity"
  // flag, not just re-flags it): the earlier stub worried it couldn't
  // tell whether the caller was from_agent or to_agent from `transferId`
  // alone. That's the wrong place to resolve it anyway — a client-
  // supplied "which side am I" flag is exactly the kind of input a
  // SECURITY DEFINER RPC should NOT trust. The correct design is for the
  // RPC itself to look up the caller's own agent_id (via
  // app.current_person_id() -> agents.person_id, mirroring
  // app.active_membership_id()'s pattern in 0012) and set whichever
  // column matches — the RPC needs only p_transfer_id, nothing else, so
  // this method's signature intentionally stays exactly as it was.
  // Expected once built: supabase.rpc('confirm_cash_transfer', params: {
  //   'p_transfer_id': transferId,
  // })
  // FIXED (this pass): app.confirm_cash_transfer RPC now exists (migration
  // 0021). It resolves which side (from/to) the caller is server-side via
  // their own agent_id — confirms the DESIGN NOTE below was followed
  // correctly: this method's signature deliberately takes no "which side"
  // flag, matching the RPC exactly.
  Future<void> confirmTransfer({required String transferId}) async {
    await _db.schema('app').rpc('confirm_cash_transfer', params: {'p_transfer_id': transferId});
  }
}

final cashTransferApiServiceProvider = Provider<CashTransferApiService>((ref) {
  return CashTransferApiService();
});

// ============================================================================
// Models
// ============================================================================

class CashTransfer {
  final String transferId;
  final String fromAgentId;
  final String fromAgentName;
  final String toAgentId;
  final String toAgentName;
  final int amount;
  final String businessDate;
  final DateTime createdAt;
  final DateTime? fromAgentConfirmedAt;
  final DateTime? toAgentConfirmedAt;

  CashTransfer({
    required this.transferId,
    required this.fromAgentId,
    required this.fromAgentName,
    required this.toAgentId,
    required this.toAgentName,
    required this.amount,
    required this.businessDate,
    required this.createdAt,
    this.fromAgentConfirmedAt,
    this.toAgentConfirmedAt,
  });

  bool get isComplete => fromAgentConfirmedAt != null && toAgentConfirmedAt != null;

  String direction(String currentAgentId) => currentAgentId == fromAgentId ? 'Outgoing' : 'Incoming';

  bool needsMyConfirmation(String currentAgentId) {
    if (currentAgentId == toAgentId) return toAgentConfirmedAt == null;
    if (currentAgentId == fromAgentId) return fromAgentConfirmedAt == null;
    return false;
  }
}

// ============================================================================
// State
// ============================================================================

class LoanDistributionState {
  final bool loadingTransfers;
  final List<CashTransfer> transfers;
  final bool sendingTransfer;
  final bool confirmingTransferId;
  final String? error;

  const LoanDistributionState({
    this.loadingTransfers = false,
    this.transfers = const [],
    this.sendingTransfer = false,
    this.confirmingTransferId = false,
    this.error,
  });

  List<CashTransfer> incoming(String agentId) =>
      transfers.where((t) => t.toAgentId == agentId && !t.isComplete).toList();
  List<CashTransfer> outgoing(String agentId) =>
      transfers.where((t) => t.fromAgentId == agentId && !t.isComplete).toList();
  List<CashTransfer> completed() => transfers.where((t) => t.isComplete).toList();

  LoanDistributionState copyWith({
    bool? loadingTransfers,
    List<CashTransfer>? transfers,
    bool? sendingTransfer,
    bool? confirmingTransferId,
    String? error,
    bool clearError = false,
  }) {
    return LoanDistributionState(
      loadingTransfers: loadingTransfers ?? this.loadingTransfers,
      transfers: transfers ?? this.transfers,
      sendingTransfer: sendingTransfer ?? this.sendingTransfer,
      confirmingTransferId: confirmingTransferId ?? this.confirmingTransferId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LoanDistributionNotifier extends Notifier<LoanDistributionState> {
  @override
  LoanDistributionState build() => const LoanDistributionState();

  Future<void> loadTransfers({required String agentId}) async {
    state = state.copyWith(loadingTransfers: true, clearError: true);
    try {
      final api = ref.read(cashTransferApiServiceProvider);
      final transfers = await api.listTransfers(agentId: agentId);
      state = state.copyWith(loadingTransfers: false, transfers: transfers);
    } catch (e) {
      state = state.copyWith(loadingTransfers: false, error: e.toString());
    }
  }

  Future<bool> sendTransfer({
    required String fromAgentId,
    required String toAgentId,
    required String toAgentName,
    required int amount, // whole rupees (M8)
    required String businessDate,
  }) async {
    state = state.copyWith(sendingTransfer: true, clearError: true);
    try {
      final api = ref.read(cashTransferApiServiceProvider);
      await api.initiateTransfer(
        fromAgentId: fromAgentId,
        toAgentId: toAgentId,
        toAgentName: toAgentName,
        amount: amount,
        businessDate: businessDate,
      );
      // initiateTransfer now returns only the new transfer_id (the RPC
      // doesn't return a full row — from_agent_id/fromAgentName aren't
      // available to construct a complete CashTransfer client-side).
      // Refresh the list from source instead of appending a partial
      // object, same pattern confirmTransfer below already uses.
      state = state.copyWith(sendingTransfer: false);
      await loadTransfers(agentId: fromAgentId);
      return true;
    } catch (e) {
      state = state.copyWith(sendingTransfer: false, error: e.toString());
      return false;
    }
  }

  Future<bool> confirmTransfer({required String transferId, required String agentId}) async {
    state = state.copyWith(confirmingTransferId: true, clearError: true);
    try {
      final api = ref.read(cashTransferApiServiceProvider);
      // Note: `agentId` is intentionally NOT forwarded to
      // api.confirmTransfer — see the DESIGN NOTE on that method. It's
      // kept as a parameter here only because the screen (which this
      // sub-chat does not own/edit) already calls this Notifier method
      // with it, and it's still useful for the subsequent loadTransfers
      // refresh below.
      await api.confirmTransfer(transferId: transferId);
      await loadTransfers(agentId: agentId);
      state = state.copyWith(confirmingTransferId: false);
      return true;
    } catch (e) {
      state = state.copyWith(confirmingTransferId: false, error: e.toString());
      return false;
    }
  }
}

final loanDistributionProvider = NotifierProvider<LoanDistributionNotifier, LoanDistributionState>(
  LoanDistributionNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OW-007 Loan Details — real Supabase wiring over Module 6/7.
///
/// SCHEMA GAP FOUND (this session, not in the original stub's own
/// flagging): the real `loans` table has NO `remarks` or
/// `future_effective_information` column — the stub's editAllowedFields/
/// addRemark methods assumed both exist directly on `loans`, matching the
/// original spec's PATCH-field list, but 0007_module6_loan_domain.sql has
/// neither. `collection_agent_membership_id` DOES exist and is wired.
/// remarks/future_effective_information are left genuinely unimplemented
/// (not silently dropped, not guessed into some other table) — flagged
/// for master chat: either a schema addendum adding these columns, or a
/// dedicated loan_remarks table analogous to customer_remarks.
class LoanDetailsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<LoanDetail> fetchLoanDetail({required String loanId}) async {
    final row = await _db
        .from('loans')
        .select('''
          loan_id, loan_number, loan_status, repayment_type, installment_amount,
          repayment_amount, amount_given, remaining_balance,
          collection_agent_membership_id,
          customers!inner(customer_id, persons!inner(full_name)),
          business_members!loans_collection_agent_membership_id_fkey(persons(full_name)),
          guarantors(guarantor_id, guarantor_name, relationship, phone, address, remarks, status),
          loan_schedule(schedule_id, status),
          penalty_entries(penalty_id, penalty_option, penalty_amount_applied, entry_timestamp, is_waived_or_reduced)
        ''')
        .eq('loan_id', loanId)
        .single();

    final customer = row['customers'] as Map<String, dynamic>;
    final customerPerson = customer['persons'] as Map<String, dynamic>;
    final agentMember = row['business_members'] as Map<String, dynamic>?;
    final agentPerson = agentMember?['persons'] as Map<String, dynamic>?;
    final schedule = ((row['loan_schedule'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final completed = schedule.where((s) => s['status'] == 'Completed').length;
    final guarantorRows = ((row['guarantors'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final penaltyRows = ((row['penalty_entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final status = _statusFromString(row['loan_status'] as String);

    final penalties = penaltyRows
        .map((p) => PenaltyEntry(
              penaltyEntryId: p['penalty_id'] as String,
              penaltyOption: p['penalty_option'] as String,
              penaltyAmount: (p['penalty_amount_applied'] as num).toDouble(),
              appliedDate: DateTime.parse(p['entry_timestamp'] as String),
              isWaivedOrReduced: p['is_waived_or_reduced'] as bool? ?? false,
            ))
        .toList();

    return LoanDetail(
      loanId: row['loan_id'] as String,
      loanNumber: row['loan_number'] as String,
      customerName: customerPerson['full_name'] as String? ?? '',
      customerId: customer['customer_id'] as String,
      status: status,
      repaymentType: row['repayment_type'] as String,
      installmentAmount: (row['installment_amount'] as num).toDouble(),
      loanAmount: (row['repayment_amount'] as num).toDouble(),
      amountGiven: (row['amount_given'] as num).toDouble(),
      outstandingBalance: (row['remaining_balance'] as num).toDouble(),
      todaysDue: (row['installment_amount'] as num).toDouble(), // precise per-schedule due requires business_date join — see KNOWN SIMPLIFICATION pattern elsewhere this session
      completedInstallments: completed,
      remainingInstallments: schedule.length - completed,
      inGracePeriod: status == LoanStatus.gracePeriod,
      penaltyEligible: status == LoanStatus.penaltyEligible,
      collectionAgentId: row['collection_agent_membership_id'] as String,
      collectionAgentName: agentPerson?['full_name'] as String? ?? '',
      guarantor: guarantorRows.isEmpty
          ? null
          : GuarantorDetail(
              name: guarantorRows.first['guarantor_name'] as String,
              relationship: guarantorRows.first['relationship'] as String,
              phone: guarantorRows.first['phone'] as String,
              address: guarantorRows.first['address'] as String,
              remarks: guarantorRows.first['remarks'] as String?,
            ),
      paymentHistory: const [], // requires a separate collections query scoped by loan_id — not fetched by this detail view
      penaltyEntries: penalties,
      availableActions: const [], // server-computed list per original API BINDING — no such computation exists yet; UI should derive from the getters below instead
      futureEffectiveInformation: null, // schema gap, see class doc
      remarks: null, // schema gap, see class doc
    );
  }

  // NOTE: loan_status_enum (schema) has no 'Penalty Eligible' value — only
  // 'Penalty'. The stub's own LoanStatus model has a separate
  // penaltyEligible/penalty distinction with no matching second DB state;
  // 'Penalty' is mapped to penaltyEligible here since that's the value
  // canApplyPenalty's getter actually checks — mapping it to
  // LoanStatus.penalty instead would make Apply Penalty permanently
  // unreachable against real data.
  LoanStatus _statusFromString(String s) => switch (s) {
        'Draft' => LoanStatus.draft,
        'Active' => LoanStatus.active,
        'Grace Period' => LoanStatus.gracePeriod,
        'Penalty' => LoanStatus.penaltyEligible,
        'Closed' => LoanStatus.closed,
        'Cancelled' => LoanStatus.cancelled,
        'Defaulted' => LoanStatus.defaulted,
        _ => LoanStatus.active,
      };

  Future<void> editAllowedFields({
    required String loanId,
    String? collectionAgentMembershipId,
    String? remarks,
    String? futureEffectiveInformation,
  }) async {
    if (collectionAgentMembershipId != null) {
      await _db.from('loans').update({'collection_agent_membership_id': collectionAgentMembershipId}).eq('loan_id', loanId);
    }
    if (remarks != null || futureEffectiveInformation != null) {
      throw UnimplementedError(
        'remarks/future_effective_information have no backing column on loans — see class-level SCHEMA GAP note.',
      );
    }
  }

  Future<void> transferAgent({required String loanId, required String newAgentMembershipId}) async {
    await _db.from('loans').update({'collection_agent_membership_id': newAgentMembershipId}).eq('loan_id', loanId);
  }

  Future<void> applyPenalty({
    required String loanId,
    required String penaltyOption,
    required double penaltyAmount,
  }) async {
    // BLOCKED ON RPC: applying a penalty must atomically insert
    // penalty_entries AND increase loans.remaining_balance by the same
    // amount (per penalty_entries.penalty_amount_applied's own column
    // comment: "resolved Rs amount added to remaining_balance") — the
    // same class of atomicity requirement already flagged for
    // record_collection/create_loan_with_bf_check elsewhere this session,
    // not something a plain two-step .insert()+.update() can safely
    // guarantee under a dropped connection between steps.
    throw UnimplementedError(
      'BLOCKED on RPC "apply_loan_penalty" (not yet built) — must atomically insert penalty_entries and increase '
      'loans.remaining_balance together; a plain insert+update pair risks a partial write. Expected: '
      "supabase.rpc('apply_loan_penalty', params: {'p_loan_id': loanId, 'p_penalty_option': penaltyOption, "
      "'p_penalty_amount': penaltyAmount})",
    );
  }

  Future<List<PenaltyEntry>> fetchPenaltyEntries({required String loanId}) async {
    final rows = await _db
        .from('penalty_entries')
        .select('penalty_id, penalty_option, penalty_amount_applied, entry_timestamp, is_waived_or_reduced')
        .eq('loan_id', loanId)
        .order('entry_timestamp', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((p) => PenaltyEntry(
              penaltyEntryId: p['penalty_id'] as String,
              penaltyOption: p['penalty_option'] as String,
              penaltyAmount: (p['penalty_amount_applied'] as num).toDouble(),
              appliedDate: DateTime.parse(p['entry_timestamp'] as String),
              isWaivedOrReduced: p['is_waived_or_reduced'] as bool? ?? false,
            ))
        .toList();
  }

  /// Same atomicity concern as applyPenalty above — waiving/reducing must
  /// also reverse the corresponding amount out of loans.remaining_balance.
  Future<void> waiveOrReducePenalty({
    required String penaltyEntryId,
    required bool waive,
    double? reducedAmount,
  }) async {
    throw UnimplementedError(
      'BLOCKED on RPC "waive_loan_penalty" (not yet built) — same atomicity requirement as applyPenalty: must '
      'reverse the corresponding amount out of loans.remaining_balance in the same transaction as marking '
      'is_waived_or_reduced.',
    );
  }

  Future<void> closeLoan({required String loanId, bool writeOffRemaining = false}) async {
    await _db.from('loans').update({
      'loan_status': 'Closed',
      'closed_at': DateTime.now().toIso8601String(),
      if (writeOffRemaining) 'remaining_balance': 0,
    }).eq('loan_id', loanId);
  }

  Future<void> addRemark({required String loanId, required String remark}) async {
    throw UnimplementedError(
      'loans has no remarks column and no dedicated loan_remarks table exists in the delivered schema — see '
      'class-level SCHEMA GAP note. Do not silently write this into customer_remarks; that table is scoped to '
      'customer_id, not loan_id, and would misattribute the remark.',
    );
  }
}

final loanDetailsApiServiceProvider = Provider<LoanDetailsApiService>((ref) {
  return LoanDetailsApiService();
});

class GuarantorDetail {
  final String name;
  final String relationship;
  final String phone;
  final String address;
  final String? remarks;
  GuarantorDetail({
    required this.name,
    required this.relationship,
    required this.phone,
    required this.address,
    this.remarks,
  });
}

class LoanPaymentHistoryRow {
  final DateTime businessDate;
  final String receiptNumber;
  final double amount;
  final String paymentMode;
  final String collector;
  final double difference;
  final String? remarks;
  LoanPaymentHistoryRow({
    required this.businessDate,
    required this.receiptNumber,
    required this.amount,
    required this.paymentMode,
    required this.collector,
    required this.difference,
    this.remarks,
  });
}

class PenaltyEntry {
  final String penaltyEntryId;
  final String penaltyOption;
  final double penaltyAmount;
  final DateTime appliedDate;
  final bool isWaivedOrReduced;
  PenaltyEntry({
    required this.penaltyEntryId,
    required this.penaltyOption,
    required this.penaltyAmount,
    required this.appliedDate,
    required this.isWaivedOrReduced,
  });
}

/// loans.loan_status enum (Merged REMOVED per locked decision) — 'Renewed'
/// does not exist, Loan Renewal feature dropped entirely.
enum LoanStatus { draft, active, gracePeriod, penaltyEligible, penalty, closed, cancelled, defaulted }

class LoanDetail {
  final String loanId;
  final String loanNumber;
  final String customerName;
  final String customerId;
  final LoanStatus status;
  final String repaymentType;
  final double installmentAmount;
  final double loanAmount;
  final double amountGiven;
  final double outstandingBalance;
  final double todaysDue;
  final int completedInstallments;
  final int remainingInstallments;
  final bool inGracePeriod;
  final bool penaltyEligible;
  final String collectionAgentId;
  final String collectionAgentName;
  final GuarantorDetail? guarantor;
  final List<LoanPaymentHistoryRow> paymentHistory;
  final List<PenaltyEntry> penaltyEntries;
  final List<String> availableActions; // server-computed, per API BINDING
  final String? futureEffectiveInformation;
  final String? remarks;

  LoanDetail({
    required this.loanId,
    required this.loanNumber,
    required this.customerName,
    required this.customerId,
    required this.status,
    required this.repaymentType,
    required this.installmentAmount,
    required this.loanAmount,
    required this.amountGiven,
    required this.outstandingBalance,
    required this.todaysDue,
    required this.completedInstallments,
    required this.remainingInstallments,
    required this.inGracePeriod,
    required this.penaltyEligible,
    required this.collectionAgentId,
    required this.collectionAgentName,
    this.guarantor,
    this.paymentHistory = const [],
    this.penaltyEntries = const [],
    this.availableActions = const [],
    this.futureEffectiveInformation,
    this.remarks,
  });

  bool get isReadOnlyFinancials =>
      status == LoanStatus.closed || status == LoanStatus.cancelled || status == LoanStatus.defaulted;

  bool get canCollectPayment => !isReadOnlyFinancials;
  bool get canTransferAgent => !isReadOnlyFinancials;
  bool get canEditAllowedFields => !isReadOnlyFinancials;
  bool get canApplyPenalty => status == LoanStatus.penaltyEligible;
  bool get canWaivePenalty => penaltyEntries.any((p) => !p.isWaivedOrReduced) && !isReadOnlyFinancials;
  bool get canCloseLoan => outstandingBalance <= 0 || status == LoanStatus.defaulted;
}

class LoanDetailsNotifier extends FamilyAsyncNotifier<LoanDetail, String> {
  @override
  Future<LoanDetail> build(String loanId) async {
    return ref.read(loanDetailsApiServiceProvider).fetchLoanDetail(loanId: loanId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(loanDetailsApiServiceProvider).fetchLoanDetail(loanId: arg));
  }

  Future<bool> editAllowedFields({String? remarks, String? futureEffectiveInformation}) async {
    try {
      await ref.read(loanDetailsApiServiceProvider).editAllowedFields(
            loanId: arg,
            remarks: remarks,
            futureEffectiveInformation: futureEffectiveInformation,
          );
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> transferAgent(String newAgentMembershipId) async {
    try {
      await ref.read(loanDetailsApiServiceProvider).transferAgent(loanId: arg, newAgentMembershipId: newAgentMembershipId);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> applyPenalty({required String penaltyOption, required double penaltyAmount}) async {
    try {
      await ref
          .read(loanDetailsApiServiceProvider)
          .applyPenalty(loanId: arg, penaltyOption: penaltyOption, penaltyAmount: penaltyAmount);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> waiveOrReducePenalty({
    required String penaltyEntryId,
    required bool waive,
    double? reducedAmount,
  }) async {
    try {
      await ref
          .read(loanDetailsApiServiceProvider)
          .waiveOrReducePenalty(penaltyEntryId: penaltyEntryId, waive: waive, reducedAmount: reducedAmount);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeLoan({bool writeOffRemaining = false}) async {
    try {
      await ref.read(loanDetailsApiServiceProvider).closeLoan(loanId: arg, writeOffRemaining: writeOffRemaining);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addRemark(String remark) async {
    try {
      await ref.read(loanDetailsApiServiceProvider).addRemark(loanId: arg, remark: remark);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final loanDetailsProvider = AsyncNotifierProvider.family<LoanDetailsNotifier, LoanDetail, String>(
  LoanDetailsNotifier.new,
);

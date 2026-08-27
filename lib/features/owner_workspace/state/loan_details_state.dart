import '../../login_registration/state/auth_flow_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/mana_time.dart';

/// OW-007 Loan Details — real Supabase wiring over Module 6/7.
///
/// The schema gap this class used to carry is closed (migration
/// 20260827123809). It is worth saying what it was, because the shape of the
/// fix was decided by it: `loans` had neither `remarks` nor
/// `future_effective_information`, so editAllowedFields and addRemark both
/// raised UnimplementedError -- OW-007 shipped two buttons whose Save could
/// never succeed.
///
/// They were NOT given the same shape:
///
///   future_effective_information is one editable note, so it is a column on
///   loans. Editing it is the point.
///
///   remarks are an append-only log in `loan_remarks`, mirroring
///   customer_remarks, because a lending record that lets somebody overwrite
///   yesterday's note has lost what a remark is for. Writing them into
///   customer_remarks would have been worse than leaving them broken: that
///   table is scoped to customer_id, not loan_id, and would misattribute a
///   remark about one loan to every loan that customer holds.
class LoanDetailsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<LoanDetail> fetchLoanDetail({required String loanId}) async {
    final row = await _db
        .from('loans')
        .select('''
          loan_id, business_id, loan_number, loan_status, repayment_type, installment_amount,
          repayment_amount, amount_given, remaining_balance, grace_period_days,
          collection_agent_membership_id, future_effective_information,
          customers!inner(customer_id, persons!inner(full_name)),
          business_members!loans_collection_agent_membership_id_fkey(persons!business_members_person_id_fkey(full_name)),
          guarantors(guarantor_id, guarantor_name, relationship, phone, address, remarks, status),
          loan_schedule(schedule_id, status, due_date),
          penalty_entries(penalty_id, penalty_option, penalty_amount_applied, entry_timestamp, is_waived_or_reduced)
        ''')
        .eq('loan_id', loanId)
        .single();

    final customer = row['customers'] as Map<String, dynamic>;
    final customerPerson = customer['persons'] as Map<String, dynamic>;
    final agentMember = row['business_members'] as Map<String, dynamic>?;
    final agentPerson = agentMember?['persons'] as Map<String, dynamic>?;
    final schedule = ((row['loan_schedule'] as List?) ?? const []).cast<Map<String, dynamic>>();

    // Instalments completed come from the BALANCE, not from loan_schedule.
    //
    // They used to be `schedule.where(status == 'Completed').length`, and
    // every loan in the app reported 0. Not a rounding slip -- all 8,075
    // schedule rows in the database are 'Pending'. record_collection has
    // never written that column, so the schedule is a plan that was written
    // once and never advanced, and a loan with eleven collections against it
    // still read "Completed Installments 0".
    //
    // Marking rows Completed as money lands would need a payment waterfall to
    // decide what a part-payment completes, and this app deliberately has
    // none: one remaining_balance per loan is the whole model. So the count
    // is derived from what is actually owed, which is the figure the rest of
    // the app already trusts.
    //
    // It agrees with reality on live rows: a loan of 12,000 at 1,000 with
    // 1,000 left and eleven collections recorded derives eleven completed.
    //
    // It is also the only version that works for a MIGRATED loan, whose
    // schedule holds what is LEFT rather than the whole term -- counting rows
    // there answers a different question entirely.
    final emi = (row['installment_amount'] as num).toInt();
    final repayment = (row['repayment_amount'] as num).toInt();
    final owed = (row['remaining_balance'] as num).toInt();
    final totalInstallments = emi > 0 ? (repayment / emi).ceil() : schedule.length;
    final completed = emi > 0
        ? ((repayment - owed) / emi).floor().clamp(0, totalInstallments)
        : 0;
    final guarantorRows = ((row['guarantors'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final penaltyRows = ((row['penalty_entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final status = _statusFromString(row['loan_status'] as String);

    // Overdue-past-grace is computed from the schedule, NOT read off
    // loan_status. `loan_status = 'Penalty'` exists in the enum but nothing
    // in this codebase ever writes it — loans are created 'Active' by
    // create_loan_with_bf_check and only ever move to 'Closed' — so gating
    // the Apply Penalty action on that status made it permanently
    // unreachable. This reads the same boundary function the server's own
    // hard gate uses (app.loan_penalty_eligible_from), so the button and the
    // RPC cannot disagree about when a penalty is allowed.
    final lastDue = schedule
        .map((s) => DateTime.parse(s['due_date'] as String))
        .fold<DateTime?>(null, (max, d) => max == null || d.isAfter(max) ? d : max);
    final graceDays = (row['grace_period_days'] as num?)?.toInt() ?? 0;
    final penaltyEligibleFrom = lastDue?.add(Duration(days: graceDays + 1));

    final penalties = penaltyRows
        .map((p) => PenaltyEntry(
              penaltyEntryId: p['penalty_id'] as String,
              penaltyOption: p['penalty_option'] as String,
              penaltyAmount: (p['penalty_amount_applied'] as num).toInt(),
              appliedDate: DateTime.parse(p['entry_timestamp'] as String),
              isWaivedOrReduced: p['is_waived_or_reduced'] as bool? ?? false,
            ))
        .toList();

    return LoanDetail(
      loanId: row['loan_id'] as String,
      businessId: row['business_id'] as String,
      loanNumber: row['loan_number'] as String,
      customerName: customerPerson['full_name'] as String? ?? '',
      customerId: customer['customer_id'] as String,
      status: status,
      repaymentType: row['repayment_type'] as String,
      installmentAmount: (row['installment_amount'] as num).toInt(),
      loanAmount: (row['repayment_amount'] as num).toInt(),
      amountGiven: (row['amount_given'] as num).toInt(),
      outstandingBalance: (row['remaining_balance'] as num).toInt(),
      todaysDue: (row['installment_amount'] as num).toInt(), // precise per-schedule due requires business_date join — see KNOWN SIMPLIFICATION pattern elsewhere this session
      gracePeriodDays: graceDays,
      completedInstallments: completed,
      // Against the total the loan actually has, not against however many
      // schedule rows happen to exist.
      remainingInstallments: (totalInstallments - completed).clamp(0, totalInstallments),
      inGracePeriod: status == LoanStatus.gracePeriod,
      penaltyEligibleFrom: penaltyEligibleFrom,
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
      futureEffectiveInformation:
          row['future_effective_information'] as String?,
      // Remarks are a separate append-only table, loaded by
      // fetchRemarks -- not a column on the loan.
      remarks: const [],
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

  /// Grants grace on a running loan.
  ///
  /// Stops FUTURE penalties and never touches one already applied: an applied
  /// penalty is already inside remaining_balance, so clearing it here would
  /// move what the customer owes, days later, from a screen about dates. Use
  /// Waive / Reduce Penalty for that -- it says so and records who did it.
  Future<void> grantGracePeriod({
    required String loanId,
    required int days,
    required String reason,
  }) async {
    await _db.schema('app').rpc('grant_grace_period', params: {
      'p_loan_id': loanId,
      'p_days': days,
      'p_reason': reason,
    });
  }

  /// No `remarks` parameter, deliberately. Remarks are append-only and go
  /// through addRemark; an "edit" that overwrites one is exactly what the
  /// append-only rule exists to prevent.
  Future<void> editAllowedFields({
    required String loanId,
    String? collectionAgentMembershipId,
    String? futureEffectiveInformation,
  }) async {
    final patch = <String, dynamic>{
      if (collectionAgentMembershipId != null)
        'collection_agent_membership_id': collectionAgentMembershipId,
      if (futureEffectiveInformation != null)
        // Cleared, not blanked: an empty box means "there is no note", and a
        // null reads that way everywhere else in this file.
        'future_effective_information':
            futureEffectiveInformation.isEmpty ? null : futureEffectiveInformation,
    };
    if (patch.isEmpty) return;

    // Read back. PostgREST answers an UPDATE that matched no rows exactly
    // like one that matched, so without this a save the Owner is not
    // permitted to make reports success -- the same defect the loan transfer
    // had.
    final rows = await _db
        .from('loans')
        .update(patch)
        .eq('loan_id', loanId)
        .select('loan_id');
    if (rows.isEmpty) {
      throw Exception(
          'The change did not save. You may not have permission to edit this loan.');
    }
  }

  /// Reads the row back, because PostgREST answers an UPDATE that matched
  /// nothing exactly like one that matched. A bare update here could not tell
  /// a completed transfer from a loan the caller may not touch -- and the
  /// screen above it reported success either way.
  Future<void> transferAgent({required String loanId, required String newAgentMembershipId}) async {
    final rows = await _db
        .from('loans')
        .update({'collection_agent_membership_id': newAgentMembershipId})
        .eq('loan_id', loanId)
        .select('loan_id');
    if (rows.isEmpty) {
      throw Exception('The transfer did not save. You may not have permission to change this loan.');
    }
  }

  /// Applying a penalty must atomically insert penalty_entries AND increase
  /// loans.remaining_balance by the same amount (per
  /// penalty_entries.penalty_amount_applied's own column comment: "resolved
  /// Rs amount added to remaining_balance"). Now backed by

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
              penaltyAmount: (p['penalty_amount_applied'] as num).toInt(),
              appliedDate: DateTime.parse(p['entry_timestamp'] as String),
              isWaivedOrReduced: p['is_waived_or_reduced'] as bool? ?? false,
            ))
        .toList();
  }

  /// Same atomicity concern as applyPenalty above — waiving/reducing must
  /// also reverse the corresponding amount out of loans.remaining_balance.
  /// Backed by `app.waive_loan_penalty` (migration 0054); returns the rupee
  /// amount actually reversed.
  ///
  /// NOTE: the RPC overwrites penalty_amount_applied with the new effective
  /// amount (0 on a full waive), so the originally-applied figure is not
  /// recoverable afterwards — there is no penalty history table in the
  /// schema to hold it. See the 0054 header for why consistency with
  /// remaining_balance was chosen over preserving the original.
  Future<int> waiveOrReducePenalty({
    required String penaltyEntryId,
    required bool waive,
    int? reducedAmount,
  }) async {
    final result = await _db.schema('app').rpc('waive_loan_penalty', params: {
      'p_penalty_id': penaltyEntryId,
      'p_waive': waive,
      'p_reduced_amount': reducedAmount,
    });
    return (result as num).toInt();
  }

  /// Backed by `app.close_loan` (migration 0055) rather than a raw UPDATE,
  /// because closing a loan is ALSO the penalty recognition event and the two
  /// must not be separable. The server recognises penalty income only when
  /// the balance was already zero before this call — a genuine payoff — so a
  /// write-off (and therefore a Defaulted or Cancelled loan) recognises
  /// nothing. Returns what was actually recognised so the screen can report
  /// it instead of guessing.
  Future<LoanCloseResult> closeLoan({required String loanId, bool writeOffRemaining = false}) async {
    final result = await _db.schema('app').rpc('close_loan', params: {
      'p_loan_id': loanId,
      'p_write_off': writeOffRemaining,
    }) as Map<String, dynamic>;
    return LoanCloseResult(
      writtenOff: result['written_off'] as bool? ?? false,
      penaltyRecognised: ((result['penalty_recognised'] as num?) ?? 0).toInt(),
      recognisedBusinessDate: result['recognised_business_date'] as String?,
    );
  }

  /// First date a penalty may be applied — last installment's due_date +
  /// grace_period_days + 1. Null when the loan has no schedule at all, in
  /// which case `applyPenalty` will reject. Lets OW-007 disable the Apply
  /// Penalty action and say *when* it unlocks, rather than letting the Owner
  /// type an amount and only then hit the server's rejection.
  Future<DateTime?> penaltyEligibleFrom({required String loanId}) async {
    final result = await _db.schema('app').rpc('loan_penalty_eligible_from', params: {
      'p_loan_id': loanId,
    });
    return result == null ? null : DateTime.parse(result as String);
  }

  Future<void> addRemark({
    required String loanId,
    required String remark,
    required int enteredByPersonId,
  }) async {
    final rows = await _db
        .from('loan_remarks')
        .insert({
          'loan_id': loanId,
          'remark_text': remark,
          'entered_by_person_id': enteredByPersonId,
        })
        .select('remark_id');
    if (rows.isEmpty) {
      throw Exception('The remark did not save.');
    }
  }

  /// The loan's remarks, newest first. A separate query rather than an embed:
  /// loan_remarks reaches persons through entered_by_person_id, and this file
  /// already embeds persons twice through other paths -- a third would be the
  /// ambiguous-embed error (PGRST201) the guard test exists to catch.
  Future<List<LoanRemark>> fetchRemarks({required String loanId}) async {
    final rows = await _db
        .from('loan_remarks')
        .select('remark_id, remark_text, business_date, created_at')
        .eq('loan_id', loanId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => LoanRemark(
              remarkId: r['remark_id'] as String,
              text: r['remark_text'] as String,
              businessDate: DateTime.parse(r['business_date'] as String),
            ))
        .toList();
  }
}

/// What `app.close_loan` actually did — a write-off and a payoff both leave
/// the loan Closed at a zero balance, but only the payoff recognises penalty
/// income, and only the server can tell them apart (it sees the balance
/// before the write).
class LoanCloseResult {
  final bool writtenOff;
  final int penaltyRecognised;
  final String? recognisedBusinessDate;

  const LoanCloseResult({
    required this.writtenOff,
    required this.penaltyRecognised,
    this.recognisedBusinessDate,
  });

  bool get recognisedPenalty => penaltyRecognised > 0;
}

final loanDetailsApiServiceProvider = Provider<LoanDetailsApiService>((ref) {
  return LoanDetailsApiService();
});

/// One remark on a loan. Append-only: there is no edit and no id-based
/// update anywhere above this, by design -- see the class note on
/// LoanDetailsApiService.
class LoanRemark {
  final String remarkId;
  final String text;

  /// The Indian calendar day the remark belongs to, which is what the book
  /// is kept in -- not the wall-clock timestamp it was typed at.
  final DateTime businessDate;

  const LoanRemark({
    required this.remarkId,
    required this.text,
    required this.businessDate,
  });
}

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
  final int amount;
  final String paymentMode;
  final String collector;
  final int difference;
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
  final int penaltyAmount;
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

  /// Which book this loan belongs to. Needed by anything that has to look up
  /// the business's own people -- the agent picker, for one, which used to be
  /// handed the string 'stub-agent-id' instead.
  final String businessId;
  final String loanNumber;
  final String customerName;
  final String customerId;
  final LoanStatus status;
  final String repaymentType;
  final int installmentAmount;
  final int loanAmount;
  final int amountGiven;
  final int outstandingBalance;
  final int todaysDue;
  /// Days of grace currently granted on this loan. The Grace Period dialog
  /// opens on it, so somebody extending 14 days to 21 sees 14 rather than
  /// an empty box that would read as none.
  final int gracePeriodDays;
  final int completedInstallments;
  final int remainingInstallments;
  final bool inGracePeriod;
  /// First date a penalty may be applied: last installment's due_date +
  /// grace_period_days + 1. Null when the loan has no schedule rows, in
  /// which case eligibility cannot be assessed and stays false. Mirrors
  /// `app.loan_penalty_eligible_from`, which the server's hard gate uses.
  final DateTime? penaltyEligibleFrom;
  final String collectionAgentId;
  final String collectionAgentName;
  final GuarantorDetail? guarantor;
  final List<LoanPaymentHistoryRow> paymentHistory;
  final List<PenaltyEntry> penaltyEntries;
  final List<String> availableActions; // server-computed, per API BINDING
  final String? futureEffectiveInformation;

  /// Append-only, newest first. Empty until fetchRemarks has run.
  final List<LoanRemark> remarks;

  LoanDetail({
    required this.loanId,
    required this.businessId,
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
    this.gracePeriodDays = 0,
    required this.completedInstallments,
    required this.remainingInstallments,
    required this.inGracePeriod,
    this.penaltyEligibleFrom,
    required this.collectionAgentId,
    required this.collectionAgentName,
    this.guarantor,
    this.paymentHistory = const [],
    this.penaltyEntries = const [],
    this.availableActions = const [],
    this.futureEffectiveInformation,
    this.remarks = const [],
  });

  bool get isReadOnlyFinancials =>
      status == LoanStatus.closed || status == LoanStatus.cancelled || status == LoanStatus.defaulted;

  bool get canCollectPayment => !isReadOnlyFinancials;
  bool get canTransferAgent => !isReadOnlyFinancials;
  bool get canEditAllowedFields => !isReadOnlyFinancials;
  /// "Loan not paid AND past both due date and grace period" — the same two
  /// conditions `app.apply_loan_penalty` enforces server-side. Not read off
  /// loan_status: the 'Penalty' status this used to check is never written by
  /// anything, which made the action permanently unreachable.
  bool get penaltyEligible {
    if (penaltyEligibleFrom == null) return false;
    final today = manaNowIst();
    final todayDate = DateTime(today.year, today.month, today.day);
    return outstandingBalance > 0 && !todayDate.isBefore(penaltyEligibleFrom!);
  }

  bool get canApplyPenalty => penaltyEligible && !isReadOnlyFinancials;
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

  /// Rethrows. `catch (_) => false` turned every failure into a bare "it
  /// didn't work" with the reason discarded -- a permission refusal, an
  /// expired session and a dropped connection all looked identical, and the
  /// screen above could not say which. NetworkErrorHandler shows the real
  /// message when it is allowed to see one.
  Future<bool> editAllowedFields({String? futureEffectiveInformation}) async {
    await ref.read(loanDetailsApiServiceProvider).editAllowedFields(
          loanId: arg,
          futureEffectiveInformation: futureEffectiveInformation,
        );
    await refresh();
    return true;
  }

  /// Throws rather than returning false.
  ///
  /// `catch (_) { return false; }` threw away the server's own reason, and the
  /// screen showed "Agent transferred" without even reading the false. Letting
  /// it through means NetworkErrorHandler says what actually happened.
  Future<void> transferAgent(String newAgentMembershipId) async {
    await ref
        .read(loanDetailsApiServiceProvider)
        .transferAgent(loanId: arg, newAgentMembershipId: newAgentMembershipId);
    await refresh();
  }

  // applyPenalty is gone from here.
  //
  // It required a penalty OPTION, and the only screen that called it has moved
  // to the shared sheet, which asks for an amount and nothing else. Leaving a
  // second path to the same money write -- one that still demanded a choice
  // nobody makes -- is how the two drift apart.

  Future<int> waiveOrReducePenalty({
    required String penaltyEntryId,
    required bool waive,
    int? reducedAmount,
  }) async {
    final reversed = await ref
        .read(loanDetailsApiServiceProvider)
        .waiveOrReducePenalty(penaltyEntryId: penaltyEntryId, waive: waive, reducedAmount: reducedAmount);
    await refresh();
    return reversed;
  }

  // Rethrows for the same reason applyPenalty/waiveOrReducePenalty do: this
  // now hits an RPC that rejects for readable reasons (not the Owner, loan
  // already Closed or Cancelled) and it recognises penalty income. A bare
  // `false` would have let the screen report a close that never happened.
  Future<LoanCloseResult> closeLoan({bool writeOffRemaining = false}) async {
    final result =
        await ref.read(loanDetailsApiServiceProvider).closeLoan(loanId: arg, writeOffRemaining: writeOffRemaining);
    await refresh();
    return result;
  }

  /// Rethrows: a refusal here means the Agent lacks can_grant_grace_period,
  /// and "it didn't work" would leave them retrying a thing they may not do.
  Future<bool> grantGracePeriod({required int days, required String reason}) async {
    await ref.read(loanDetailsApiServiceProvider).grantGracePeriod(
          loanId: arg,
          days: days,
          reason: reason,
        );
    await refresh();
    return true;
  }

  /// Rethrows, same reasoning as editAllowedFields above.
  Future<bool> addRemark(String remark) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      throw StateError(
          'No logged-in person_id available — cannot set entered_by_person_id.');
    }
    await ref.read(loanDetailsApiServiceProvider).addRemark(
          loanId: arg,
          remark: remark,
          enteredByPersonId: int.parse(personId),
        );
    await refresh();
    return true;
  }

  /// The remark log. Kept off the detail fetch on purpose: the log grows and
  /// the detail is read on every screen open.
  Future<List<LoanRemark>> loadRemarks() =>
      ref.read(loanDetailsApiServiceProvider).fetchRemarks(loanId: arg);
}

final loanDetailsProvider = AsyncNotifierProvider.family<LoanDetailsNotifier, LoanDetail, String>(
  LoanDetailsNotifier.new,
);

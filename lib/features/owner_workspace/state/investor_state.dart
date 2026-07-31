import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/text_utils.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// OW-003 Investor Domain — real Supabase wiring over Module 5.
class InvestorApiService {
  final Ref ref;
  InvestorApiService({required this.ref});

  SupabaseClient get _db => Supabase.instance.client;

  Future<List<InvestorSummary>> fetchInvestors({required String businessId, String? status}) async {
    var q = _db
        .from('investors')
        .select('investor_id, membership_id, '
            'business_members!inner(business_id, membership_status), '
            'persons!inner(full_name, mlid, mobile_number), '
            // SCHEMA MISMATCH FIX: `investments` has no `remaining_balance`
            // column (0006_module5_investor_domain.sql) — per that
            // migration's own column comment, `principal_amount` IS the
            // single combined Principal+Interest running balance (Merged
            // Addendum item 2). my_investments_state.dart already used the
            // correct column; this file (and fetchInvestorProfile below)
            // did not, and threw PostgrestException 42703 on every load.
            'investments(investment_id, principal_amount, roi_rate, last_interest_payment_date)')
        .eq('business_members.business_id', businessId);
    final rows = await q;

    final investors = (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) =>
            status == null ||
            (r['business_members'] as Map<String, dynamic>)['membership_status'] == status)
        .toList();

    // Interest Due is live per CALC BR-234, so it needs one snapshot RPC
    // per investment. Every investment across every investor in one
    // Future.wait — a list screen must not fan out into serial round
    // trips, and a PostgrestBuilder is lazy so assign-then-await would do
    // exactly that.
    final ids = <String>[
      for (final r in investors)
        for (final i in ((r['investments'] as List?) ?? const []).cast<Map<String, dynamic>>())
          i['investment_id'] as String,
    ];
    final accruedById = await _accruedFor(ids);

    return investors.map((r) {
      final person = r['persons'] as Map<String, dynamic>;
      final investments = ((r['investments'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final balance =
          investments.fold<double>(0, (sum, i) => sum + ((i['principal_amount'] as num?)?.toDouble() ?? 0));
      final roi = investments.isEmpty ? 0.0 : (investments.first['roi_rate'] as num).toDouble();
      return InvestorSummary(
        investorId: r['investor_id'] as String,
        fullName: titleCaseName(person['full_name'] as String? ?? ''),
        mlid: person['mlid'] as String? ?? '',
        phoneNumber: person['mobile_number'] as String? ?? '',
        investmentBalance: balance,
        roi: roi,
        interestDue: investments.fold<double>(
            0, (sum, i) => sum + (accruedById[i['investment_id'] as String] ?? 0)),
        membershipStatus: (r['business_members'] as Map<String, dynamic>)['membership_status'] as String,
        lastTransaction: null,
      );
    }).toList();
  }

  /// accrued_interest per investment id, via the calculation engine.
  Future<Map<String, double>> _accruedFor(List<String> investmentIds) async {
    if (investmentIds.isEmpty) return {};
    final results = await Future.wait(investmentIds.map((id) async {
      final rows =
          await _db.schema('app').rpc('investment_interest_snapshot', params: {'p_investment_id': id});
      final list = (rows as List?) ?? const [];
      if (list.isEmpty) return MapEntry(id, 0.0);
      return MapEntry(
          id, ((list.first as Map<String, dynamic>)['accrued_interest'] as num?)?.toDouble() ?? 0);
    }));
    return Map.fromEntries(results);
  }

  /// Approve/reject `membership_requests` rows where requested_role='Investor'.
  /// Per OW-003's LOCKED CORRECTION, this is the Owner's ONLY side of
  /// bringing an investor on — the request itself always originates
  /// Investor-side (IW-002).
  Future<void> approveInvestorRequest({required String requestId}) async {
    final personId = ref.read(authFlowProvider).personId;
    final req = await _db.from('membership_requests').select('person_id, business_id').eq('request_id', requestId).single();
    await _db.from('membership_requests').update({
      'status': 'Approved',
      'reviewed_by_person_id': personId != null ? int.parse(personId) : null,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('request_id', requestId);

    final memberRow = await _db
        .from('business_members')
        .insert({
          'person_id': req['person_id'],
          'business_id': req['business_id'],
          'role': 'Investor',
          'membership_status': 'Active',
          'verification_status': 'Not Required', // Investor OTP verification (BR-190/191) happens IW-side before this
          'onboarding_method': 'Direct Registration',
          'joined_at': DateTime.now().toIso8601String(),
        })
        .select('membership_id')
        .single();
    await _db.from('investors').insert({
      'membership_id': memberRow['membership_id'],
      'person_id': req['person_id'],
    });
  }

  Future<void> rejectInvestorRequest({required String requestId}) async {
    final personId = ref.read(authFlowProvider).personId;
    await _db.from('membership_requests').update({
      'status': 'Rejected',
      'reviewed_by_person_id': personId != null ? int.parse(personId) : null,
      'reviewed_at': DateTime.now().toIso8601String(),
      'cooldown_until': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    }).eq('request_id', requestId);
  }

  Future<InvestorSummary?> searchByMlid({required String mlid}) async {
    final rows = await _db.schema('app').rpc('owner_search_person_by_mlid', params: {'p_mlid': mlid});
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final row = list.first;
    return InvestorSummary(
      investorId: '', // not yet a member of this business
      personId: row['person_id']?.toString(),
      fullName: titleCaseName(row['full_name'] as String? ?? ''),
      mlid: row['mlid'] as String? ?? '',
      phoneNumber: row['mobile_number'] as String? ?? '',
      investmentBalance: 0,
      roi: 0,
      interestDue: 0,
      membershipStatus: 'Pending Invitation',
    );
  }

  Future<void> addExistingInvestor({required String businessId, required String personId}) async {
    final memberRow = await _db
        .from('business_members')
        .insert({
          'person_id': int.parse(personId),
          'business_id': businessId,
          'role': 'Investor',
          'membership_status': 'Active',
          'verification_status': 'Not Required',
          'onboarding_method': 'Direct Registration',
          'joined_at': DateTime.now().toIso8601String(),
        })
        .select('membership_id')
        .single();
    await _db.from('investors').insert({
      'membership_id': memberRow['membership_id'],
      'person_id': int.parse(personId),
    });
  }

  Future<void> updateInvestorStatus({required String investorId, required String status}) async {
    final inv = await _db.from('investors').select('membership_id').eq('investor_id', investorId).single();
    await _db.from('business_members').update({'membership_status': status}).eq('membership_id', inv['membership_id']);
  }

  Future<InvestorProfile> fetchInvestorProfile({required String investorId}) async {
    final row = await _db
        .from('investors')
        .select('investor_id, membership_id, '
            'business_members!inner(membership_status), '
            'persons!inner(full_name, mlid, mobile_number), '
            'investments(investment_id, principal_amount, original_principal_amount, roi_rate, '
            'interest_type, effective_date, status, profit_share_percent)')
        .eq('investor_id', investorId)
        .single();

    final person = row['persons'] as Map<String, dynamic>;
    final investments = ((row['investments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final balance = investments.fold<double>(0, (sum, i) => sum + ((i['principal_amount'] as num?)?.toDouble() ?? 0));

    return InvestorProfile(
      summary: InvestorSummary(
        investorId: row['investor_id'] as String,
        fullName: titleCaseName(person['full_name'] as String? ?? ''),
        mlid: person['mlid'] as String? ?? '',
        phoneNumber: person['mobile_number'] as String? ?? '',
        investmentBalance: balance,
        roi: investments.isEmpty ? 0.0 : (investments.first['roi_rate'] as num).toDouble(),
        interestDue: 0, // filled from the per-investment snapshots below
        membershipStatus: (row['business_members'] as Map<String, dynamic>)['membership_status'] as String,
      ),
      investments: await _withInterest(investments),
    );
  }

  /// Fills each investment's live interest figures from the calculation
  /// engine (CALC BR-234) instead of the hardcoded zeros that stood here
  /// since this screen was built.
  ///
  /// One RPC per investment, issued in parallel — `investment_interest_
  /// snapshot` is per-investment by design because the compounding walk is
  /// per-row. Future.wait rather than a loop of awaits: a PostgrestBuilder
  /// is lazy, so awaiting in sequence would be N serial round trips.
  ///
  /// A snapshot failure degrades to zeros rather than taking the whole
  /// profile down — the principal and ROI on screen are still correct and
  /// come from the row itself. This is the one place a swallowed error is
  /// right: interest is derived and re-derivable, not a recorded movement
  /// of money.
  Future<List<InvestmentRecord>> _withInterest(List<Map<String, dynamic>> investments) async {
    // .schema('app') is REQUIRED — these functions live in the `app`
    // schema, and a bare .rpc() targets `public`. Every other app.* call
    // in this codebase does this; these three did not, so they 404'd and
    // the accrued figure silently fell back to zero on screen.
    //
    // Errors are NOT caught here any more either. A swallowed failure is
    // what hid that wiring bug: the screen showed a confident ₹0 for a
    // real accruing investment, which on a money screen is worse than an
    // error. Let it reach NetworkErrorHandler.
    final snapshots = await Future.wait(
      investments.map((i) async {
        final rows = await _db.schema('app').rpc('investment_interest_snapshot',
            params: {'p_investment_id': i['investment_id']});
        final list = (rows as List?) ?? const [];
        return list.isEmpty ? null : list.first as Map<String, dynamic>;
      }),
    );

    return [
      for (final (index, i) in investments.indexed)
        InvestmentRecord(
          investmentId: i['investment_id'] as String,
          // The snapshot's principal is authoritative: it includes any
          // compounding that is due but not yet materialised, which the
          // stored column does not.
          principalAmount: (snapshots[index]?['principal'] as num?)?.toDouble() ??
              (i['principal_amount'] as num).toDouble(),
          roiRate: (i['roi_rate'] as num).toDouble(),
          interestMethod: i['interest_type'] as String,
          effectiveDate: DateTime.parse(i['effective_date'] as String),
          interestAccrued: (snapshots[index]?['accrued_interest'] as num?)?.toDouble() ?? 0,
          interestPaid: (snapshots[index]?['interest_paid_to_date'] as num?)?.toDouble() ?? 0,
          originalPrincipal: (snapshots[index]?['original_principal'] as num?)?.toDouble() ??
              (i['original_principal_amount'] as num?)?.toDouble() ??
              (i['principal_amount'] as num).toDouble(),
          totalInterestEarned:
              (snapshots[index]?['total_interest_earned'] as num?)?.toDouble() ?? 0,
          status: i['status'] as String,
          profitSharePercent: (i['profit_share_percent'] as num?)?.toDouble(),
        ),
    ];
  }

  /// Materialises any due compounding anniversaries (CALC BR-053). Owner
  /// only, server-side. Returns how many events were written.
  Future<int> applyCompounding({required String investmentId}) async {
    final result = await _db.schema('app').rpc('apply_investment_compounding',
        params: {'p_investment_id': investmentId});
    return (result as num?)?.toInt() ?? 0;
  }

  /// Records an Owner-verified interest payout (BR-051/BR-055). Moves
  /// last_interest_payment_date so accrual restarts from the payment date
  /// rather than paying the same interest twice.
  Future<void> recordInterestPayment({
    required String investmentId,
    required double amount,
    String? remarks,
  }) async {
    await _db.schema('app').rpc('record_investment_interest_payment', params: {
      'p_investment_id': investmentId,
      'p_amount': amount,
      'p_business_date': DateTime.now().toIso8601String().split('T').first,
      'p_remarks': remarks,
    });
  }

  /// original_principal_amount is a frozen Agreement Snapshot (BR-034) —
  /// set equal to principal_amount at creation, never touched again by
  /// this method.
  Future<void> recordInvestment({
    required String investorId,
    required double amount,
    required double roiRate,
    required String interestMethod,
    required String effectiveDate,
  }) async {
    // Through app.record_investment, not a bare insert: recording an
    // investment now also credits the business cash pool (BR-022 — the
    // investor's money IS business cash) and refreshes that day's ledger.
    // Those writes must not be able to drift apart, so they live in one
    // server-side transaction rather than three client round trips.
    //
    // roi_rate is rupees per 100 per month, not a percent per year
    // (CALC BR-233).
    await _db.schema('app').rpc('record_investment', params: {
      'p_investor_id': investorId,
      'p_amount': amount,
      'p_roi_rate': roiRate,
      'p_interest_type': interestMethod,
      'p_effective_date': effectiveDate.split('T').first,
    });
  }

  /// Corrects a wrongly-entered investment.
  ///
  /// BR-169's pattern for loans applies here: a saved financial record is
  /// corrected through an edit that preserves the previous values, never a
  /// silent overwrite. The old row is written to audit_log first.
  ///
  /// original_principal_amount moves too, deliberately: it is the frozen
  /// Agreement Snapshot (BR-034), and if the amount was simply typed wrong
  /// then the "original" was wrong as well. This is a correction of a
  /// mistake, not a change of terms.
  Future<void> editInvestment({
    required String investmentId,
    required double amount,
    required double roiRate,
    required String interestMethod,
    required String effectiveDate,
  }) async {
    await _db.schema('app').rpc('edit_investment', params: {
      'p_investment_id': investmentId,
      'p_amount': amount,
      'p_roi_rate': roiRate,
      'p_interest_type': interestMethod,
      'p_effective_date': effectiveDate.split('T').first,
    });
  }

  /// Deletes an investment entered by mistake.
  ///
  /// Refuses once the investment has real history — any interest PAYMENT
  /// or any withdrawal means money has moved, and BR-002 makes those
  /// records permanent. Compounding events are not history in that sense:
  /// they are derived and are recreated by the engine, so they do not
  /// block. Audited before removal either way.
  Future<void> deleteInvestment({required String investmentId}) async {
    // Server-side: the guards (no interest payment, no withdrawal), the
    // audit row, the deletes and the cash-pool debit have to be one
    // transaction. Doing the guards client-side would let a withdrawal
    // land between the check and the delete.
    await _db.schema('app').rpc('delete_investment', params: {
      'p_investment_id': investmentId,
    });
  }

  Future<void> requestWithdrawal({
    required String investmentId,
    required double amount,
    required String withdrawalType,
  }) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    await _db.from('investment_withdrawal_requests').insert({
      'investment_id': investmentId,
      'requested_by_person_id': int.parse(personId),
      'withdrawal_type': withdrawalType,
      'requested_amount': amount,
      'status': 'Pending',
    });
  }

  // BUG FIXED this pass: declareProfitShare/payProfitShare below were
  // both fully implemented but never surfaced anywhere in OW-003 — this
  // lets the UI actually list what's already been declared for an
  // investment (to show a "pay" action once, not offer to declare the
  // same profit twice).
  Future<List<ProfitShareDeclaration>> fetchProfitShareDeclarations({required String investmentId}) async {
    final rows = await _db
        .from('distribution_declarations')
        .select('declaration_id, total_profit_amount, declared_amount, business_date, status, remarks')
        .eq('investment_id', investmentId)
        .order('business_date', ascending: false);
    return (rows as List)
        .map((r) => ProfitShareDeclaration(
              declarationId: r['declaration_id'] as String,
              totalProfitAmount: (r['total_profit_amount'] as num).toDouble(),
              declaredAmount: (r['declared_amount'] as num).toDouble(),
              businessDate: DateTime.parse(r['business_date'] as String),
              status: r['status'] as String,
              remarks: r['remarks'] as String?,
            ))
        .toList();
  }

  Future<void> declareProfitShare({
    required String investmentId,
    required double totalProfitAmount,
    String? remarks,
  }) async {
    final investment = await _db.from('investments').select('business_id, profit_share_percent').eq('investment_id', investmentId).single();
    final pct = (investment['profit_share_percent'] as num?)?.toDouble() ?? 0;
    await _db.from('distribution_declarations').insert({
      'business_id': investment['business_id'],
      'recipient_type': 'Investor',
      'investment_id': investmentId,
      'profit_share_percent': pct,
      'total_profit_amount': totalProfitAmount,
      'declared_amount': totalProfitAmount * pct / 100,
      'business_date': DateTime.now().toIso8601String().split('T').first,
      'status': 'Declared',
      'remarks': remarks,
    });
  }

  /// interest_amount is manually entered by Owner, never system-computed
  /// (Rule #059, per the schema's own column comment) — payProfitShare's
  /// stub signature takes no interest figure, so this inserts 0 and relies
  /// on the schema's own DEFAULT 0; a future UI pass that actually
  /// collects that figure should pass it through here rather than this
  /// method silently computing one.
  Future<void> payProfitShare({required String declarationId}) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    final decl = await _db.from('distribution_declarations').select('declared_amount').eq('declaration_id', declarationId).single();
    await _db.from('distribution_payments').insert({
      'declaration_id': declarationId,
      'paid_amount': decl['declared_amount'],
      'business_date': DateTime.now().toIso8601String().split('T').first,
      'approved_by_person_id': int.parse(personId),
    });
    await _db.from('distribution_declarations').update({'status': 'Paid'}).eq('declaration_id', declarationId);
  }

  // BUG FIXED this pass: IW-004's "Request Withdrawal" does a real
  // INSERT into investment_withdrawal_requests, and even the Owner's own
  // "request withdrawal" dialog here only ever inserted another Pending
  // row — nothing anywhere ever transitioned one out of Pending. Closes
  // that with a real Owner-side review queue (investment_withdrawal_
  // requests_owner_all RLS, 0014, already grants full access).
  Future<List<WithdrawalRequestSummary>> fetchWithdrawalRequests({required String businessId}) async {
    final rows = await _db
        .from('investment_withdrawal_requests')
        .select('request_id, investment_id, withdrawal_type, requested_amount, remarks, created_at, '
            'investments!inner(business_id, investors!inner(persons!inner(full_name, mlid)))')
        .eq('investments.business_id', businessId)
        .eq('status', 'Pending')
        .order('created_at', ascending: false);
    return (rows as List).map((r) {
      final investment = r['investments'] as Map<String, dynamic>;
      final investor = investment['investors'] as Map<String, dynamic>;
      final person = investor['persons'] as Map<String, dynamic>;
      return WithdrawalRequestSummary(
        requestId: r['request_id'] as String,
        investmentId: r['investment_id'] as String,
        investorName: titleCaseName(person['full_name'] as String? ?? ''),
        investorMlid: person['mlid'] as String? ?? '',
        withdrawalType: r['withdrawal_type'] as String,
        requestedAmount: (r['requested_amount'] as num).toDouble(),
        remarks: r['remarks'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  Future<void> rejectWithdrawalRequest({required String requestId, required String reason}) async {
    await _db.from('investment_withdrawal_requests').update({
      'status': 'Rejected',
      'rejection_reason': reason,
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('request_id', requestId);
  }

  /// Pays out a withdrawal request — Owner enters the principal/interest
  /// split manually (schema's own column comment: "Owner-entered at
  /// approval time", not system-computed). Reduces investments.
  /// principal_amount by the paid amount (that column is documented as
  /// the single combined running balance, per 0006's own comment) and
  /// auto-closes the investment if it reaches 0 (app-layer, same as that
  /// comment specifies — no DB trigger does this).
  Future<void> approveWithdrawalRequest({
    required String requestId,
    required String investmentId,
    required String withdrawalType,
    required double amount,
    required double principalPortion,
    required double interestPortion,
  }) async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) throw StateError('No logged-in person_id available.');
    final today = DateTime.now().toIso8601String().split('T').first;

    final withdrawal = await _db
        .from('investment_withdrawals')
        .insert({
          'investment_id': investmentId,
          'withdrawal_type': withdrawalType,
          'amount': amount,
          'principal_portion': principalPortion,
          'interest_portion': interestPortion,
          'business_date': today,
          'approved_by_person_id': int.parse(personId),
        })
        .select('withdrawal_id')
        .single();

    final investment = await _db.from('investments').select('principal_amount').eq('investment_id', investmentId).single();
    final remaining = (investment['principal_amount'] as num).toDouble() - principalPortion;
    await _db.from('investments').update({
      'principal_amount': remaining < 0 ? 0 : remaining,
      if (remaining <= 0) 'status': 'Closed',
    }).eq('investment_id', investmentId);

    await _db.from('investment_withdrawal_requests').update({
      'status': 'Approved-Paid',
      'resulting_withdrawal_id': withdrawal['withdrawal_id'],
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('request_id', requestId);
  }
}

class ProfitShareDeclaration {
  final String declarationId;
  final double totalProfitAmount;
  final double declaredAmount;
  final DateTime businessDate;
  final String status; // Declared | Paid
  final String? remarks;
  ProfitShareDeclaration({
    required this.declarationId,
    required this.totalProfitAmount,
    required this.declaredAmount,
    required this.businessDate,
    required this.status,
    this.remarks,
  });
}

class WithdrawalRequestSummary {
  final String requestId;
  final String investmentId;
  final String investorName;
  final String investorMlid;
  final String withdrawalType;
  final double requestedAmount;
  final String? remarks;
  final DateTime createdAt;
  WithdrawalRequestSummary({
    required this.requestId,
    required this.investmentId,
    required this.investorName,
    required this.investorMlid,
    required this.withdrawalType,
    required this.requestedAmount,
    this.remarks,
    required this.createdAt,
  });
}

class InvestorSummary {
  final String investorId;
  final String? personId; // populated for pre-membership search results; investorId is empty in that case
  final String fullName;
  final String mlid;
  final String phoneNumber;
  final double investmentBalance;
  final double roi;
  final double interestDue;
  final String membershipStatus; // Pending Invitation | Pending Acceptance | Active | Temporarily Disabled | Suspended | Removed
  final DateTime? lastTransaction;

  InvestorSummary({
    required this.investorId,
    this.personId,
    required this.fullName,
    required this.mlid,
    required this.phoneNumber,
    required this.investmentBalance,
    required this.roi,
    required this.interestDue,
    required this.membershipStatus,
    this.lastTransaction,
  });
}

class InvestmentRecord {
  final String investmentId;
  final double principalAmount;
  final double roiRate;
  final String interestMethod;
  final DateTime effectiveDate;
  /// CURRENT PERIOD only for Yearly Compound — it resets at each
  /// anniversary because prior years' interest has already become
  /// principal (Appendix A Case B / BR-052). For Simple it is cumulative
  /// since the last payment. This is the figure an "Interest Only"
  /// withdrawal is capped at.
  final double interestAccrued;
  final double interestPaid;
  /// The Agreement Snapshot amount (BR-034) — what was originally put in,
  /// before any compounding grew `principalAmount`.
  final double originalPrincipal;
  /// Everything this investment has earned since inception: compounded
  /// into principal, plus accrued now, plus already paid out. REPORTING
  /// ONLY — never a withdrawal cap, since the compounded part is
  /// withdrawable as principal rather than as interest.
  final double totalInterestEarned;
  final String status; // Active | Closed
  final double? profitSharePercent;

  InvestmentRecord({
    required this.investmentId,
    required this.principalAmount,
    required this.roiRate,
    required this.interestMethod,
    required this.effectiveDate,
    required this.interestAccrued,
    required this.interestPaid,
    required this.originalPrincipal,
    required this.totalInterestEarned,
    required this.status,
    this.profitSharePercent,
  });

  bool get isCompound => interestMethod == 'Yearly Compound';

  /// Compounding has moved money into capital, so the split is worth
  /// showing. False for Simple, and for a compound investment that has
  /// not reached its first anniversary yet.
  bool get hasCompounded => principalAmount > originalPrincipal;
}

class InvestorProfile {
  final InvestorSummary summary;
  final List<InvestmentRecord> investments;

  InvestorProfile({required this.summary, this.investments = const []});
}

// --- Riverpod state ----------------------------------------------------

final investorApiServiceProvider = Provider<InvestorApiService>((ref) {
  return InvestorApiService(ref: ref);
});

class InvestorWorkforceState {
  final List<InvestorSummary> investors;
  final bool loading;
  final String? statusFilter;
  final String searchQuery;
  final String? error;

  const InvestorWorkforceState({
    this.investors = const [],
    this.loading = false,
    this.statusFilter,
    this.searchQuery = '',
    this.error,
  });

  List<InvestorSummary> get filtered {
    var list = investors;
    if (statusFilter != null) list = list.where((i) => i.membershipStatus == statusFilter).toList();
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((i) => i.fullName.toLowerCase().contains(q) || i.mlid.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  int get total => investors.length;
  int get active => investors.where((i) => i.membershipStatus == 'Active').length;
  int get pendingInvitations => investors.where((i) => i.membershipStatus == 'Pending Invitation').length;
  int get pendingAcceptance => investors.where((i) => i.membershipStatus == 'Pending Acceptance').length;
  int get suspended => investors.where((i) => i.membershipStatus == 'Suspended').length;
  int get removed => investors.where((i) => i.membershipStatus == 'Removed').length;
  double get totalInvestment => investors.fold(0.0, (sum, i) => sum + i.investmentBalance);
  double get interestPayable => investors.fold(0.0, (sum, i) => sum + i.interestDue);

  InvestorWorkforceState copyWith({
    List<InvestorSummary>? investors,
    bool? loading,
    String? statusFilter,
    bool clearStatusFilter = false,
    String? searchQuery,
    String? error,
    bool clearError = false,
  }) {
    return InvestorWorkforceState(
      investors: investors ?? this.investors,
      loading: loading ?? this.loading,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InvestorWorkforceNotifier extends Notifier<InvestorWorkforceState> {
  @override
  InvestorWorkforceState build() => const InvestorWorkforceState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(investorApiServiceProvider);
      final investors = await api.fetchInvestors(businessId: businessId);
      state = state.copyWith(investors: investors, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setStatusFilter(String? status) =>
      state = status == null ? state.copyWith(clearStatusFilter: true) : state.copyWith(statusFilter: status);

  void setSearchQuery(String q) => state = state.copyWith(searchQuery: q);

  Future<bool> approveRequest(String businessId, String requestId) async {
    try {
      await ref.read(investorApiServiceProvider).approveInvestorRequest(requestId: requestId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> rejectRequest(String businessId, String requestId) async {
    try {
      await ref.read(investorApiServiceProvider).rejectInvestorRequest(requestId: requestId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<InvestorSummary?> searchByMlid(String mlid) async {
    try {
      return await ref.read(investorApiServiceProvider).searchByMlid(mlid: mlid);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> addExisting(String businessId, String personId) async {
    try {
      await ref.read(investorApiServiceProvider).addExistingInvestor(businessId: businessId, personId: personId);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateStatus(String businessId, String investorId, String status) async {
    try {
      await ref.read(investorApiServiceProvider).updateInvestorStatus(investorId: investorId, status: status);
      await load(businessId);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final investorWorkforceProvider = NotifierProvider<InvestorWorkforceNotifier, InvestorWorkforceState>(
  InvestorWorkforceNotifier.new,
);

class InvestorProfileNotifier extends FamilyAsyncNotifier<InvestorProfile, String> {
  @override
  Future<InvestorProfile> build(String investorId) async {
    return ref.read(investorApiServiceProvider).fetchInvestorProfile(investorId: investorId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(investorApiServiceProvider).fetchInvestorProfile(investorId: arg));
  }

  Future<bool> editInvestment({
    required String investmentId,
    required double amount,
    required double roiRate,
    required String interestMethod,
    required String effectiveDate,
  }) async {
    await ref.read(investorApiServiceProvider).editInvestment(
          investmentId: investmentId,
          amount: amount,
          roiRate: roiRate,
          interestMethod: interestMethod,
          effectiveDate: effectiveDate,
        );
    await refresh();
    return true;
  }

  Future<bool> deleteInvestment({required String investmentId}) async {
    await ref.read(investorApiServiceProvider).deleteInvestment(investmentId: investmentId);
    await refresh();
    return true;
  }

  Future<bool> recordInvestment({
    required double amount,
    required double roiRate,
    required String interestMethod,
    required String effectiveDate,
  }) async {
    try {
      await ref.read(investorApiServiceProvider).recordInvestment(
            investorId: arg,
            amount: amount,
            roiRate: roiRate,
            interestMethod: interestMethod,
            effectiveDate: effectiveDate,
          );
      await refresh();
      return true;
    } catch (e) {
      // Deliberately RETHROWN, not swallowed into `false`. This method
      // records money. Returning false hid a hard PGRST204 schema error
      // behind a silent no-op for as long as this screen has existed —
      // the Owner pressed Save, the dialog closed, and nothing was
      // written. NetworkErrorHandler shows the real Postgres message.
      rethrow;
    }
  }

  Future<bool> requestWithdrawal({
    required String investmentId,
    required double amount,
    required String withdrawalType,
  }) async {
    try {
      await ref.read(investorApiServiceProvider).requestWithdrawal(
            investmentId: investmentId,
            amount: amount,
            withdrawalType: withdrawalType,
          );
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final investorProfileProvider =
    AsyncNotifierProvider.family<InvestorProfileNotifier, InvestorProfile, String>(
  InvestorProfileNotifier.new,
);

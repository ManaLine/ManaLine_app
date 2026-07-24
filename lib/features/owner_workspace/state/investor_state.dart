import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
            'investments(remaining_balance, roi_rate, last_interest_payment_date)')
        .eq('business_members.business_id', businessId);
    final rows = await q;

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) {
          final person = r['persons'] as Map<String, dynamic>;
          final investments = ((r['investments'] as List?) ?? const []).cast<Map<String, dynamic>>();
          final balance = investments.fold<double>(0, (sum, i) => sum + ((i['remaining_balance'] as num?)?.toDouble() ?? 0));
          final roi = investments.isEmpty ? 0.0 : (investments.first['roi_rate'] as num).toDouble();
          return InvestorSummary(
            investorId: r['investor_id'] as String,
            fullName: person['full_name'] as String? ?? '',
            mlid: person['mlid'] as String? ?? '',
            phoneNumber: person['mobile_number'] as String? ?? '',
            investmentBalance: balance,
            roi: roi,
            interestDue: 0, // requires investment_interest_ledger aggregation — see KNOWN SIMPLIFICATION pattern established elsewhere this session
            membershipStatus: (r['business_members'] as Map<String, dynamic>)['membership_status'] as String,
            lastTransaction: null,
          );
        })
        .where((i) => status == null || i.membershipStatus == status)
        .toList();
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
    final row = await _db.from('persons').select('person_id, full_name, mlid, mobile_number').eq('mlid', mlid).maybeSingle();
    if (row == null) return null;
    return InvestorSummary(
      investorId: '', // not yet a member of this business
      fullName: row['full_name'] as String? ?? '',
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
            'investments(investment_id, principal_amount, roi_rate, interest_type, effective_date, '
            'remaining_balance, status, profit_share_percent)')
        .eq('investor_id', investorId)
        .single();

    final person = row['persons'] as Map<String, dynamic>;
    final investments = ((row['investments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final balance = investments.fold<double>(0, (sum, i) => sum + ((i['remaining_balance'] as num?)?.toDouble() ?? 0));

    return InvestorProfile(
      summary: InvestorSummary(
        investorId: row['investor_id'] as String,
        fullName: person['full_name'] as String? ?? '',
        mlid: person['mlid'] as String? ?? '',
        phoneNumber: person['mobile_number'] as String? ?? '',
        investmentBalance: balance,
        roi: investments.isEmpty ? 0.0 : (investments.first['roi_rate'] as num).toDouble(),
        interestDue: 0,
        membershipStatus: (row['business_members'] as Map<String, dynamic>)['membership_status'] as String,
      ),
      investments: investments
          .map((i) => InvestmentRecord(
                investmentId: i['investment_id'] as String,
                principalAmount: (i['principal_amount'] as num).toDouble(),
                roiRate: (i['roi_rate'] as num).toDouble(),
                interestMethod: i['interest_type'] as String,
                effectiveDate: DateTime.parse(i['effective_date'] as String),
                interestAccrued: 0, // requires investment_interest_ledger aggregation
                interestPaid: 0,
                status: i['status'] as String,
                profitSharePercent: (i['profit_share_percent'] as num?)?.toDouble(),
              ))
          .toList(),
    );
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
    final investor = await _db.from('investors').select('business_members!inner(business_id)').eq('investor_id', investorId).single();
    final businessId = (investor['business_members'] as Map<String, dynamic>)['business_id'];
    await _db.from('investments').insert({
      'investor_id': investorId,
      'business_id': businessId,
      'principal_amount': amount,
      'original_principal_amount': amount,
      'roi_rate': roiRate,
      'interest_type': interestMethod,
      'effective_date': effectiveDate,
      'status': 'Active',
      'remaining_balance': amount,
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
}

class InvestorSummary {
  final String investorId;
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
  final double interestAccrued;
  final double interestPaid;
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
    required this.status,
    this.profitSharePercent,
  });
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
    } catch (_) {
      return false;
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

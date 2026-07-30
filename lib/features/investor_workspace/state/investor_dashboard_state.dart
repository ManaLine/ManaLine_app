import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// IW-001 Investor Home Dashboard.
/// RESOLVED: was a genuine stub (`throw UnimplementedError` on every
/// call) — the actual cause of "Could Not Load Dashboard." Real queries
/// against investors/investments/investment_interest_ledger/
/// investment_withdrawal_requests, verified directly against the live
/// schema before writing this.
///
/// FIXED (this batch): the `persons` embed off `business_members` was
/// ambiguous — two FKs exist (business_members_person_id_fkey and
/// business_members_invited_by_person_id_fkey), and PostgREST refused to
/// guess which one, throwing PGRST201 ("Could not embed because more
/// than one relationship was found"). Disambiguated to the person_id FK
/// explicitly — the dashboard wants the member's own person record, not
/// who invited them.
class InvestorDashboardApiService {
  final SupabaseClient _db;
  InvestorDashboardApiService(this._db);

  Future<InvestorDashboardData> fetchDashboard({required String businessId, required String personId}) async {
    final membershipRows = await _db
        .from('business_members')
        .select('membership_id, membership_status, verification_status, businesses(business_name), persons!business_members_person_id_fkey(full_name)')
        .eq('person_id', personId)
        .eq('business_id', businessId)
        .eq('role', 'Investor')
        .limit(1);
    final memberships = (membershipRows as List).cast<Map<String, dynamic>>();
    if (memberships.isEmpty || memberships.first['membership_status'] != 'Active') {
      return InvestorDashboardData.noMemberships();
    }
    final membership = memberships.first;
    final business = membership['businesses'] as Map<String, dynamic>?;
    final person = membership['persons'] as Map<String, dynamic>?;

    final investorRow = await _db
        .from('investors')
        .select('investor_id')
        .eq('membership_id', membership['membership_id'])
        .maybeSingle();
    if (investorRow == null) return InvestorDashboardData.noMemberships();
    final investorId = investorRow['investor_id'] as String;

    final investmentRows = await _db
        .from('investments')
        .select('investment_id, principal_amount, status')
        .eq('investor_id', investorId)
        .eq('business_id', businessId);
    final investments = (investmentRows as List).cast<Map<String, dynamic>>();
    final activeInvestments = investments.where((i) => i['status'] == 'Active').toList();
    final totalBalance = activeInvestments.fold<double>(0, (sum, i) => sum + ((i['principal_amount'] as num?)?.toDouble() ?? 0));
    final investmentIds = investments.map((i) => i['investment_id']).toList();

    double totalAccrued = 0;
    double totalPaid = 0;
    if (investmentIds.isNotEmpty) {
      final ledgerRows = await _db
          .from('investment_interest_ledger')
          .select('amount, entry_type')
          .inFilter('investment_id', investmentIds);
      for (final row in (ledgerRows as List).cast<Map<String, dynamic>>()) {
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (row['entry_type'] == 'Payment') {
          totalPaid += amount;
        } else {
          totalAccrued += amount;
        }
      }
    }

    int pendingWithdrawals = 0;
    int pendingInterestPayments = 0;
    if (investmentIds.isNotEmpty) {
      final withdrawalRows = await _db
          .from('investment_withdrawal_requests')
          .select('withdrawal_type, status')
          .inFilter('investment_id', investmentIds)
          .eq('status', 'Pending');
      final withdrawals = (withdrawalRows as List).cast<Map<String, dynamic>>();
      pendingWithdrawals = withdrawals.length;
      pendingInterestPayments = withdrawals.where((w) => w['withdrawal_type'] == 'Interest Only').length;
    }

    // notifications_self_select (0018 RLS) scopes this to the caller's
    // own recipient_person_id — safe for any logged-in role, not just
    // Owner (whose OW-001 dashboard reads the same table business_id-
    // scoped instead, since an Owner has one identity per business).
    final notificationRows = await _db
        .from('notifications')
        .select('notification_type, message, created_at, is_read')
        .eq('recipient_person_id', personId)
        .order('created_at', ascending: false)
        .limit(20);

    return InvestorDashboardData(
      hasActiveMembership: true,
      businessName: business?['business_name'] as String? ?? '',
      investorName: person?['full_name'] as String? ?? '',
      investorVerified: membership['verification_status'] == 'Verified',
      totalInvestmentBalance: totalBalance,
      activeInvestmentCount: activeInvestments.length,
      totalInterestAccrued: totalAccrued,
      interestPaidToDate: totalPaid,
      pendingWithdrawalRequests: pendingWithdrawals,
      pendingInterestPaymentRequests: pendingInterestPayments,
      notifications: (notificationRows as List)
          .map((n) => InvestorNotification(
                type: n['notification_type'] as String,
                message: n['message'] as String,
                timestamp: DateTime.parse(n['created_at'] as String),
                read: n['is_read'] as bool? ?? false,
              ))
          .toList(),
    );
  }
}

class InvestorNotification {
  final String type;
  final String message;
  final DateTime timestamp;
  final bool read;
  InvestorNotification({required this.type, required this.message, required this.timestamp, this.read = false});
}

final investorDashboardApiServiceProvider = Provider<InvestorDashboardApiService>((ref) {
  return InvestorDashboardApiService(Supabase.instance.client);
});

class InvestorDashboardData {
  final bool hasActiveMembership; // S3 No Memberships gate
  final String businessName;
  final String investorName;
  final bool investorVerified;
  final double totalInvestmentBalance;
  final int activeInvestmentCount;
  final double totalInterestAccrued;
  final double interestPaidToDate;
  final int pendingWithdrawalRequests;
  final int pendingInterestPaymentRequests;
  final List<InvestorNotification> notifications;

  InvestorDashboardData({
    required this.hasActiveMembership,
    this.businessName = '',
    this.investorName = '',
    this.investorVerified = false,
    this.totalInvestmentBalance = 0,
    this.activeInvestmentCount = 0,
    this.totalInterestAccrued = 0,
    this.interestPaidToDate = 0,
    this.pendingWithdrawalRequests = 0,
    this.pendingInterestPaymentRequests = 0,
    this.notifications = const [],
  });

  factory InvestorDashboardData.noMemberships() => InvestorDashboardData(hasActiveMembership: false);
}

class InvestorDashboardNotifier extends AsyncNotifier<InvestorDashboardData> {
  @override
  Future<InvestorDashboardData> build() async {
    // Real screen passes businessId in via load(); build() stays
    // side-effect-free per Riverpod convention (same pattern as OW-001's
    // OwnerDashboardNotifier).
    return InvestorDashboardData.noMemberships();
  }

  Future<void> load(String businessId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final api = ref.read(investorDashboardApiServiceProvider);
      final personId = ref.read(authFlowProvider).personId;
      if (personId == null) return Future.value(InvestorDashboardData.noMemberships());
      return api.fetchDashboard(businessId: businessId, personId: personId);
    });
  }
}

final investorDashboardProvider = AsyncNotifierProvider<InvestorDashboardNotifier, InvestorDashboardData>(
  InvestorDashboardNotifier.new,
);

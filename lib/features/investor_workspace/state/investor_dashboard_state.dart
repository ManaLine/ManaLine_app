import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/text_utils.dart';
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
    // PERF: this method is a genuine dependency chain — membership ->
    // investor -> investments -> {ledger, withdrawals} — so there is less to
    // parallelise here than on the other dashboards. Two wins are available
    // and taken: notifications only need personId, so they ride along with
    // the membership lookup instead of waiting for the whole chain; and the
    // ledger and withdrawal reads both depend only on investmentIds, so they
    // go out together at the end. 6 sequential trips become 4 waves.
    //
    // A deeper win exists — embedding investors(investor_id) and investments
    // into the membership select would collapse three trips into one — but
    // nested-embed filters are where this codebase has hit PGRST201
    // ambiguity bugs before, so it is deliberately not attempted right
    // before live testing.
    final wave1 = await Future.wait<dynamic>([
      _db
          .from('business_members')
          .select('membership_id, membership_status, verification_status, businesses(business_name), persons!business_members_person_id_fkey(full_name)')
          .eq('person_id', personId)
          .eq('business_id', businessId)
          .eq('role', 'Investor')
          .limit(1),
      _db
          .from('notifications')
          .select('notification_type, message, created_at, is_read')
          .eq('recipient_person_id', personId)
          .order('created_at', ascending: false)
          .limit(20),
    ]);
    final membershipRows = wave1[0] as List;
    final notificationRows = wave1[1] as List;
    final memberships = membershipRows.cast<Map<String, dynamic>>();
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
    final totalBalance = activeInvestments.fold<int>(0, (sum, i) => sum + ((i['principal_amount'] as num?)?.toInt() ?? 0));
    final investmentIds = investments.map((i) => i['investment_id']).toList();

    // Both of these depend only on investmentIds, so they go out together
    // rather than one after the other. Skipped entirely when the investor has
    // no investments, instead of spending two trips on empty filters.
    //
    // Notifications were fetched back in wave 1 (notifications_self_select,
    // 0018 RLS, scopes them to the caller's own recipient_person_id — safe
    // for any logged-in role, unlike OW-001 which reads the same table
    // business_id-scoped since an Owner has one identity per business).
    int totalAccrued = 0;
    int totalPaid = 0;
    int pendingWithdrawals = 0;
    int pendingInterestPayments = 0;

    if (investmentIds.isNotEmpty) {
      final wave4 = await Future.wait<dynamic>([
        _db.from('investment_interest_ledger').select('amount, entry_type').inFilter('investment_id', investmentIds),
        _db
            .from('investment_withdrawal_requests')
            .select('withdrawal_type, status')
            .inFilter('investment_id', investmentIds)
            .eq('status', 'Pending'),
      ]);

      for (final row in (wave4[0] as List).cast<Map<String, dynamic>>()) {
        final amount = (row['amount'] as num?)?.toInt() ?? 0;
        if (row['entry_type'] == 'Payment') {
          totalPaid += amount;
        } else {
          totalAccrued += amount;
        }
      }

      final withdrawals = (wave4[1] as List).cast<Map<String, dynamic>>();
      pendingWithdrawals = withdrawals.length;
      pendingInterestPayments = withdrawals.where((w) => w['withdrawal_type'] == 'Interest Only').length;
    }

    return InvestorDashboardData(
      hasActiveMembership: true,
      businessName: titleCaseName(business?['business_name'] as String? ?? ''),
      investorName: person?['full_name'] as String? ?? '',
      investorVerified: membership['verification_status'] == 'Verified',
      totalInvestmentBalance: totalBalance,
      activeInvestmentCount: activeInvestments.length,
      totalInterestAccrued: totalAccrued,
      interestPaidToDate: totalPaid,
      pendingWithdrawalRequests: pendingWithdrawals,
      pendingInterestPaymentRequests: pendingInterestPayments,
      notifications: notificationRows
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
  final int totalInvestmentBalance;
  final int activeInvestmentCount;
  final int totalInterestAccrued;
  final int interestPaidToDate;
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

  /// Which business the currently-held value belongs to — see [load].
  String? _loadedForBusinessId;

  Future<void> load(String businessId) async {
    // Keep the existing value visible while revalidating, so a revisit doesn't
    // flash a spinner over already-loaded figures. Except on a Business
    // Switch, where holding the previous business's investment balances would
    // show the investor another business's money.
    final sameBusiness = _loadedForBusinessId == businessId;
    if (!state.hasValue || !sameBusiness) state = const AsyncLoading();

    final next = await AsyncValue.guard(() {
      final api = ref.read(investorDashboardApiServiceProvider);
      final personId = ref.read(authFlowProvider).personId;
      if (personId == null) return Future.value(InvestorDashboardData.noMemberships());
      return api.fetchDashboard(businessId: businessId, personId: personId);
    });
    _loadedForBusinessId = next.hasValue ? businessId : null;
    state = next;
  }
}

final investorDashboardProvider = AsyncNotifierProvider<InvestorDashboardNotifier, InvestorDashboardData>(
  InvestorDashboardNotifier.new,
);

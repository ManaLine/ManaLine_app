import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CW-001 Customer Home Dashboard — real Supabase wiring over Module 3
/// (customers/loan_requests via customer_id) + Module 6
/// (loans/loan_schedule) + Module 7 (customer_online_payments) +
/// businesses (Module 1).
///
/// RLS: `customers_self_select` / `loans_customer_select_own` /
/// `loan_schedule_customer_select_own` / `loan_requests_customer_select_own`
/// / `customer_online_payments_customer_select_own`
/// (0014/0015/0016_rls_*.sql) already scope every query below to the
/// logged-in person's own rows — no explicit person_id filter added
/// client-side, matching agent_notifications_state.dart's header-comment
/// reasoning.
class CustomerDashboardApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<CustomerDashboardData> fetchDashboard({required String businessId}) async {
    final businessRow = await _db
        .from('businesses')
        .select('business_name, logo_url')
        .eq('business_id', businessId)
        .maybeSingle();

    final customerRow = await _db
        .from('customers')
        .select('''
          customer_id,
          business_members!inner(business_id, membership_status),
          persons!inner(full_name, profile_photo_url),
          loans(loan_id, loan_status, remaining_balance)
        ''')
        .eq('business_members.business_id', businessId)
        .maybeSingle();

    if (customerRow == null) {
      return CustomerDashboardData.noMemberships();
    }

    final bm = customerRow['business_members'] as Map<String, dynamic>;
    if (bm['membership_status'] != 'Active') {
      return CustomerDashboardData.noMemberships();
    }

    final person = customerRow['persons'] as Map<String, dynamic>;
    final customerId = customerRow['customer_id'] as String;
    final loans = ((customerRow['loans'] as List?) ?? const []).cast<Map<String, dynamic>>();
    // Same "active loan" bucket used throughout this session
    // (customer_state.dart / agent_customer_state.dart):
    // Active + Grace Period + Penalty.
    final activeLoans = loans.where((l) => ['Active', 'Grace Period', 'Penalty'].contains(l['loan_status'])).toList();
    final totalOutstanding =
        activeLoans.fold<double>(0, (sum, l) => sum + (l['remaining_balance'] as num).toDouble());
    final activeLoanIds = activeLoans.map((l) => l['loan_id'] as String).toList();

    // Next payment due: earliest still-Pending loan_schedule row across
    // this customer's active loans. loan_schedule_customer_select_own
    // (0015) scopes this to the caller's own loans.
    DateTime? nextDueDate;
    double? nextDueAmount;
    if (activeLoanIds.isNotEmpty) {
      final scheduleRows = await _db
          .from('loan_schedule')
          .select('due_date, installment_amount, loan_id')
          .inFilter('loan_id', activeLoanIds)
          .eq('status', 'Pending')
          .order('due_date', ascending: true)
          .limit(1);
      final rows = (scheduleRows as List).cast<Map<String, dynamic>>();
      if (rows.isNotEmpty) {
        nextDueDate = DateTime.parse(rows.first['due_date'] as String);
        nextDueAmount = (rows.first['installment_amount'] as num).toDouble();
      }
    }

    // Pending loan requests. SCHEMA FLAG: the original stub's comment
    // said "status in (Submitted, Approved, Rejected) per spec's own
    // parenthetical", but loan_request_status_enum
    // (0007_module6_loan_domain.sql) only has ('Pending', 'Approved',
    // 'Rejected') — there is no 'Submitted' value anywhere in the
    // schema. Using 'Pending' here as the actual not-yet-resolved state;
    // flagged for confirmation against the real CW-003 screen spec if
    // "pending" there was meant to include something broader than the
    // enum's own Pending value.
    final pendingLoanRequestsRows = await _db
        .from('loan_requests')
        .select('request_id')
        .eq('customer_id', customerId)
        .eq('status', 'Pending');
    final pendingLoanRequestsCount = (pendingLoanRequestsRows as List).length;

    // Pending online payments awaiting Owner/Agent confirmation.
    final pendingOnlinePaymentsRows = await _db
        .from('customer_online_payments')
        .select('online_payment_id')
        .eq('customer_id', customerId)
        .eq('status', 'Submitted');
    final pendingOnlinePaymentsCount = (pendingOnlinePaymentsRows as List).length;

    return CustomerDashboardData(
      hasActiveMembership: true,
      businessName: businessRow?['business_name'] as String? ?? '',
      businessLogoUrl: businessRow?['logo_url'] as String?,
      customerName: person['full_name'] as String? ?? '',
      profilePhotoUrl: person['profile_photo_url'] as String?,
      // BR-189: Customer role verification_status is always 'Not
      // Required' — no Pending/Red state can occur for this role
      // (unlike Agent/Investor, BR-188/190/191). Hardcoded true per the
      // original stub's own field comment, rather than querying a
      // column that can only ever read one way for this role.
      verified: true,
      activeLoansCount: activeLoans.length,
      totalOutstanding: totalOutstanding,
      nextPaymentDueDate: nextDueDate,
      nextPaymentDueAmount: nextDueAmount,
      pendingLoanRequestsCount: pendingLoanRequestsCount,
      pendingOnlinePaymentsCount: pendingOnlinePaymentsCount,
    );
  }
}

final customerDashboardApiServiceProvider = Provider<CustomerDashboardApiService>((ref) {
  return CustomerDashboardApiService();
});

// ============================================================================
// Models
// ============================================================================

class CustomerDashboardData {
  final bool hasActiveMembership; // S3 No Memberships gate

  // HEADER
  final String businessName;
  final String? businessLogoUrl;
  final String customerName;
  final String? profilePhotoUrl;
  // customers→business_members.verification_status is always 'Not
  // Required' for the Customer role (BR-189) — there is no Pending/Red
  // state that can occur here, unlike Agent/Investor (BR-188/190/191).
  // Modeled as a bool for ManaVerificationRing's own isVerified param;
  // always true given BR-189, kept as a field (not hardcoded in the
  // widget) in case that rule is ever revisited.
  final bool verified;

  // MY SUMMARY
  final int activeLoansCount;
  final double totalOutstanding;
  final DateTime? nextPaymentDueDate;
  final double? nextPaymentDueAmount;
  final int pendingLoanRequestsCount; // loan_requests, status in (Submitted, Approved, Rejected) per spec's own parenthetical
  final int pendingOnlinePaymentsCount; // customer_online_payments awaiting Owner/Agent confirmation

  CustomerDashboardData({
    required this.hasActiveMembership,
    this.businessName = '',
    this.businessLogoUrl,
    this.customerName = '',
    this.profilePhotoUrl,
    this.verified = true,
    this.activeLoansCount = 0,
    this.totalOutstanding = 0,
    this.nextPaymentDueDate,
    this.nextPaymentDueAmount,
    this.pendingLoanRequestsCount = 0,
    this.pendingOnlinePaymentsCount = 0,
  });

  factory CustomerDashboardData.noMemberships() => CustomerDashboardData(hasActiveMembership: false);
}

// ============================================================================
// State
// ============================================================================

class CustomerDashboardNotifier extends AsyncNotifier<CustomerDashboardData> {
  @override
  Future<CustomerDashboardData> build() async {
    // Real screen passes businessId in via load(); build() stays
    // side-effect-free per Riverpod convention (same pattern as
    // IW-001's InvestorDashboardNotifier).
    return CustomerDashboardData.noMemberships();
  }

  // S1/S2 — initial load, and reload on Business Switched.
  Future<void> load(String businessId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final api = ref.read(customerDashboardApiServiceProvider);
      return api.fetchDashboard(businessId: businessId);
    });
  }
}

final customerDashboardProvider = AsyncNotifierProvider<CustomerDashboardNotifier, CustomerDashboardData>(
  CustomerDashboardNotifier.new,
);

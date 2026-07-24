import 'package:flutter_riverpod/flutter_riverpod.dart';

/// IW-001 Investor Home Dashboard — stub API. Server-side pre-aggregated
/// payload, same pattern as the Owner/Agent/Customer dashboard siblings.
class InvestorDashboardApiService {
  final String baseUrl;
  InvestorDashboardApiService({required this.baseUrl});

  // GET /businesses/{business_id}/investor-dashboard (§2.8) — client
  // renders immediately, caches last-known-good, background-refreshes
  // via polling every 15-30s for V1, not websockets.
  Future<InvestorDashboardData> fetchDashboard({required String businessId}) async {
    throw UnimplementedError('Wire to real API: GET $baseUrl/businesses/$businessId/investor-dashboard');
  }
}

final investorDashboardApiServiceProvider = Provider<InvestorDashboardApiService>((ref) {
  return InvestorDashboardApiService(baseUrl: 'https://api.manaline.app'); // TODO: real base URL
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
      return api.fetchDashboard(businessId: businessId);
    });
  }
}

final investorDashboardProvider = AsyncNotifierProvider<InvestorDashboardNotifier, InvestorDashboardData>(
  InvestorDashboardNotifier.new,
);

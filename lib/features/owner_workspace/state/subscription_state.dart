import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// P4 Subscription — the tier table, and where this business actually sits in
/// it.
///
/// DISPLAY ONLY THIS ROUND. There is no billing plumbing behind any of this:
/// no payment provider, no entitlement column, no enforcement. That is a
/// deliberate scope line, and it is why this screen has no "Subscribe" button
/// — a button that takes a payment nowhere is worse than no button, and a cap
/// that is drawn but not enforced must not be drawn as if it were.
///
/// The counts are real, though. A price list on its own is a brochure; what an
/// Owner needs to know is which tier they are already in and how close the
/// next cap is.
class SubscriptionTier {
  final String name;
  final String monthly;
  final String yearly;
  final int? agents;
  final int? customers;
  final int? investors;

  const SubscriptionTier({
    required this.name,
    required this.monthly,
    required this.yearly,
    required this.agents,
    required this.customers,
    required this.investors,
  });

  /// Enterprise has no numeric caps — nulls mean "no stated limit", not zero.
  bool get isCustom => agents == null;

  bool fits(BusinessUsage u) =>
      isCustom ||
      (u.agents <= agents! && u.customers <= customers! && u.investors <= investors!);
}

/// Owner tiers, as agreed in the pricing discussion. Caps are dual: agents are
/// the primary cost lever (they drive photo generation and query load), while
/// the customer and investor caps are generous and exist to bound edge-case
/// abuse rather than to pinch normal use.
const kOwnerTiers = <SubscriptionTier>[
  SubscriptionTier(
    name: 'Starter',
    monthly: '₹99',
    yearly: '₹999',
    agents: 4,
    customers: 150,
    investors: 20,
  ),
  SubscriptionTier(
    name: 'Growth',
    monthly: '₹199',
    yearly: '₹1,999',
    agents: 10,
    customers: 500,
    investors: 75,
  ),
  SubscriptionTier(
    name: 'Business',
    monthly: '₹349',
    yearly: '₹3,499',
    agents: 25,
    customers: 1500,
    investors: 200,
  ),
  SubscriptionTier(
    name: 'Enterprise',
    monthly: 'Custom',
    yearly: 'Custom',
    agents: null,
    customers: null,
    investors: null,
  ),
];

class BusinessUsage {
  final int agents;
  final int customers;
  final int investors;

  const BusinessUsage({
    required this.agents,
    required this.customers,
    required this.investors,
  });

  /// The cheapest tier this business already fits inside. Never null —
  /// Enterprise has no caps, so it always matches.
  SubscriptionTier get currentTier =>
      kOwnerTiers.firstWhere((t) => t.fits(this));
}

class SubscriptionApiService {
  SubscriptionApiService(this._db);
  final SupabaseClient _db;

  /// Counts ACTIVE memberships only. A removed agent no longer generates load
  /// or photos, so counting them would show an Owner as over a cap they are
  /// not actually over — and this screen's whole value is that its numbers
  /// match reality.
  Future<BusinessUsage> fetchUsage(String businessId) async {
    final rows = await _db
        .from('business_members')
        .select('role, membership_status')
        .eq('business_id', businessId)
        .eq('membership_status', 'Active');

    int count(String role) => rows.where((r) => r['role'] == role).length;

    return BusinessUsage(
      agents: count('Agent'),
      customers: count('Customer'),
      investors: count('Investor'),
    );
  }
}

final subscriptionApiServiceProvider = Provider<SubscriptionApiService>(
  (ref) => SubscriptionApiService(Supabase.instance.client),
);

final businessUsageProvider =
    FutureProvider.family<BusinessUsage, String>((ref, businessId) {
  return ref.read(subscriptionApiServiceProvider).fetchUsage(businessId);
});

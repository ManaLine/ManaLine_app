import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// IW-005 My Profile / Business Memberships — real Supabase wiring over
/// Module 0 (persons/person_addresses) and Module 1 (business_members).
///
/// RLS note: `persons_self_select`/`persons_self_update` and
/// `business_members_self_select` (0012/0013) already scope every one of
/// these queries to the calling person's own rows — no extra
/// `person_id = current_person_id()` guard is added client-side on top of
/// that; the `.eq('person_id', personId)` calls below are simply "which
/// row do I want", not a security boundary (Postgres/RLS is the boundary).
///
/// BR-238: important-field edits (phone, address, Aadhaar) keep prior
/// value in history and notify every Owner this Investor is connected
/// to — the "Previous Data" comparison view itself is Owner-side only,
/// not built here; this screen's job is just to fire the edit call
/// correctly.
/// BR-239: Aadhaar is permanent once captured — no edit method exists
/// for it at all in this API surface; only Owner (PIN + reason, via
/// OW-003) can correct it.
class InvestorProfileApiService {

  SupabaseClient get _db => Supabase.instance.client;

  Future<InvestorProfileSummary> fetchProfile({required String personId}) async {
    final row = await _db
        .from('persons')
        .select('full_name, mlid, mobile_number, aadhaar_number, profile_photo_url, '
            'verification_ring, '
            'person_addresses(address_id, village_id, door_no, area_locality, pin_code, '
            'mandal, district, is_current, locations(village_town_name))')
        .eq('person_id', int.parse(personId))
        .single();

    final addresses = ((row['person_addresses'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final currentAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a?['is_current'] == true,
          orElse: () => addresses.isNotEmpty ? addresses.first : null,
        );

    final aadhaar = row['aadhaar_number'] as String?;
    // View-only last-4: `persons.aadhaar_number` is the only column the
    // schema has (stored encrypted at the app layer per its own comment);
    // there is no dedicated `aadhaar_last4` column, so this is derived
    // client-side from whatever `aadhaar_number` returns. If the app-layer
    // encryption means this column is never returned in cleartext to a
    // Self-select caller, this derivation silently produces garbage —
    // flagged rather than guessed around.
    final aadhaarLast4 = (aadhaar != null && aadhaar.length >= 4) ? aadhaar.substring(aadhaar.length - 4) : null;

    return InvestorProfileSummary(
      fullName: row['full_name'] as String? ?? '',
      mlid: row['mlid'] as String? ?? '',
      phoneNumber: row['mobile_number'] as String?,
      aadhaarLast4: aadhaarLast4,
      profilePhotoUrl: row['profile_photo_url'] as String?,
      verificationRing: (row['verification_ring'] as String?) == 'GREEN' ? VerificationRing.green : VerificationRing.red,
      currentAddress: currentAddress == null
          ? null
          : InvestorAddress(
              addressId: currentAddress['address_id'] as String,
              villageName: (currentAddress['locations'] as Map<String, dynamic>?)?['village_town_name'] as String? ?? '',
              mandal: currentAddress['mandal'] as String? ?? '',
              district: currentAddress['district'] as String? ?? '',
              pinCode: currentAddress['pin_code'] as String? ?? '',
              doorNo: currentAddress['door_no'] as String?,
              areaLocality: currentAddress['area_locality'] as String?,
            ),
    );
  }

  // Cross-business membership list (new this session, per spec) —
  // separate call from the profile fetch. Maps to
  // GET /persons/{person_id}/memberships (04_API_Specification_v1_Part1.md
  // §2.10) via `business_members` joined to `businesses`.
  Future<List<BusinessMembership>> fetchMemberships({required String personId}) async {
    final rows = await _db
        .from('business_members')
        .select('business_id, role, membership_status, businesses(business_name)')
        .eq('person_id', int.parse(personId));

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final business = r['businesses'] as Map<String, dynamic>?;
      return BusinessMembership(
        businessId: r['business_id'] as String,
        businessName: business?['business_name'] as String? ?? '',
        role: _roleFromString(r['role'] as String?),
        membershipStatus: r['membership_status'] as String? ?? '',
      );
    }).toList();
  }

  MembershipRole _roleFromString(String? raw) {
    switch (raw) {
      case 'Owner':
        return MembershipRole.owner;
      case 'Agent':
        return MembershipRole.agent;
      case 'Investor':
        return MembershipRole.investor;
      case 'Customer':
      default:
        return MembershipRole.customer;
    }
  }

  /// BR-238: phone is an "important field" whose edits keep prior-value
  /// history. Backed by `person_phone_history` (migration 0019), added to
  /// close the previously-flagged gap — mirrors `updateAddress`'s own
  /// close-old-row/insert-new-row pattern exactly (same is_current/to_date
  /// invariant).
  ///
  /// Notification to connected Owners is still NOT something this client
  /// call can do: `notifications` (0018 RLS) has no client INSERT policy
  /// for any role — every notification is a system/trigger side-effect.
  /// If BR-238's Owner-notification is meant to fire on this edit, it
  /// needs a DB trigger or Edge Function on `persons`/`person_phone_history`,
  /// not client code here — unchanged from the prior flag.
  Future<void> updatePhone({required String personId, required String phoneNumber}) async {
    final pid = int.parse(personId);
    final today = DateTime.now().toIso8601String().split('T').first;

    await _db
        .from('person_phone_history')
        .update({'to_date': today, 'is_current': false})
        .eq('person_id', pid)
        .eq('is_current', true);

    await _db.from('person_phone_history').insert({
      'person_id': pid,
      'phone_number': phoneNumber,
      'from_date': today,
      'is_current': true,
      'reason': 'Updated',
    });

    await _db.from('persons').update({'mobile_number': phoneNumber}).eq('person_id', pid);
  }

  /// Real BR-225 "full address history" write — matches the pattern the
  /// schema doc itself describes and that `customer_state.dart`'s
  /// `createCustomer` already uses for the first-address-ever case:
  /// the previous `is_current=true` row is closed out (`to_date`,
  /// `is_current=false`) rather than edited in place, and a brand-new row
  /// is inserted as the new current address. This IS the BR-238
  /// "keeps prior value in history" mechanism for addresses — no
  /// additional history table is needed or invented, because
  /// `person_addresses` already permanently retains every prior row.
  ///
  /// Not wrapped in a single DB transaction: the Supabase client here has
  /// no cross-statement transaction primitive available (same constraint
  /// already accepted elsewhere in this codebase, e.g. `createCustomer`'s
  /// sequential business_members→customers inserts) — this is two
  /// sequential REST calls. A partial failure (old row closed, new row
  /// insert fails) would leave the person with no `is_current=true` row.
  /// Flagged as a candidate for a SECURITY DEFINER RPC if that risk isn't
  /// acceptable; not solved here since that would mean inventing a new
  /// server-side function outside this chat's file scope.
  ///
  /// Owner-notification gap: same as `updatePhone` above — no client
  /// INSERT policy exists on `notifications`, so any BR-238 Owner alert
  /// for an address change must be a server-side trigger, not this call.
  /// FIXED (this pass): mandal/district/state were previously accepted as
  /// free-text params and inserted verbatim — but person_addresses' own
  /// table comment says these are "auto-derived from village". Now looked
  /// up from `locations` via villageId server-side (well, client-side
  /// here since this is a self-edit RLS path, but the principle is the
  /// same as the Owner/Agent RPC fix: never trust a caller-supplied value
  /// that should be derived from the FK instead), so a caller can no
  /// longer pass a villageId that disagrees with its own mandal/district/
  /// state. villageName/mandal/district/state params kept for display use
  /// in the picker UI, but are no longer trusted for the actual insert.
  Future<void> updateAddress({
    required String personId,
    required String addressId,
    required String villageId,
    required String villageName,
    String? doorNo,
    String? areaLocality,
    required String pinCode,
  }) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final pid = int.parse(personId);

    final location = await _db.from('locations').select('mandal, district, state').eq('location_id', villageId).eq('status', 'Active').single();

    await _db.from('person_addresses').update({
      'to_date': today,
      'is_current': false,
      'reason': 'Shifted',
    }).eq('address_id', addressId).eq('person_id', pid);

    await _db.from('person_addresses').insert({
      'person_id': pid,
      'door_no': doorNo ?? '-',
      'area_locality': areaLocality,
      'pin_code': pinCode,
      'village_id': villageId,
      'mandal': location['mandal'],
      'district': location['district'],
      'state': location['state'],
      'from_date': today,
      'is_current': true,
    });
  }
}

final investorProfileApiServiceProviderIW005 = Provider<InvestorProfileApiService>((ref) {
  return InvestorProfileApiService();
});

enum VerificationRing { green, red }

class InvestorAddress {
  final String addressId;
  final String villageName;
  final String mandal;
  final String district;
  final String pinCode;
  final String? doorNo;
  final String? areaLocality;

  InvestorAddress({
    required this.addressId,
    required this.villageName,
    required this.mandal,
    required this.district,
    required this.pinCode,
    this.doorNo,
    this.areaLocality,
  });
}

class InvestorProfileSummary {
  final String fullName;
  final String mlid;
  final String? phoneNumber;
  final String? aadhaarLast4; // view-only, never full number
  final String? profilePhotoUrl;
  final VerificationRing verificationRing;
  final InvestorAddress? currentAddress;

  InvestorProfileSummary({
    required this.fullName,
    required this.mlid,
    this.phoneNumber,
    this.aadhaarLast4,
    this.profilePhotoUrl,
    required this.verificationRing,
    this.currentAddress,
  });
}

enum MembershipRole {
  owner('Owner'),
  agent('Agent'),
  investor('Investor'),
  customer('Customer');

  final String label;
  const MembershipRole(this.label);
}

class BusinessMembership {
  final String businessId;
  final String businessName;
  final MembershipRole role;
  final String membershipStatus; // Active | Pending Invitation | Suspended | Removed

  BusinessMembership({
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.membershipStatus,
  });
}

class InvestorProfileState {
  final bool loading;
  final InvestorProfileSummary? profile;
  final List<BusinessMembership> memberships;
  final String? error;

  const InvestorProfileState({
    this.loading = false,
    this.profile,
    this.memberships = const [],
    this.error,
  });

  InvestorProfileState copyWith({
    bool? loading,
    InvestorProfileSummary? profile,
    List<BusinessMembership>? memberships,
    String? error,
    bool clearError = false,
  }) {
    return InvestorProfileState(
      loading: loading ?? this.loading,
      profile: profile ?? this.profile,
      memberships: memberships ?? this.memberships,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InvestorProfileNotifierIW005 extends Notifier<InvestorProfileState> {
  String? _personId;

  @override
  InvestorProfileState build() => const InvestorProfileState();

  Future<void> load(String personId) async {
    _personId = personId;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(investorProfileApiServiceProviderIW005);
      final profile = await api.fetchProfile(personId: personId);
      final memberships = await api.fetchMemberships(personId: personId);
      state = state.copyWith(profile: profile, memberships: memberships, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> updatePhone({required String personId, required String phoneNumber}) async {
    try {
      await ref.read(investorProfileApiServiceProviderIW005).updatePhone(personId: personId, phoneNumber: phoneNumber);
      if (_personId != null) await load(_personId!);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> updateAddress({
    required String personId,
    required String addressId,
    required String villageId,
    required String villageName,
    String? doorNo,
    String? areaLocality,
    required String pinCode,
  }) async {
    try {
      await ref.read(investorProfileApiServiceProviderIW005).updateAddress(
            personId: personId,
            addressId: addressId,
            villageId: villageId,
            villageName: villageName,
            doorNo: doorNo,
            areaLocality: areaLocality,
            pinCode: pinCode,
          );
      if (_personId != null) await load(_personId!);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final investorProfileProviderIW005 = NotifierProvider<InvestorProfileNotifierIW005, InvestorProfileState>(
  InvestorProfileNotifierIW005.new,
);

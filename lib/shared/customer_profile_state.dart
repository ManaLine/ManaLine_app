import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One customer's personal details, for the profile screen.
///
/// WHY NOT REUSE MltiPerson. `fetchOneByCustomer` reads almost this shape and
/// then throws the row away unless `mlid_type == 'MLTI'` — it exists to find
/// people who still need converting. A profile screen has to open for anybody.
class ManaCustomerProfile {
  final int personId;
  final String customerId;
  final String mlid;

  /// 'MLTI' (temporary) or 'MLPI' (permanent, minted from an Aadhaar).
  final String mlidType;

  final String fullName;
  final String careOf;

  /// '1' male, '0' female, 'O' other — the same digit the MLID carries.
  final String genderDigit;

  final String mobile;
  final String? dob;

  /// The last four digits, which is all this app keeps in the clear. The
  /// number itself is stored only as a hash.
  final String? aadhaarLast4;

  final String? photoUrl;
  final String village;
  final String? villageId;
  final String doorNo;
  final String pinCode;
  final String addressLine;

  const ManaCustomerProfile({
    required this.personId,
    required this.customerId,
    required this.mlid,
    required this.mlidType,
    required this.fullName,
    required this.careOf,
    required this.genderDigit,
    required this.mobile,
    required this.dob,
    required this.aadhaarLast4,
    required this.photoUrl,
    required this.village,
    required this.villageId,
    required this.doorNo,
    required this.pinCode,
    required this.addressLine,
  });

  bool get isTemporary => mlidType == 'MLTI';

  /// True once an MLID has been minted from this Aadhaar.
  ///
  /// THE ONE THING THIS SCREEN WILL NOT LET ANYBODY CHANGE. An MLPI is
  /// `MLPI + gender digit + the last eight of the Aadhaar`, derived once and
  /// then printed on receipts, searched by, and quoted down a phone. Editing
  /// the Aadhaar afterwards does not re-mint it — it leaves an ID that no
  /// longer describes the person it belongs to, silently.
  ///
  /// The Owner has asked for an "Aadhaar lock" before deploy and has not yet
  /// said which of three things it means (see CLAUDE.md). Refusing the edit
  /// here is the conservative reading and the only one that cannot corrupt an
  /// identity while the question is open.
  bool get aadhaarIsLocked => mlidType == 'MLPI';
}

class CustomerProfileApiService {
  CustomerProfileApiService(this._db);
  final SupabaseClient _db;

  /// The FK is named although it does not have to be: `customers` has exactly
  /// one foreign key to `persons` (`customers_person_id_fkey`, checked against
  /// pg_constraint), so an unqualified `persons(...)` resolves fine here —
  /// which is why the MLTI reader next door gets away with one.
  ///
  /// Naming it costs nothing and says which relationship is meant. The pairs
  /// that genuinely cannot be left bare are the eleven in
  /// ambiguous_embed_guard_test; `business_members` → `persons` is the one
  /// that has bitten this app twice.
  Future<ManaCustomerProfile?> fetch(String customerId) async {
    final row = await _db.from('customers').select('''
          customer_id,
          person_id,
          persons!customers_person_id_fkey(
            person_id, mlid, mlid_type, gender_digit, full_name,
            father_husband_name, mobile_number, dob, aadhaar_last4,
            live_photo_url, profile_photo_url,
            person_addresses(is_current, door_no, pin_code, village_id,
                             locations(village_town_name))
          )
        ''').eq('customer_id', customerId).maybeSingle();
    if (row == null) return null;
    final p = row['persons'] as Map<String, dynamic>?;
    if (p == null) return null;

    final addresses = (p['person_addresses'] as List?) ?? const [];
    // The CURRENT address, falling back to whatever exists. A person with two
    // rows and neither marked current is a real state in migrated data.
    final current = addresses.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a?['is_current'] == true,
          orElse: () => addresses.isNotEmpty
              ? addresses.first as Map<String, dynamic>
              : null,
        );
    final village =
        (current?['locations'] as Map<String, dynamic>?)?['village_town_name']
                as String? ??
            '';
    final doorNo = current?['door_no'] as String? ?? '';
    final pin = current?['pin_code'] as String? ?? '';

    return ManaCustomerProfile(
      personId: (p['person_id'] as num).toInt(),
      customerId: row['customer_id'] as String,
      mlid: p['mlid'] as String? ?? '',
      mlidType: (p['mlid_type'] ?? '').toString(),
      fullName: p['full_name'] as String? ?? '',
      careOf: p['father_husband_name'] as String? ?? '',
      genderDigit: (p['gender_digit'] ?? '').toString(),
      mobile: p['mobile_number'] as String? ?? '',
      dob: p['dob'] as String?,
      aadhaarLast4: p['aadhaar_last4'] as String?,
      // live_photo_url first: it is the one taken at a doorstep, which is the
      // one an agent needs to recognise somebody by.
      photoUrl: (p['live_photo_url'] as String?)?.isNotEmpty == true
          ? p['live_photo_url'] as String
          : p['profile_photo_url'] as String?,
      village: village,
      villageId: current?['village_id'] as String?,
      doorNo: doorNo,
      pinCode: pin,
      addressLine:
          [doorNo, village, pin].where((s) => s.isNotEmpty).join(', '),
    );
  }

  /// Mobile, DOB, Aadhaar and photo.
  ///
  /// EXISTING RPC, NOT A NEW ONE. `app.owner_update_member_identity` already
  /// does exactly this and COALESCEs each argument, so a null leaves the
  /// stored value alone — which is what makes a partial edit safe.
  Future<void> updateIdentity({
    required int personId,
    String? mobileNumber,
    String? dob,
    String? aadhaarNumber,
    String? profilePhotoUrl,
  }) async {
    await _db.schema('app').rpc('owner_update_member_identity', params: {
      'p_person_id': personId,
      'p_mobile_number': mobileNumber,
      'p_dob': dob,
      'p_aadhaar_number': aadhaarNumber,
      'p_profile_photo_url': profilePhotoUrl,
    });
  }

  /// Door number, PIN and village.
  ///
  /// `app.owner_update_customer_address` derives mandal, district and state
  /// from the village rather than taking them, which is why this screen asks
  /// for a village and a door number and nothing else.
  Future<void> updateAddress({
    required int personId,
    required String doorNo,
    required String pinCode,
    required String villageId,
  }) async {
    await _db.schema('app').rpc('owner_update_customer_address', params: {
      'p_person_id': personId,
      'p_door_no': doorNo,
      'p_pin_code': pinCode,
      'p_village_id': villageId,
    });
  }
}

final customerProfileApiServiceProvider =
    Provider<CustomerProfileApiService>((ref) {
  return CustomerProfileApiService(Supabase.instance.client);
});

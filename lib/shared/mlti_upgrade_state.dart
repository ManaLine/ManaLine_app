import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turning a temporary identity into a permanent one.
///
/// A customer copied out of a paper ledger has no Aadhaar number, so
/// `app.mint_person_mlid` issues an MLTI — 'MLTI' plus a gender digit plus
/// eight random digits. An MLPI is 'MLPI' plus the gender digit plus the last
/// eight digits of the Aadhaar, which is why only an Aadhaar can make one.
///
/// Counted on the live books when this was written: 65 MLTI people against 34
/// MLPI. Every one of the 65 already has a mobile number and a current
/// address; not one has an Aadhaar. So this flow is not about collecting a
/// profile — it is about collecting the one thing that is missing.
///
/// IN BOTH WORKSPACES, which is why it lives here and not under
/// features/owner_workspace. The Owner works from a list; the agent meets the
/// customer at their door, which is the only place an Aadhaar card actually
/// is, so the same form opens from the collection round.
class MltiUpgradeApiService {
  SupabaseClient get _db => Supabase.instance.client;

  /// The people on this book still carrying a temporary ID.
  ///
  /// THE FOREIGN KEY IS NAMED because business_members has TWO of them to
  /// persons — person_id and invited_by_person_id — and it is one of the
  /// eleven ambiguous pairs ambiguous_embed_guard_test lists. An unqualified
  /// `persons(...)` here answers PGRST201 and the screen just says it could
  /// not load. That exact mistake shipped in build 14.8 on this same pair.
  Future<List<MltiPerson>> fetchPending({required String businessId}) async {
    final rows = await _db.from('business_members').select('''
          person_id, role,
          persons!business_members_person_id_fkey!inner(
            person_id, mlid, mlid_type, full_name, father_husband_name,
            mobile_number, dob, live_photo_url,
            person_addresses(is_current, locations(village_town_name))
          )
        ''').eq('business_id', businessId).eq('membership_status', 'Active');

    final out = <MltiPerson>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final p = r['persons'] as Map<String, dynamic>?;
      if (p == null || p['mlid_type'] != 'MLTI') continue;
      final addresses = (p['person_addresses'] as List?) ?? const [];
      final current = addresses.cast<Map<String, dynamic>?>().firstWhere(
            (a) => a?['is_current'] == true,
            orElse: () => addresses.isNotEmpty
                ? addresses.first as Map<String, dynamic>
                : null,
          );
      out.add(MltiPerson(
        personId: (p['person_id'] as num).toInt(),
        mlid: p['mlid'] as String? ?? '',
        fullName: p['full_name'] as String? ?? '',
        careOf: p['father_husband_name'] as String? ?? '',
        village: (current?['locations'] as Map<String, dynamic>?)?['village_town_name']
                as String? ??
            '',
        mobile: p['mobile_number'] as String? ?? '',
        role: r['role'] as String? ?? '',
        hasDob: p['dob'] != null,
        hasPhoto: p['live_photo_url'] != null,
      ));
    }
    // Name order: the Owner is looking for somebody in particular, and a list
    // of 65 in insertion order is a list nobody can find anybody in.
    out.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return out;
  }

  /// One person, by the customer row the agent just tapped.
  ///
  /// The collection round already knows the MLID -- it prints it under the
  /// name -- so it can tell an MLTI from an MLPI without asking. What it does
  /// not carry is the person_id or the C/o, and the upgrade form needs both.
  /// One round trip on tap is the right cost: the alternative is widening
  /// v_collection_due, a view eight screens read, for a field one of them uses
  /// occasionally.
  Future<MltiPerson?> fetchOneByCustomer(String customerId) async {
    final row = await _db.from('customers').select('''
          person_id,
          persons!inner(
            person_id, mlid, mlid_type, full_name, father_husband_name,
            mobile_number, dob, live_photo_url,
            person_addresses(is_current, locations(village_town_name))
          )
        ''').eq('customer_id', customerId).maybeSingle();
    if (row == null) return null;
    final p = row['persons'] as Map<String, dynamic>?;
    if (p == null || p['mlid_type'] != 'MLTI') return null;
    final addresses = (p['person_addresses'] as List?) ?? const [];
    final current = addresses.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a?['is_current'] == true,
          orElse: () =>
              addresses.isNotEmpty ? addresses.first as Map<String, dynamic> : null,
        );
    return MltiPerson(
      personId: (p['person_id'] as num).toInt(),
      mlid: p['mlid'] as String? ?? '',
      fullName: p['full_name'] as String? ?? '',
      careOf: p['father_husband_name'] as String? ?? '',
      village: (current?['locations'] as Map<String, dynamic>?)?['village_town_name']
              as String? ??
          '',
      mobile: p['mobile_number'] as String? ?? '',
      role: 'Customer',
      hasDob: p['dob'] != null,
      hasPhoto: p['live_photo_url'] != null,
    );
  }

  /// How complete each customer's profile is, keyed by customer_id.
  ///
  /// Five things make a complete record: a permanent ID, a mobile number, a
  /// date of birth, a live photo and a current village. The ring around a
  /// customer's photo closes as they are filled in -- the Owner's request,
  /// and the reason this is a fraction rather than a flag.
  ///
  /// One call for the whole round rather than one per row. On the live book
  /// that is 58 customers in a single query instead of 58.
  Future<Map<String, double>> fetchCompleteness(String businessId) async {
    final rows = await _db
        .schema('app')
        .rpc('profile_completeness', params: {'p_business_id': businessId});
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['customer_id'] as String:
            ((r['filled'] as num).toDouble() / (r['total'] as num).toDouble())
                .clamp(0.0, 1.0),
    };
  }

  /// Returns the new MLID.
  ///
  /// Every failure here is a sentence written for a person — a duplicate
  /// Aadhaar, a number that is not twelve digits, an ID collision — raised by
  /// app.mint_person_mlid rather than by a constraint. They are surfaced as
  /// they come rather than replaced with a generic message, because "this
  /// Aadhaar already belongs to an existing account" is the most useful thing
  /// this flow can ever tell somebody: it means the customer is already in the
  /// book twice.
  Future<String> convert({
    required int personId,
    required String businessId,
    required String aadhaarNumber,
    DateTime? dob,
    String? livePhotoUrl,
  }) async {
    final result = await _db
        .schema('app')
        .rpc('convert_customer_to_mlpi', params: {
      'p_person_id': personId,
      'p_business_id': businessId,
      'p_aadhaar_number': aadhaarNumber,
      'p_dob': dob == null
          ? null
          : '${dob.year.toString().padLeft(4, '0')}-'
              '${dob.month.toString().padLeft(2, '0')}-'
              '${dob.day.toString().padLeft(2, '0')}',
      'p_live_photo_url': livePhotoUrl,
    }) as Map<String, dynamic>;
    return result['new_mlid'] as String;
  }
}

class MltiPerson {
  final int personId;
  final String mlid;
  final String fullName;
  final String careOf;
  final String village;
  final String mobile;
  final String role;
  final bool hasDob;
  final bool hasPhoto;

  const MltiPerson({
    required this.personId,
    required this.mlid,
    required this.fullName,
    required this.careOf,
    required this.village,
    required this.mobile,
    required this.role,
    required this.hasDob,
    required this.hasPhoto,
  });
}

class MltiUpgradeState {
  final List<MltiPerson> people;
  final bool loading;
  final String? error;

  const MltiUpgradeState({
    this.people = const [],
    this.loading = false,
    this.error,
  });

  MltiUpgradeState copyWith({
    List<MltiPerson>? people,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      MltiUpgradeState(
        people: people ?? this.people,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

final mltiUpgradeApiServiceProvider =
    Provider<MltiUpgradeApiService>((ref) => MltiUpgradeApiService());

class MltiUpgradeNotifier extends AutoDisposeNotifier<MltiUpgradeState> {
  @override
  MltiUpgradeState build() => const MltiUpgradeState();

  Future<void> load(String businessId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final people = await ref
          .read(mltiUpgradeApiServiceProvider)
          .fetchPending(businessId: businessId);
      state = state.copyWith(people: people, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Drops one person from the list without a round trip.
  ///
  /// The list is "who still has a temporary ID", so a converted person leaves
  /// it by definition. Refetching would be a second call to say the same
  /// thing, and on a village connection it is the difference between the row
  /// disappearing now and disappearing in four seconds.
  void forget(int personId) => state = state.copyWith(
      people: state.people.where((p) => p.personId != personId).toList());
}

final mltiUpgradeProvider =
    AutoDisposeNotifierProvider<MltiUpgradeNotifier, MltiUpgradeState>(
        MltiUpgradeNotifier.new);

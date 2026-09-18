import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two rows that look like one village.
///
/// The pair arrives already pointed: `keep` is the row the server suggests
/// survives -- the one more people already live on, tie-broken towards the
/// Directory row whose mandal and district came from the LGD reference rather
/// than from somebody typing at a doorstep. The Owner can swap it, because the
/// suggestion is about how many addresses get rewritten and the Owner is the
/// one who knows which name the village is actually called by.
class ManaVillageDuplicate {
  final String keepId;
  final String keepName;
  final String keepMandal;
  final String keepDistrict;
  final int keepPeople;

  final String dropId;
  final String dropName;
  final String dropMandal;
  final String dropDistrict;
  final int dropPeople;

  final String pinCode;

  /// Why this pair cannot be merged, or null when it can.
  ///
  /// COMPUTED BY THE SERVER, not re-derived here. The same function answers
  /// this question again inside the merge itself, so the list and the refusal
  /// can never disagree -- and an area can be added to a village between the
  /// Owner reading the list and tapping Merge.
  final String? blockedReason;

  const ManaVillageDuplicate({
    required this.keepId,
    required this.keepName,
    required this.keepMandal,
    required this.keepDistrict,
    required this.keepPeople,
    required this.dropId,
    required this.dropName,
    required this.dropMandal,
    required this.dropDistrict,
    required this.dropPeople,
    required this.pinCode,
    required this.blockedReason,
  });

  bool get isBlocked => (blockedReason ?? '').isNotEmpty;

  /// The same pair with the two sides exchanged.
  ///
  /// The blocked reason is DROPPED rather than carried over, because it was
  /// computed for the other direction and may not hold for this one -- the
  /// area-set check is symmetric today, but a reason quoted from the wrong
  /// direction would be a sentence nobody can act on. The server is asked
  /// again for the swapped pair.
  ManaVillageDuplicate swapped() => ManaVillageDuplicate(
        keepId: dropId,
        keepName: dropName,
        keepMandal: dropMandal,
        keepDistrict: dropDistrict,
        keepPeople: dropPeople,
        dropId: keepId,
        dropName: keepName,
        dropMandal: keepMandal,
        dropDistrict: keepDistrict,
        dropPeople: keepPeople,
        pinCode: pinCode,
        blockedReason: null,
      );

  factory ManaVillageDuplicate.fromRow(Map<String, dynamic> r) =>
      ManaVillageDuplicate(
        keepId: (r['keep_location_id'] ?? '').toString(),
        keepName: (r['keep_name'] ?? '').toString(),
        keepMandal: (r['keep_mandal'] ?? '').toString(),
        keepDistrict: (r['keep_district'] ?? '').toString(),
        keepPeople: (r['keep_people'] as num?)?.toInt() ?? 0,
        dropId: (r['drop_location_id'] ?? '').toString(),
        dropName: (r['drop_name'] ?? '').toString(),
        dropMandal: (r['drop_mandal'] ?? '').toString(),
        dropDistrict: (r['drop_district'] ?? '').toString(),
        dropPeople: (r['drop_people'] as num?)?.toInt() ?? 0,
        pinCode: (r['pin_code'] ?? '').toString(),
        blockedReason: (r['blocked_reason'] as String?)?.isEmpty == true
            ? null
            : r['blocked_reason'] as String?,
      );
}

class VillageMergeApiService {
  VillageMergeApiService(this._db);
  final SupabaseClient _db;

  Future<List<ManaVillageDuplicate>> candidates(String businessId) async {
    final rows = await _db.schema('app').rpc(
      'duplicate_village_candidates',
      params: {'p_business_id': businessId},
    );
    return ((rows as List?) ?? const [])
        .map((r) => ManaVillageDuplicate.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Ask whether a pair can be merged in this direction. Empty means it can.
  ///
  /// Needed because the Owner can swap the two sides, and the answer is
  /// computed per direction rather than per pair.
  ///
  /// EMPTY STRING, NOT NULL, and the difference matters. This is called
  /// through `NetworkErrorHandler.run`, which returns null when the call
  /// FAILED. If "allowed" were also null the screen could not tell a village
  /// it may merge from a question it never got an answer to -- and it would
  /// resolve that ambiguity in the direction that offers the button.
  Future<String> blockedReason({
    required String businessId,
    required String loserId,
    required String survivorId,
  }) async {
    final r = await _db.schema('app').rpc(
      'village_merge_blocked_reason',
      params: {
        'p_business_id': businessId,
        'p_loser_id': loserId,
        'p_survivor_id': survivorId,
      },
    );
    return (r as String?) ?? '';
  }

  /// Returns the server's summary of what moved.
  Future<Map<String, dynamic>> merge({
    required String businessId,
    required String loserId,
    required String survivorId,
  }) async {
    final r = await _db.schema('app').rpc(
      'merge_villages',
      params: {
        'p_business_id': businessId,
        'p_loser_id': loserId,
        'p_survivor_id': survivorId,
      },
    );
    return (r as Map).cast<String, dynamic>();
  }
}

final villageMergeApiServiceProvider =
    Provider<VillageMergeApiService>((ref) {
  return VillageMergeApiService(Supabase.instance.client);
});

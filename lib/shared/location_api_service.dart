import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one place that reads and writes `locations`.
///
/// WHY THIS EXISTS: `locations` was queried from THIRTEEN different files —
/// registration, three profile screens, two customer-management screens, the
/// business setup, the migration screen and the bulk wizard — each with its own
/// slightly different select list, its own idea of whether to filter on
/// `status = 'Active'`, and its own limit. The village/PIN behaviour was then
/// fixed one file at a time, repeatedly, because a fix in one screen had no
/// effect on the other twelve.
///
/// That is exactly the "second place that queries the same table" the project's
/// own layering rule forbids, and it is the largest layer violation in the
/// codebase.
///
/// WHAT THIS DELIBERATELY DOES NOT DO: it does not decide anything about a
/// village. The LGD reference SUGGESTS and never validates — 8.1% of PIN codes
/// list two districts after the post-2022 splits — so every method here
/// returns what the database holds and leaves the choice to the Owner.
class ManaVillage {
  final String locationId;
  final String name;
  final String pinCode;
  final String mandal;
  final String district;
  final String state;

  const ManaVillage({
    required this.locationId,
    required this.name,
    required this.pinCode,
    required this.mandal,
    required this.district,
    required this.state,
  });

  factory ManaVillage.fromRow(Map<String, dynamic> r) => ManaVillage(
        locationId: (r['location_id'] ?? '').toString(),
        name: (r['village_town_name'] ?? '').toString(),
        pinCode: (r['pin_code'] ?? '').toString(),
        mandal: (r['mandal'] ?? '').toString(),
        district: (r['district'] ?? '').toString(),
        state: (r['state'] ?? '').toString(),
      );

  /// What the picker rows show under the name.
  String get placeLabel => [mandal, district]
      .where((s) => s.trim().isNotEmpty)
      .join(' · ');
}

class LocationApiService {
  final SupabaseClient _db;
  const LocationApiService(this._db);

  /// Every column any caller needed, so no screen has to re-derive the list
  /// and none of them can quietly drift apart again.
  static const _columns =
      'location_id, village_town_name, pin_code, mandal, district, state';

  /// The fewest letters of a village name [searchByPin] will search on. A PIN
  /// alone can carry fifty villages; that is the directory, not a shortlist.
  static const minVillageLetters = 3;

  /// Villages for a PIN: the ones already in use first, then everything the
  /// LGD reference knows, optionally narrowed by name.
  ///
  /// `status = 'Active'` is applied HERE rather than trusted to each caller:
  /// two of the thirteen call sites omitted it and were offering retired
  /// villages as if they were current.
  ///
  /// THE REFERENCE HALF EXISTS BECAUSE `locations` IS NOT A DIRECTORY. It holds
  /// only villages some business already operates in, so a new book finds it
  /// empty and every PIN answered with nothing — 517536 reported no villages
  /// while the reference carried fifty, and 524129 while it carried Punabaka.
  ///
  /// A reference row has an EMPTY [ManaVillage.locationId]: it is a suggestion,
  /// and the `locations` row is written only if somebody picks it. Callers must
  /// put a pick through [resolveId] before storing it against a customer or an
  /// operating area.
  ///
  /// A PIN ALONE SEARCHES NOTHING. It needs at least [minVillageLetters] of the
  /// name too, and the result is sorted A to Z.
  Future<List<ManaVillage>> searchByPin({
    required String pinCode,
    String query = '',
    int limit = 10,
  }) async {
    final pin = pinCode.trim();
    if (pin.length != 6) return const [];
    // A PIN with no name searches nothing, so the screen can ask for the name
    // instead of showing everything.
    if (query.trim().length < minVillageLetters) return const [];

    var q = _db
        .from('locations')
        .select(_columns)
        .eq('status', 'Active')
        .eq('pin_code', pin);

    final needle = query.trim();
    if (needle.isNotEmpty) q = q.ilike('village_town_name', '%$needle%');

    final rows = await q.limit(limit);
    final results = [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        ManaVillage.fromRow(r),
    ];

    final seen = {for (final v in results) v.name.toLowerCase()};
    final lowerNeedle = needle.toLowerCase();

    // An unreachable reference must leave the in-use villages standing rather
    // than empty the list, which would be the original bug again.
    List<Map<String, dynamic>> reference = const [];
    try {
      final suggested =
          await _db.schema('app').rpc('suggest_villages', params: {'p_pincode': pin});
      reference = (suggested as List? ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {
      return results;
    }

    for (final r in reference) {
      if (results.length >= limit) break;
      final name = ((r['village'] as String?) ?? '').trim();
      if (name.isEmpty) continue;
      if (lowerNeedle.isNotEmpty && !name.toLowerCase().contains(lowerNeedle)) continue;
      if (!seen.add(name.toLowerCase())) continue;
      results.add(ManaVillage(
        locationId: '', // suggestion — see resolveId
        name: name,
        pinCode: pin,
        mandal: ((r['mandal'] as String?) ?? '').trim(),
        district: ((r['district'] as String?) ?? '').trim(),
        state: ((r['state'] as String?) ?? '').trim(),
      ));
    }

    // A to Z across the whole list. Ordering by provenance — in use first,
    // reference after — is an order only the database understands; the person
    // reading it is looking for a name.
    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  /// The `location_id` for a chosen village, creating the row when the pick
  /// came from the reference rather than from a village already in use.
  ///
  /// Writing all fifty villages the moment a PIN is typed would fill
  /// `locations` with places nobody operates in, so the write waits for a
  /// decision.
  Future<String> resolveId(ManaVillage village) async {
    if (village.locationId.isNotEmpty) return village.locationId;
    final created = await addIfMissing(
      pinCode: village.pinCode,
      villageTownName: village.name,
      // 'Village' and 'Town' are the whole of location_area_type_enum, and
      // every directory pick in this app already hardcodes the former.
      areaType: 'Village',
      mandal: village.mandal,
      district: village.district,
      state: village.state,
    );
    return created.locationId;
  }

  /// One village by id — for showing what an address already points at.
  Future<ManaVillage?> byId(String locationId) async {
    final rows =
        await _db.from('locations').select(_columns).eq('location_id', locationId).limit(1);
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list.isEmpty ? null : ManaVillage.fromRow(list.first);
  }

  /// Creates the village if this business is the first to use it, and returns
  /// it either way.
  ///
  /// An RPC rather than an insert from Dart: it writes and reads across a
  /// uniqueness check, which is precisely the multi-step write the project's
  /// rules reserve for Postgres.
  Future<ManaVillage> addIfMissing({
    required String pinCode,
    required String villageTownName,
    required String areaType,
    required String mandal,
    required String district,
    required String state,
  }) async {
    final rows = await _db.schema('app').rpc('add_location_if_missing', params: {
      'p_pin_code': pinCode.trim(),
      'p_village_town_name': villageTownName.trim(),
      'p_area_type': areaType,
      'p_mandal': mandal.trim(),
      'p_district': district.trim(),
      'p_state': state.trim(),
    });
    return ManaVillage.fromRow(
        (rows as List).first as Map<String, dynamic>);
  }

  /// What the LGD reference knows about a PIN. Suggestions only: these have no
  /// `location_id` until someone actually picks one and [addIfMissing] writes
  /// it.
  Future<List<Map<String, dynamic>>> suggestFromReference(String pinCode) async {
    final rows = await _db
        .schema('app')
        .rpc('suggest_villages', params: {'p_pincode': pinCode.trim()});
    return (rows as List? ?? const []).cast<Map<String, dynamic>>();
  }
}

final locationApiServiceProvider = Provider<LocationApiService>(
  (ref) => LocationApiService(Supabase.instance.client),
);

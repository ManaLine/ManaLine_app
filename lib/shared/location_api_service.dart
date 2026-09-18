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

  /// Every district the directory lists this village under, when there is
  /// more than one. Empty for a village already in use, which has an answer.
  ///
  /// WHY A VILLAGE HAS TWO DISTRICTS. Andhra Pradesh split its districts in
  /// 2022 and `lgd_villages` carries both the old and the new name -- 56,163
  /// villages are listed twice this way, Srikalahasti mandal among them.
  ///
  /// The app used to resolve that silently, and always wrongly in the same
  /// direction: app.suggest_villages orders by district A to Z and the merge
  /// loop below kept the first row it saw, so every village in Srikalahasti
  /// was stored as CHITTOOR -- the pre-split answer -- while the mandal has
  /// been in Tirupati since 2022. Nothing said so and nothing could have.
  ///
  /// The Owner, on item 11: "enable user to select mandal, district ... which
  /// is correct if app fills it wrong or old data". Carrying the options this
  /// far is what lets the question be asked instead of answered by sort order.
  final List<String> districtOptions;

  const ManaVillage({
    required this.locationId,
    required this.name,
    required this.pinCode,
    required this.mandal,
    required this.district,
    required this.state,
    this.districtOptions = const [],
  });

  /// True when the directory cannot say which district this is in.
  bool get districtIsAmbiguous => districtOptions.length > 1;

  ManaVillage withDistrict(String d) => ManaVillage(
        locationId: locationId,
        name: name,
        pinCode: pinCode,
        mandal: mandal,
        district: d,
        state: state,
        districtOptions: districtOptions,
      );

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

/// One mandal / district / state a PIN can mean, and how many villages it
/// carries there — the count is what orders the choices.
class ManaPinOption {
  final String mandal;
  final String district;
  final String state;
  final int villages;

  const ManaPinOption({
    required this.mandal,
    required this.district,
    required this.state,
    required this.villages,
  });

  String get label => [mandal, district].where((s) => s.isNotEmpty).join(' · ');
}

/// A village close enough to what somebody typed to be worth asking about.
class ManaSimilarVillage {
  final ManaVillage village;

  /// True when this is a `locations` row some business already works in, so
  /// picking it reuses a real id rather than creating a second place.
  final bool inUse;
  final double score;

  const ManaSimilarVillage({
    required this.village,
    required this.inUse,
    required this.score,
  });
}

/// One person a business knows, as the village list shows them.
///
/// Deliberately thinner than CustomerSummary: this list exists to be scanned
/// and tapped, so it carries the four things that tell two people called
/// Lakshmi apart -- the name, who they are the daughter or wife of, the
/// mobile, and the MLID -- and nothing that would need a second query.
class ManaVillagePerson {
  final int personId;
  final String mlid;
  final String fullName;
  final String careOf;
  final String mobile;

  /// Every role they hold in this business. A person can be a Customer and an
  /// Agent at once; showing one of the two sends the Owner to the wrong screen.
  final Set<String> roles;

  const ManaVillagePerson({
    required this.personId,
    required this.mlid,
    required this.fullName,
    required this.careOf,
    required this.mobile,
    required this.roles,
  });

  /// Does this person match what has been typed?
  ///
  /// Matched in the app, not the database: the village's people are already
  /// in hand, and a round trip per keystroke inside a list of seventeen is
  /// slower than the list itself.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        careOf.toLowerCase().contains(q) ||
        mobile.contains(q) ||
        mlid.toLowerCase().contains(q);
  }
}

class LocationApiService {
  final SupabaseClient _db;
  LocationApiService(this._db);

  /// Every column any caller needed, so no screen has to re-derive the list
  /// and none of them can quietly drift apart again.
  static const _columns =
      'location_id, village_town_name, pin_code, mandal, district, state';

  /// The columns `lgd_villages` itself carries — a different shape from
  /// `locations` (`village`/`pincode`, no `location_id`), because it is the
  /// read-only LGD reference, never the app's own table.
  static const _lgdColumns = 'village, mandal, district, state, pincode';

  /// The fewest letters of a village name [searchByPin] will search on. A PIN
  /// alone can carry fifty villages; that is the directory, not a shortlist.
  /// [searchVillages] reuses this — one number, not a second one that could
  /// drift from it (see `village_search_rule_test.dart`).
  static const minVillageLetters = 3;

  /// `states()` result, kept for the life of this service instance. A
  /// government list of Indian states does not change mid-session, and
  /// `select distinct state` with no filter measures 244 ms — it cannot use
  /// the `(state, district)` index without a filter, so it walks the whole
  /// 767,191-row table. Paying that once per app run is fine; paying it every
  /// time the cascade opens is not. `locationApiServiceProvider` hands out one
  /// instance for the app's lifetime, so this cache lives exactly as long as
  /// the 35 states it holds are true.
  List<String>? _statesCache;

  ManaVillage _fromLgdRow(Map<String, dynamic> r) => ManaVillage(
        // A directory row, not a `locations` row: no id until [resolveId]
        // materialises it, same as the reference half of [searchByPin].
        locationId: '',
        name: (r['village'] as String?)?.trim() ?? '',
        pinCode: (r['pincode'] as String?)?.trim() ?? '',
        mandal: (r['mandal'] as String?)?.trim() ?? '',
        district: (r['district'] as String?)?.trim() ?? '',
        state: (r['state'] as String?)?.trim() ?? '',
      );

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

    // EVERY DISTRICT THE REFERENCE OFFERS, not whichever came back first.
    //
    // This loop used to `continue` on a name it had already seen, which threw
    // away the second row -- and the second row is the other district. Since
    // suggest_villages orders by district A to Z, the one kept was always the
    // alphabetically first, which for Srikalahasti is Chittoor: the district
    // the mandal left in 2022.
    final byName = <String, ManaVillage>{};
    final districtsByName = <String, Set<String>>{};
    for (final r in reference) {
      final name = ((r['village'] as String?) ?? '').trim();
      if (name.isEmpty) continue;
      if (lowerNeedle.isNotEmpty && !name.toLowerCase().contains(lowerNeedle)) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      final district = ((r['district'] as String?) ?? '').trim();
      if (district.isNotEmpty) {
        (districtsByName[key] ??= <String>{}).add(district);
      }
      byName.putIfAbsent(
        key,
        () => ManaVillage(
          locationId: '', // suggestion — see resolveId
          name: name,
          pinCode: pin,
          mandal: ((r['mandal'] as String?) ?? '').trim(),
          district: district,
          state: ((r['state'] as String?) ?? '').trim(),
        ),
      );
    }
    for (final entry in byName.entries) {
      if (results.length >= limit) break;
      final options = (districtsByName[entry.key] ?? const <String>{}).toList()
        ..sort();
      results.add(ManaVillage(
        locationId: entry.value.locationId,
        name: entry.value.name,
        pinCode: entry.value.pinCode,
        mandal: entry.value.mandal,
        district: entry.value.district,
        state: entry.value.state,
        // Only when there is a real choice. One district is an answer, not an
        // option, and a screen that asked anyway would be asking 93% of the
        // time for nothing.
        districtOptions: options.length > 1 ? options : const [],
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
  /// The villages THIS business actually works, with their ids.
  ///
  /// BulkOnboardingService.operatingVillages already read these and formatted
  /// them as display strings -- "Uranduru (517640)" -- which is right for a
  /// spreadsheet dropdown and useless to a form that needs a location_id.
  /// Parsing that string back into data is how a spelling variant quietly
  /// becomes a different village, so this returns the rows instead.
  ///
  /// WHY A FORM WANTS THEM. A book works a dozen villages out of a national
  /// register of 768,529, and the customer being added almost always lives in
  /// one of them. Offering those twelve first turns a search into a tap, and
  /// it is also what makes the check in item 6 possible: a business with none
  /// of these cannot have a customer added to it yet, and saying so beats
  /// letting somebody fill a form that has nowhere to put an address.
  Future<List<ManaVillage>> businessVillages(String businessId) async {
    final rows = await _db
        .from('operating_area_locations')
        .select(
            'locations!inner(location_id, village_town_name, pin_code, mandal, district, state)')
        .eq('business_id', businessId)
        .isFilter('removed_at', null);
    final byId = <String, ManaVillage>{};
    for (final r in rows as List) {
      final l = (r as Map<String, dynamic>)['locations'] as Map<String, dynamic>?;
      if (l == null) continue;
      final v = ManaVillage.fromRow(l);
      if (v.locationId.isEmpty || v.name.isEmpty) continue;
      // Distinct by id: one village can sit in more than one operating area.
      byId[v.locationId] = v;
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Who this business knows who lives in [villageId].
  ///
  /// The Owner, 2026-09-18: "Global search - while searching a user - select
  /// village first - then search becomes easy and findable when the user
  /// count goes up."
  ///
  /// A name search across a whole book returns everyone called Lakshmi. A
  /// name search inside one village returns the one the Owner means, and with
  /// twelve villages that is a twelvefold cut for a single tap. It also
  /// answers the empty query: pick a village and you get its people without
  /// typing anything, which is the state an Owner is usually in.
  ///
  /// TWO QUERIES, NOT ONE NESTED FILTER. Going
  /// person_addresses -> persons -> business_members in a single select means
  /// filtering on a doubly-nested embed, and the `business_members` -> `persons`
  /// pair is one of the eleven that must name its foreign key or PostgREST
  /// answers 300. Two plain round trips are legible and cannot be got wrong
  /// quietly; the first returns at most a village's worth of ids.
  Future<List<ManaVillagePerson>> peopleInVillage({
    required String businessId,
    required String villageId,
  }) async {
    final addresses = await _db
        .from('person_addresses')
        .select('person_id')
        .eq('village_id', villageId)
        .eq('is_current', true);
    final ids = [
      for (final r in addresses as List)
        (r as Map<String, dynamic>)['person_id'] as int,
    ];
    if (ids.isEmpty) return const [];

    // business_members -> persons has TWO foreign keys, person_id and
    // invited_by_person_id, so this one is named or the query dies with
    // PGRST201 and the screen just says it could not load.
    final rows = await _db
        .from('business_members')
        .select('role, membership_status, '
            'persons!business_members_person_id_fkey('
            'person_id, mlid, full_name, father_husband_name, mobile_number)')
        .eq('business_id', businessId)
        .eq('membership_status', 'Active')
        .inFilter('person_id', ids);

    // One person can hold two roles in the same business -- the UNIQUE is on
    // (person_id, business_id, role) -- so they arrive twice and are folded
    // into one entry carrying both.
    final byPerson = <int, ManaVillagePerson>{};
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final person = m['persons'] as Map<String, dynamic>?;
      if (person == null) continue;
      final id = (person['person_id'] as num).toInt();
      final role = (m['role'] ?? '').toString();
      final existing = byPerson[id];
      byPerson[id] = ManaVillagePerson(
        personId: id,
        mlid: (person['mlid'] ?? '').toString(),
        fullName: (person['full_name'] ?? '').toString(),
        careOf: (person['father_husband_name'] ?? '').toString(),
        mobile: (person['mobile_number'] ?? '').toString(),
        roles: {...?existing?.roles, if (role.isNotEmpty) role},
      );
    }
    final list = byPerson.values.toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return list;
  }

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
      // This path only ever materialises a village the reference already knew.
      source: 'Directory',
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
  ///
  /// [source] records WHERE the village came from — 'Directory' when a
  /// reference suggestion is being materialised, 'Owner Entered' when somebody
  /// typed a village the directory has never heard of. Defaulted, so the six
  /// existing callers are unchanged and get the answer that shows up for review
  /// rather than the one that hides.
  Future<ManaVillage> addIfMissing({
    required String pinCode,
    required String villageTownName,
    required String areaType,
    required String mandal,
    required String district,
    required String state,
    String source = 'Owner Entered',
  }) async {
    final rows = await _db.schema('app').rpc('add_location_if_missing', params: {
      'p_pin_code': pinCode.trim(),
      'p_village_town_name': villageTownName.trim(),
      'p_area_type': areaType,
      'p_mandal': mandal.trim(),
      'p_district': district.trim(),
      'p_state': state.trim(),
      'p_source': source,
    });
    return ManaVillage.fromRow(
        (rows as List).first as Map<String, dynamic>);
  }

  /// The mandal / district / state combinations a PIN can mean.
  ///
  /// The Add New Village form used to ask for all three as free text, which is
  /// how a village came to record its state as "Andhrapradesh" and then narrow
  /// every picker to nothing. The PIN already answers it: 99.8% of pincodes
  /// resolve to one state, 97.8% to at most two districts, 85% to at most three
  /// mandals. Ordered most-villages-first, so the likelier answer leads.
  ///
  /// Empty for a PIN the directory does not carry at all — a genuinely new
  /// postal area, where there is nothing to offer and free text is the only
  /// honest option.
  Future<List<ManaPinOption>> pinOptions(String pinCode) async {
    if (pinCode.trim().length != 6) return const [];
    final rows = await _db
        .schema('app')
        .rpc('pin_administrative_options', params: {'p_pincode': pinCode.trim()});
    return [
      for (final r in (rows as List? ?? const []).cast<Map<String, dynamic>>())
        ManaPinOption(
          mandal: (r['mandal'] as String?) ?? '',
          district: (r['district'] as String?) ?? '',
          state: (r['state'] as String?) ?? '',
          villages: (r['villages'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// Villages at this PIN whose names are CLOSE to what somebody has typed.
  ///
  /// Before creating a village, ask whether they meant one that already exists.
  /// add_location_if_missing dedupes on an exact name, so two spellings of one
  /// place become two locations and the customers split between them.
  ///
  /// Trigram similarity at 0.4, a threshold measured rather than picked --
  /// ichapuram/Ichchapuram scores 0.83 and is the same town (confirmed by the
  /// Owner: the railway station carries the second spelling), while
  /// Dommarametta/Dommara Pochampally scores 0.27 and is not.
  Future<List<ManaSimilarVillage>> similarVillages({
    required String pinCode,
    required String name,
  }) async {
    if (pinCode.trim().length != 6 || name.trim().length < minVillageLetters) {
      return const [];
    }
    final rows = await _db.schema('app').rpc('suggest_similar_villages',
        params: {'p_pincode': pinCode.trim(), 'p_name': name.trim()});
    return [
      for (final r in (rows as List? ?? const []).cast<Map<String, dynamic>>())
        ManaSimilarVillage(
          village: ManaVillage(
            locationId: (r['location_id'] as String?) ?? '',
            name: (r['village'] as String?) ?? '',
            pinCode: pinCode.trim(),
            mandal: (r['mandal'] as String?) ?? '',
            district: (r['district'] as String?) ?? '',
            state: (r['state'] as String?) ?? '',
          ),
          inUse: (r['in_use'] as bool?) ?? false,
          score: (r['score'] as num?)?.toDouble() ?? 0,
        ),
    ];
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

  /// Every state the LGD reference carries — the second way into an address,
  /// for a person who does not know their PIN. PIN entry stays the default;
  /// this is the cascade beside it (state -> district -> >=3 letters).
  ///
  /// PostgREST has no DISTINCT on a plain table select, so this calls
  /// `app.lgd_states()`, which runs the DISTINCT in SQL and returns 35 rows
  /// instead of 767,191. See [_statesCache] for why the result is kept
  /// in memory rather than re-fetched.
  Future<List<String>> states() async {
    final cached = _statesCache;
    if (cached != null) return cached;
    final rows = await _db.schema('app').rpc('lgd_states');
    final list = [
      for (final r in (rows as List? ?? const []).cast<Map<String, dynamic>>())
        ((r['state'] as String?) ?? '').trim(),
    ]..removeWhere((s) => s.isEmpty);
    _statesCache = list;
    return list;
  }

  /// Districts the LGD reference lists under [state], alphabetical.
  ///
  /// Not cached, unlike [states]: `select distinct district where state = ?`
  /// measures 8 ms because the `(state, district)` index already serves it —
  /// there is no 244 ms problem here to solve, and caching per state would
  /// add bookkeeping (which state's list is stale, when to evict) for a
  /// saving too small to matter.
  Future<List<String>> districtsIn(String state) async {
    final s = state.trim();
    if (s.isEmpty) return const [];
    final rows =
        await _db.schema('app').rpc('lgd_districts', params: {'p_state': s});
    return [
      for (final r in (rows as List? ?? const []).cast<Map<String, dynamic>>())
        ((r['district'] as String?) ?? '').trim(),
    ]..removeWhere((d) => d.isEmpty);
  }

  /// Villages in [district] of [state] whose names start with [query] —
  /// falling back to a substring match only when the prefix search finds
  /// nothing.
  ///
  /// PREFIX FIRST, DELIBERATELY. Measured in Visakhapatnam (3,275 villages):
  /// a prefix search for `pal` returns 14 rows; a substring search for the
  /// same three letters returns 500. The owner decided this list carries no
  /// cap, and that decision is only safe because prefix keeps it short — 500
  /// rows on a cheap phone is not a list, it is a wall. Do not "simplify"
  /// this into one substring query: that is the wall coming back.
  ///
  /// The substring fallback exists because LGD spellings diverge mid-word —
  /// *Ichapuram* and *Ichchapuram* are one place — and it fires rarely,
  /// because a prefix of `ich` already catches both.
  ///
  /// Fewer than [minVillageLetters] letters issues no query at all, same rule
  /// as [searchByPin].
  Future<List<ManaVillage>> searchVillages({
    required String state,
    required String district,
    required String query,
  }) async {
    final needle = query.trim();
    if (needle.length < minVillageLetters) return const [];
    final st = state.trim();
    final di = district.trim();
    if (st.isEmpty || di.isEmpty) return const [];

    final prefixRows = await _db
        .from('lgd_villages')
        .select(_lgdColumns)
        .eq('state', st)
        .eq('district', di)
        .ilike('village', '$needle%')
        .order('village', ascending: true);
    final prefixResults = [
      for (final r in (prefixRows as List).cast<Map<String, dynamic>>())
        _fromLgdRow(r),
    ];
    if (prefixResults.isNotEmpty) return prefixResults;

    // Only reached when the prefix search found nothing — see the doc
    // comment above for why this must stay a fallback, not a default.
    final substringRows = await _db
        .from('lgd_villages')
        .select(_lgdColumns)
        .eq('state', st)
        .eq('district', di)
        .ilike('village', '%$needle%')
        .order('village', ascending: true);
    return [
      for (final r in (substringRows as List).cast<Map<String, dynamic>>())
        _fromLgdRow(r),
    ];
  }
}

final locationApiServiceProvider = Provider<LocationApiService>(
  (ref) => LocationApiService(Supabase.instance.client),
);

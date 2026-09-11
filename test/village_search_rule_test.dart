import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/business_management_state.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:mana_line/shared/widgets/village_picker_field.dart';

/// PIN plus at least three letters of the village name, sorted A to Z.
///
/// WHY THE RULE EXISTS: a PIN on its own is not a shortlist. 517536 carries
/// fifty villages (Srikalahasti and Thottambedu mandals, across the Chittoor
/// and Tirupati district split) and 524129 twenty-four, and answering a six-digit PIN with
/// the whole directory makes the Owner scroll for a name they already know.
///
/// WHY THIS TEST EXISTS: the rule lives in three places — the operating-area
/// search, the shared LocationApiService, and the setup wizard's own inline
/// search. Three copies of one number is exactly the drift this repo keeps
/// meeting, and two of them agreeing while the third quietly uses 2 would be
/// invisible on screen: the odd one out would simply search sooner.
///
/// The wizard's copy is a private constant on a State class and cannot be
/// reached from here. It is checked by reading it — `_minVillageLetters` in
/// ow_000_first_business_setup.dart — and the comment there says so.
void main() {
  test('the threshold is the same wherever it is enforced', () {
    expect(BusinessManagementApiService.minVillageLetters, 3);
    expect(LocationApiService.minVillageLetters, 3);
    expect(
      BusinessManagementApiService.minVillageLetters,
      LocationApiService.minVillageLetters,
      reason: 'One picker would start searching before the others, for the '
          'same typing. Keep them equal or give each a written reason.',
    );
  });

  group('needsVillageName tells the two silences apart', () {
    // "Nothing searched yet" and "searched, found nothing" must not share a
    // message. Conflating them is how "No villages found for that PIN" came to
    // be shown for a PIN with fifty villages behind it.
    test('a complete PIN with no name is asking for the name', () {
      const s = OperatingAreaSearchState(pinCode: '517536');
      expect(s.needsVillageName, isTrue);
    });

    test('a complete PIN with too few letters is still asking', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'do');
      expect(s.needsVillageName, isTrue);
    });

    test('three letters is enough to have searched', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'dom');
      expect(s.needsVillageName, isFalse);
    });

    test('whitespace is not a letter', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'd  ');
      expect(s.needsVillageName, isTrue,
          reason: 'Trimmed length decides, or two spaces would trigger a '
              'search for one letter.');
    });

    test('an incomplete PIN is not asking for a village name yet', () {
      // The prompt would be premature: the PIN field is still being typed, and
      // a screen nagging for a village before it has a PIN reads as broken.
      const s = OperatingAreaSearchState(pinCode: '5175', villageQuery: '');
      expect(s.needsVillageName, isFalse);
    });
  });

  group('a composed address reads like an address', () {
    // A REAL row, read out of lgd_villages. The fixture used to say
    // "Dommarametta, Renigunta" — a village the directory does not carry,
    // under a mandal that is not 517536's. A plausible-looking invention in a
    // test fixture is worse than an obviously fake one: it reads as verified.
    const v = ManaVillage(
      locationId: '',
      name: 'Akkurthy',
      pinCode: '517536',
      mandal: 'Srikalahasti',
      district: 'Tirupati',
      state: 'Andhra Pradesh',
    );

    test('door number first, PIN last', () {
      expect(
        manaComposeAddress(doorNo: 'D.No 12', village: v),
        'D.No 12, Akkurthy, Srikalahasti, Tirupati, Andhra Pradesh - 517536',
      );
    });

    test('no door number leaves no stray comma', () {
      // A business with no door number must not have an address that starts
      // with a separator.
      expect(
        manaComposeAddress(village: v),
        'Akkurthy, Srikalahasti, Tirupati, Andhra Pradesh - 517536',
      );
      expect(manaComposeAddress(doorNo: '   ', village: v),
          startsWith('Akkurthy'));
    });

    test('a village the reference knows only by name still composes', () {
      // The directory is incomplete in places — mandal or district can be
      // blank, and the result must not carry ", ," through it.
      const bare = ManaVillage(
        locationId: '',
        name: 'Punabaka',
        pinCode: '524129',
        mandal: '',
        district: '',
        state: 'Andhra Pradesh',
      );
      expect(manaComposeAddress(village: bare),
          'Punabaka, Andhra Pradesh - 524129');
    });

    test('no PIN means no trailing dash', () {
      const noPin = ManaVillage(
        locationId: '',
        name: 'Somewhere',
        pinCode: '',
        mandal: '',
        district: '',
        state: '',
      );
      expect(manaComposeAddress(village: noPin), 'Somewhere');
    });
  });

  // Two search rules coexist now: PIN + 3 letters (above, unchanged) and the
  // cascade added in Plan 4 — state -> district -> 3 letters, prefix before
  // substring. searchVillages has no test seam (it talks straight to
  // Supabase, and this file has no harness to fake that client), so these
  // read the guard conditions out of LocationApiService.searchVillages the
  // same way village_lookup_guard_test.dart reads its own target: by source
  // text. That is weaker than exercising the method, and worth saying so —
  // it proves the guard is present in the code, not that it behaves right at
  // runtime.
  group('the cascade rule: state, district and 3 letters, prefix first', () {
    late final String source;
    late final String body;

    setUpAll(() {
      source = File('lib/shared/location_api_service.dart').readAsStringSync();
      final start = source.indexOf('Future<List<ManaVillage>> searchVillages');
      expect(start, greaterThan(-1),
          reason: 'searchVillages moved or was renamed; this guard reads it '
              'by source text and needs updating alongside it.');
      // Up to the next top-level method, `Future<ManaPinOption` say — good
      // enough to bound one method body without a real parser.
      final next = source.indexOf('\n  Future<', start + 10);
      body = source.substring(start, next == -1 ? source.length : next);
    });

    test('the cascade shares the PIN path\'s letter threshold', () {
      // One constant, not two copies that could disagree — searchVillages
      // and searchByPin both gate on LocationApiService.minVillageLetters.
      expect(LocationApiService.minVillageLetters, 3);
      expect(body, contains('needle.length < minVillageLetters'),
          reason: 'searchVillages must gate on the shared constant, not a '
              'new literal that could drift from it.');
    });

    test('state and district are both required before any query runs', () {
      expect(body, contains('st.isEmpty || di.isEmpty'),
          reason: 'Without this, a cascade missing a district (or a state) '
              'would search every village on earth instead of returning '
              'nothing — the wall the PIN path already refuses to become.');
    });

    test('the prefix search runs, and is checked, before the substring one', () {
      final prefixAt = body.indexOf("ilike('village', '\$needle%')");
      final substringAt = body.indexOf("ilike('village', '%\$needle%')");
      expect(prefixAt, greaterThan(-1),
          reason: 'No prefix query found — searchVillages must try `needle%` '
              'first (14 rows in Visakhapatnam) before ever trying `%needle%` '
              '(500 rows): see the doc comment on searchVillages.');
      expect(substringAt, greaterThan(-1),
          reason: 'No substring fallback found — Ichapuram/Ichchapuram-style '
              'mid-word spelling drift needs one.');
      expect(prefixAt, lessThan(substringAt),
          reason: 'The substring query must be reachable only after the '
              'prefix query returns nothing, not run alongside or before it.');
      expect(body.indexOf('prefixResults.isNotEmpty) return prefixResults'),
          allOf(greaterThan(prefixAt), lessThan(substringAt)),
          reason: 'A non-empty prefix result must return before the '
              'substring query is ever issued — "fallback" means it does '
              'not run when the first search already found something.');
    });
  });
}

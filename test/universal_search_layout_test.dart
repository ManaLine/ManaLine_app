import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// Universal Search used to be a bottom sheet: the field opened at the bottom
/// of the display under the keyboard, and the results grew downwards out of a
/// plain non-scrolling Column, so a name matching twenty people ran off the
/// screen rather than scrolling.
///
/// It is a pushed screen now, with the field pinned in the app bar. These pin
/// the part that was wrong — the field is at the top and the body scrolls —
/// plus the usual scale sweep, because a hint string in an AppBar.bottom of
/// fixed height is this app's recurring overflow shape.
const _searchTelugu = <String, Map<String, String>>{
  'search': {'English': 'Search', 'Telugu': 'వెతకండి'},
  'search_by_phone_mlid_aadhaar_name': {
    'English': 'Search by Phone, MANA LINE ID, Aadhaar, or Name.',
    'Telugu': 'ఫోన్, మానా లైన్ ఐడీ, ఆధార్ లేదా పేరుతో వెతకండి.',
  },
  'no_identity_found': {
    'English': 'No identity found.',
    'Telugu': 'గుర్తింపు కనుగొనబడలేదు.',
  },
  'not_a_member_of_business': {
    'English': 'Not a member of this business.',
    'Telugu': 'ఈ వ్యాపారంలో సభ్యులు కాదు.',
  },
};

/// The screen asks which villages this book works the moment it opens, so
/// every case here needs this -- the harness rule is that a screen loading in
/// initState gets its provider seeded rather than being allowed to reach the
/// network, and without it the test measures an empty screen and proves
/// nothing.
///
/// THREE VILLAGES, and one of them with a long Telugu name, because the
/// village dropdown is a new full-width control in a column that already
/// overflowed once. A one-village fixture would not measure the wrap.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path.contains('operating_area_locations')
        ? [
            for (final v in const [
              ['loc-1', 'Panagallu (Rural)', '517640'],
              ['loc-2', 'శ్రీకాళహస్తి గ్రామం', '517644'],
              ['loc-3', 'Uranduru', '517640'],
            ])
              {
                'locations': {
                  'location_id': v[0],
                  'village_town_name': v[1],
                  'pin_code': v[2],
                  'mandal': 'Srikalahasti',
                  'district': 'Chittoor',
                  'state': 'Andhra Pradesh',
                }
              }
          ]
        : const [];
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

List<Override> _seeded() => [
      locationApiServiceProvider.overrideWithValue(
        LocationApiService(SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          httpClient: _FakeClient(),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        )),
      ),
    ];

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Universal Search survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded(),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Universal Search at ${scale}x');
    });

    testWidgets('Universal Search survives text scale ${scale}x in Telugu',
        (tester) async {
      await pumpManaScreen(
        tester,
        const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _searchTelugu,
      );
      expectNoLayoutFault(tester, 'Universal Search at ${scale}x in Telugu');
    });
  }

  testWidgets('the field is above the results area', (tester) async {
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded());

    final field = tester.getRect(find.byType(TextField));
    final body = tester.getRect(find.byType(Scaffold));

    // The whole point of the change: the thing you type into is near the top
    // of the screen, not sitting at the bottom under the keyboard.
    expect(field.top, lessThan(body.height / 2),
        reason: 'the search field must sit in the top half of the screen');
  });

  testWidgets('before searching it prompts rather than claiming no match',
      (tester) async {
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded());

    // Saying "no identity found" to someone who has not typed anything yet
    // reads as a broken search.
    expect(find.text('No identity found.'), findsNothing);
  });

  testWidgets('the villages this book works are offered before anything is '
      'typed', (tester) async {
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded());
    await tester.pumpAndSettle();

    // The Owner: "while searching a user - select village first - then search
    // becomes easy and findable when the user count goes up." The point is
    // that it is offered WITHOUT typing -- a filter you have to discover by
    // typing first is not a filter that reduces anything.
    expect(find.text('Search Within a Village'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<ManaVillage>), findsOneWidget);
  });

  testWidgets('a village dropdown of long Telugu names does not overflow',
      (tester) async {
    // The dropdown is a new full-width control in a column that has
    // overflowed before, and Telugu is the language that widens.
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'),
        overrides: _seeded(),
        textScale: 2.0,
        language: ManaLanguage.telugu,
        translations: _searchTelugu);
    await tester.pumpAndSettle();
    expectNoLayoutFault(tester, 'village dropdown at 2.0x in Telugu');
  });
}

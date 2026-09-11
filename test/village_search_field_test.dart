// Tests for ManaVillageSearchField (Plan 4 Task 3): the two-mode picker that
// sits beside the existing PIN field — PIN by default, State -> District ->
// name cascade on request.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/village_search_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// Same fake-http-client technique as location_api_service_test.dart: there
/// is no mocking package in this repo, and `SupabaseClient(url, key,
/// httpClient: ...)` is a real public constructor parameter, not a
/// workaround. This is the "seed the service" the brief asks for — an
/// unseeded field would reach the network on first frame and prove nothing.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._responder);

  final List<Uri> requests = [];
  final List<Map<String, dynamic>> Function(Uri url) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final body = utf8.encode(jsonEncode(_responder(request.url)));
    return http.StreamedResponse(
      Stream.value(body),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

const _statesRows = [
  {'state': 'Andhra Pradesh'},
  {'state': 'Telangana'},
];

const _districtsRows = [
  {'district': 'Visakhapatnam'},
  {'district': 'Srikakulam'},
];

/// One village, 'Palasa', found by either a prefix or substring search on
/// 'pal' — enough to exercise pick/unpick without needing the full
/// prefix-vs-substring fallback (that behaviour already has its own
/// coverage in location_api_service_test.dart).
List<Map<String, dynamic>> _defaultResponder(Uri url) {
  if (url.path.endsWith('/rpc/lgd_states')) return _statesRows;
  if (url.path.endsWith('/rpc/lgd_districts')) return _districtsRows;
  if (url.path.endsWith('/lgd_villages')) {
    final needle = (url.queryParameters['village'] ?? '').toLowerCase();
    if (needle.contains('pal')) {
      return const [
        {
          'village': 'Palasa',
          'mandal': 'Palasa',
          'district': 'Visakhapatnam',
          'state': 'Andhra Pradesh',
          'pincode': '532221',
        },
      ];
    }
    return const [];
  }
  return const [];
}

/// Same idea as [_FakeClient], but the responder is async so a test can hold
/// a response open (via a [Completer]) and release two overlapping requests
/// in a chosen order — the only way to exercise DEFECT 1 (a slow response
/// overwriting a newer one), since a synchronous fake always answers in
/// request order.
class _DelayedClient extends http.BaseClient {
  _DelayedClient(this._responder);

  final Future<List<Map<String, dynamic>>> Function(Uri url) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = await _responder(request.url);
    final body = utf8.encode(jsonEncode(rows));
    return http.StreamedResponse(
      Stream.value(body),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

LocationApiService _delayedService(
  Future<List<Map<String, dynamic>>> Function(Uri url) responder,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: _DelayedClient(responder),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return LocationApiService(client);
}

({LocationApiService service, List<Uri> requests}) _serviceWith(
  List<Map<String, dynamic>> Function(Uri url) responder,
) {
  final fake = _FakeClient(responder);
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: fake,
    // Widget tests fail on a pending timer at teardown; GoTrue's own
    // auto-refresh timer has nothing to do with what this widget exercises,
    // so it is switched off rather than worked around per test.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return (service: LocationApiService(client), requests: fake.requests);
}

Widget _hosted(
  LocationApiService service,
  ValueChanged<ManaVillage?> onPicked, {
  String? initialPin,
}) {
  return UncontrolledProviderScope(
    container: ProviderContainer(overrides: [
      locationApiServiceProvider.overrideWithValue(service),
      translationCacheProvider.overrideWithValue(FakeTranslationCache()),
      // ref.t() reads authFlowProvider for the current language; the real
      // notifier's build() reads ManaSession from secure storage, which
      // needs seeding (see setUp below) even for a plain default state.
      authFlowProvider
          .overrideWith(() => SeededAuthFlowNotifier(const AuthFlowState())),
    ]),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ManaVillageSearchField(onPicked: onPicked, initialPin: initialPin),
        ),
      ),
    ),
  );
}

Future<void> openCascade(WidgetTester tester) async {
  await tester.tap(find.text('village_search_by_state_district'));
  await tester.pumpAndSettle();
  expect(find.text('village_search_by_state_district'), findsOneWidget,
      reason: 'the segment tap must land — the cascade segments only exist '
          'once the widget itself has built');
}

Future<void> pickState(WidgetTester tester, String state) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).first,
      warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.text(state).last, warnIfMissed: false);
  await tester.pumpAndSettle();
  // Confirms the second tap actually landed on the overlay menu item rather
  // than missing silently: the district field only renders once a state is
  // chosen, so its absence would mean the pick never happened.
  expect(find.text('District *'), findsOneWidget);
}

Future<void> pickDistrict(WidgetTester tester, String district) async {
  final districtField = find.byType(DropdownButtonFormField<String>).last;
  await tester.tap(districtField, warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.text(district).last, warnIfMissed: false);
  await tester.pumpAndSettle();
  // Same reasoning as pickState: the village name field only renders once a
  // district is chosen.
  expect(find.byType(TextField), findsOneWidget);
}

void main() {
  setUp(() => seedSecureStorage());

  group('ManaVillageSearchField: mode', () {
    testWidgets('defaults to PIN on open', (tester) async {
      final built = _serviceWith(_defaultResponder);
      await tester.pumpWidget(_hosted(built.service, (_) {}));
      await tester.pumpAndSettle();

      // The PIN field is the reused ManaVillagePickerField — its own PIN
      // input carries this label.
      expect(find.text('PIN Code'), findsOneWidget);
      // The cascade's State field must not be showing yet.
      expect(find.text('State *'), findsNothing);
    });

    testWidgets('switching to cascade clears the PIN pick and emits null',
        (tester) async {
      final built = _serviceWith((url) {
        if (url.path.endsWith('/locations')) {
          return const [
            {
              'location_id': 'loc-1',
              'village_town_name': 'Palasa',
              'pin_code': '532221',
              'mandal': 'Palasa',
              'district': 'Srikakulam',
              'state': 'Andhra Pradesh',
            },
          ];
        }
        return _defaultResponder(url);
      });

      ManaVillage? last;
      var callCount = 0;
      await tester.pumpWidget(_hosted(built.service, (v) {
        last = v;
        callCount++;
      }));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '532221');
      await tester.enterText(find.byType(TextField).at(1), 'pal');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Palasa').first);
      await tester.pumpAndSettle();
      expect(last?.name, 'Palasa', reason: 'the PIN-mode pick must reach onPicked');

      // Flip to the cascade segment.
      await tester.tap(find.text('village_search_by_state_district'));
      await tester.pumpAndSettle();

      expect(last, isNull,
          reason: 'switching modes must clear a half-finished/finished pick');
      expect(callCount, greaterThanOrEqualTo(2));
      // The PIN field must have come back empty (re-keyed), not carry the
      // old pick if the person switches back.
      await tester.tap(find.text('village_search_by_pin'));
      await tester.pumpAndSettle();
      final pinField = tester.widget<TextField>(find.byType(TextField).first);
      expect(pinField.controller?.text ?? '', isEmpty);
    });
  });

  group('ManaVillageSearchField: initialPin', () {
    testWidgets('prefills the PIN box on open without picking or searching',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      ManaVillage? picked;
      var callCount = 0;

      await tester.pumpWidget(_hosted(
        built.service,
        (v) {
          picked = v;
          callCount++;
        },
        initialPin: '532221',
      ));
      await tester.pumpAndSettle();

      final pinField = tester.widget<TextField>(find.byType(TextField).first);
      expect(pinField.controller?.text, '532221',
          reason: 'the PIN box must start filled from initialPin');
      // A convenience for typing, not a pick: nothing has been searched (the
      // name box is still empty, so searchByPin's own guard never runs) and
      // onPicked must not have fired on its own.
      expect(built.requests, isEmpty,
          reason: 'prefilling the box must not fire a search on its own');
      expect(picked, isNull);
      expect(callCount, 0);
    });

    testWidgets('with no initialPin, the PIN box opens empty as before',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      await tester.pumpWidget(_hosted(built.service, (_) {}));
      await tester.pumpAndSettle();

      final pinField = tester.widget<TextField>(find.byType(TextField).first);
      expect(pinField.controller?.text ?? '', isEmpty);
    });
  });

  group('ManaVillageSearchField: cascade', () {
    testWidgets('fewer than 3 letters shows no results and issues no query',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      await tester.pumpWidget(_hosted(built.service, (_) {}));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');

      final beforeCount = built.requests.length;
      await tester.enterText(find.byType(TextField).last, 'pa');
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ListTile), findsNothing);
      expect(built.requests.length, beforeCount,
          reason: 'below minVillageLetters must not touch the network');
    });

    testWidgets('changing state clears district and village selection',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      ManaVillage? last;
      await tester.pumpWidget(_hosted(built.service, (v) => last = v));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');
      await tester.enterText(find.byType(TextField).last, 'pal');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Palasa'));
      await tester.pumpAndSettle();
      expect(last?.name, 'Palasa');

      // District field must have disappeared until a state is chosen? No —
      // re-picking the SAME state re-clears district/village regardless.
      await pickState(tester, 'Telangana');

      expect(last, isNull, reason: 'changing state must clear the pick');
      // District dropdown must be back to unset — the village field (which
      // only appears once a district is chosen) must be gone.
      expect(find.byType(TextField), findsNothing,
          reason: 'the village name field only shows once a district is '
              'chosen again; changing state must have cleared it');
    });

    testWidgets('picking a village emits it; editing afterwards emits null',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      ManaVillage? last;
      await tester.pumpWidget(_hosted(built.service, (v) => last = v));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');
      await tester.enterText(find.byType(TextField).last, 'pal');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Palasa'));
      await tester.pumpAndSettle();
      expect(last?.name, 'Palasa');
      expect(last?.pinCode, '532221');

      await tester.enterText(find.byType(TextField).last, 'pala');
      await tester.pump();
      expect(last, isNull,
          reason: 'editing the search after a pick must emit null immediately');
    });

    testWidgets('result row shows village, mandal, district, state and PIN',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      await tester.pumpWidget(_hosted(built.service, (_) {}));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');
      await tester.enterText(find.byType(TextField).last, 'pal');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Palasa · Visakhapatnam · Andhra Pradesh - 532221'),
          findsOneWidget);
    });
  });

  group('ManaVillageSearchField: stale search responses', () {
    testWidgets(
        'a slow response for an earlier query must not overwrite a later one',
        (tester) async {
      // 'pal' resolves to Palasa but is held open; 'palak' resolves to
      // Palakayatirevu and is released first. If the widget applied
      // responses in arrival order (the pre-fix behaviour) the list would
      // then flip back to Palasa when the held 'pal' response lands —
      // exactly the flicker DEFECT 1 describes.
      final palGate = Completer<void>();
      final palakGate = Completer<void>();
      final service = _delayedService((url) async {
        if (url.path.endsWith('/rpc/lgd_states')) return _statesRows;
        if (url.path.endsWith('/rpc/lgd_districts')) return _districtsRows;
        if (url.path.endsWith('/lgd_villages')) {
          final needle = (url.queryParameters['village'] ?? '').toLowerCase();
          if (needle.contains('palak')) {
            await palakGate.future;
            return const [
              {
                'village': 'Palakayatirevu',
                'mandal': 'Palakonda',
                'district': 'Visakhapatnam',
                'state': 'Andhra Pradesh',
                'pincode': '532440',
              },
            ];
          }
          if (needle.contains('pal')) {
            await palGate.future;
            return const [
              {
                'village': 'Palasa',
                'mandal': 'Palasa',
                'district': 'Visakhapatnam',
                'state': 'Andhra Pradesh',
                'pincode': '532221',
              },
            ];
          }
        }
        return const [];
      });

      await tester.pumpWidget(_hosted(service, (_) {}));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');

      // Types 'pal', lets the debounce fire and the (gated) request go out.
      await tester.enterText(find.byType(TextField).last, 'pal');
      await tester.pump(const Duration(milliseconds: 500));

      // Types past it to 'palak' before the first response ever lands —
      // its own debounced request also goes out and is gated separately.
      await tester.enterText(find.byType(TextField).last, 'palak');
      await tester.pump(const Duration(milliseconds: 500));

      // The later query's response arrives first...
      palakGate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Palakayatirevu'), findsOneWidget);

      // ...and then the earlier, slower one finally lands. A correct widget
      // drops it; the broken widget overwrites the list with it.
      palGate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Palakayatirevu'), findsOneWidget,
          reason: 'the later query\'s result must still be showing');
      expect(find.text('Palasa'), findsNothing,
          reason: 'the stale response for text already typed past must be '
              'dropped, not applied over the newer result');
    });
  });

  group('ManaVillageSearchField: add village (cascade)', () {
    List<Map<String, dynamic>> addFlowResponder(Uri url) {
      if (url.path.endsWith('/rpc/lgd_states')) return _statesRows;
      if (url.path.endsWith('/rpc/lgd_districts')) return _districtsRows;
      // The directory has never heard of this place — same as the real
      // Dommarametta example the review names.
      if (url.path.endsWith('/lgd_villages')) return const [];
      if (url.path.endsWith('/rpc/suggest_similar_villages')) return const [];
      if (url.path.endsWith('/rpc/add_location_if_missing')) {
        return const [
          {
            'location_id': 'loc-new-1',
            'village_town_name': 'Dommarametta',
            'pin_code': '532221',
            'mandal': 'Palasa Mandal',
            'district': 'Visakhapatnam',
            'state': 'Andhra Pradesh',
          },
        ];
      }
      return const [];
    }

    testWidgets('a search finding nothing offers the add-village path',
        (tester) async {
      final built = _serviceWith(addFlowResponder);
      await tester.pumpWidget(_hosted(built.service, (_) {}));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');

      await tester.enterText(find.byType(TextField).last, 'Dommarametta');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing,
          reason: 'the directory genuinely does not carry this village');
      expect(find.text('add_this_village'), findsOneWidget,
          reason: 'no match must not be a dead end — DEFECT 2');
    });

    testWidgets('a village returned from the sheet is emitted through onPicked',
        (tester) async {
      final built = _serviceWith(addFlowResponder);
      ManaVillage? last;
      await tester.pumpWidget(_hosted(built.service, (v) => last = v));
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');

      await tester.enterText(find.byType(TextField).last, 'Dommarametta');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('add_this_village'));
      await tester.pumpAndSettle();

      // The sheet must open in cascade mode with state/district already
      // locked from the cascade, and the typed name carried over — not
      // asked for again.
      expect(find.text('Andhra Pradesh'), findsWidgets);
      expect(find.text('Visakhapatnam'), findsWidgets);

      // Sheet fields, in the order the cascade branch of the sheet renders
      // them: name (already filled), mandal, PIN. Index 0 is the search
      // field's own village-name TextField, still present behind the sheet.
      await tester.enterText(find.byType(TextField).at(2), 'Palasa Mandal');
      await tester.enterText(find.byType(TextField).at(3), '532221');
      await tester.pumpAndSettle();

      await tester.tap(find.text('add_this_village').last);
      await tester.pumpAndSettle();

      expect(last?.name, 'Dommarametta',
          reason: 'a village created from the sheet must reach onPicked '
              'exactly like a tapped search result');
    });
  });

  group('ManaVillageSearchField: layout', () {
    testWidgets('no layout fault at 390/820/1440 in PIN mode', (tester) async {
      final built = _serviceWith(_defaultResponder);
      await pumpAtWidths(tester, _hosted(built.service, (_) {}), (width) async {
        expectNoLayoutFault(tester, 'ManaVillageSearchField (PIN) at $width');
      });
    });

    testWidgets('no layout fault at 390/820/1440 in cascade mode with results',
        (tester) async {
      final built = _serviceWith(_defaultResponder);
      final widget = _hosted(built.service, (_) {});
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      await openCascade(tester);
      await pickState(tester, 'Andhra Pradesh');
      await pickDistrict(tester, 'Visakhapatnam');
      await tester.enterText(find.byType(TextField).last, 'pal');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await pumpAtWidths(tester, widget, (width) async {
        expectNoLayoutFault(
            tester, 'ManaVillageSearchField (cascade, results) at $width');
      });
    });
  });
}

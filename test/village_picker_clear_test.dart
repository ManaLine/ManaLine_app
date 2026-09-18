import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/village_picker_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// Emptying the PIN takes the village name with it.
///
/// REPORTED FROM THE HANDSET: "removing pincode should remove the village
/// selected - now it's remains and user needs to remove by back spacing."
/// The screenshot showed an empty PIN box above a Village Name box still
/// reading "Panagallu (Rural)" — a village under a PIN that no longer
/// existed, clearable only by backspacing a name nobody had typed twice.
///
/// The rule was already written one widget over: ManaVillageSearchField's own
/// comment says "Changing an earlier step clears every later one". The
/// cascade obeyed it; the PIN picker did not.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Every lookup answers "nothing found". These tests are about what the
    // FIELDS do, not about search results.
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(const <Map<String, dynamic>>[]))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

Widget _hosted() {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: _FakeClient(),
    // A widget test fails on a pending timer at teardown, and GoTrue's
    // auto-refresh has nothing to do with what this exercises.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return UncontrolledProviderScope(
    container: ProviderContainer(overrides: [
      locationApiServiceProvider.overrideWithValue(LocationApiService(client)),
      translationCacheProvider.overrideWithValue(FakeTranslationCache()),
      authFlowProvider
          .overrideWith(() => SeededAuthFlowNotifier(const AuthFlowState())),
    ]),
    // A FIELD, not a screen: TextField needs a Material ancestor and this
    // widget brings none of its own.
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ManaVillagePickerField(onPicked: (_) {}, label: 'Village'),
        ),
      ),
    ),
  );
}

Finder _pinField() => find.byWidgetPredicate(
    (w) => w is TextField && w.keyboardType == TextInputType.number);

Finder _nameField() => find.byWidgetPredicate(
    (w) => w is TextField && w.keyboardType != TextInputType.number);

String _nameText(WidgetTester tester) =>
    tester.widget<TextField>(_nameField()).controller?.text ?? '';

void main() {
  setUp(seedSecureStorage);

  testWidgets('emptying the PIN clears the village name', (tester) async {
    await tester.pumpWidget(_hosted());
    await tester.pump();

    await tester.enterText(_pinField(), '517640');
    await tester.enterText(_nameField(), 'Panagallu');
    await tester.pumpAndSettle();
    expect(_nameText(tester), 'Panagallu');

    await tester.enterText(_pinField(), '');
    await tester.pumpAndSettle();

    expect(_nameText(tester), isEmpty,
        reason: 'the village belonged to the PIN that was just removed');
  });

  testWidgets('deleting one digit does NOT clear it', (tester) async {
    // The common correction. Five digits is invalid, but somebody fixing a
    // typo has not abandoned the village — clearing here would make every
    // correction cost the name too, which is a worse screen than the one
    // being fixed.
    await tester.pumpWidget(_hosted());
    await tester.pump();

    await tester.enterText(_pinField(), '517640');
    await tester.enterText(_nameField(), 'Panagallu');
    await tester.pumpAndSettle();

    await tester.enterText(_pinField(), '51764');
    await tester.pumpAndSettle();

    expect(_nameText(tester), 'Panagallu',
        reason: 'a half-typed PIN is a correction in progress, not a reset');
  });

  testWidgets('clearing an already-empty name is harmless', (tester) async {
    await tester.pumpWidget(_hosted());
    await tester.pump();
    await tester.enterText(_pinField(), '517640');
    await tester.pumpAndSettle();
    await tester.enterText(_pinField(), '');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

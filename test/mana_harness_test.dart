import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/colors.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/local_auth_store.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Tests for the TEST HARNESS itself.
///
/// A harness that silently fails open is worse than none: every screen test
/// built on it would report green while asserting nothing. These are the
/// negative controls that keep the rest of the suite honest.
void main() {
  group('the harness detects the faults it exists to catch', () {
    testWidgets('a genuine overflow is reported, not swallowed', (tester) async {
      // NEGATIVE CONTROL. If this ever passes with `isNull`, every
      // `expectNoLayoutFault` in the suite has become decorative.
      await pumpManaScreen(
        tester,
        Scaffold(
          body: Row(
            children: [
              // 600 logical pixels of unbreakable content on a 360pt phone.
              Container(width: 600, height: 20, color: ManaColors.brand),
            ],
          ),
        ),
      );

      final error = tester.takeException();
      expect(error, isNotNull,
          reason: 'the harness must surface a RenderFlex overflow');
      expect(error.toString(), contains('overflowed'));
    });

    testWidgets('text scaling actually reaches the widget tree', (tester) async {
      // Guards the MediaQuery placement: applied outside MaterialApp.router it
      // would be discarded, and every "at 2.0x" test would silently be a
      // second 1.0x test.
      double? seen;
      await pumpManaScreen(
        tester,
        Builder(builder: (context) {
          seen = MediaQuery.of(context).textScaler.scale(10) / 10;
          return const SizedBox.shrink();
        }),
        textScale: 2.0,
      );

      expect(seen, 2.0);
    });

    testWidgets('the surface really is 360x640', (tester) async {
      Size? size;
      await pumpManaScreen(
        tester,
        Builder(builder: (context) {
          size = MediaQuery.of(context).size;
          return const SizedBox.shrink();
        }),
      );

      expect(size, kManaSmallPhone);
    });
  });

  group('provider overrides', () {
    testWidgets('translations resolve without Supabase being initialised',
        (tester) async {
      // TranslationCache.load() touches Supabase.instance directly, which
      // throws in a test process. Reaching a real translated string proves the
      // fake is installed rather than the real cache silently erroring.
      String? telugu;
      await pumpManaScreen(
        tester,
        Consumer(builder: (context, ref, _) {
          ref.watch(translationLoaderProvider);
          telugu = ref.t('login_with_password');
          return const SizedBox.shrink();
        }),
        language: ManaLanguage.telugu,
      );

      expect(telugu, 'పాస్‌వర్డ్‌తో లాగిన్ చేయండి');
      expect(telugu, isNot('login_with_password'),
          reason: 'a raw key here means the fake cache was not installed, and '
              'every language test would be measuring ASCII width');
    });

    testWidgets('an unknown key falls back to the key, as production does',
        (tester) async {
      String? value;
      await pumpManaScreen(
        tester,
        Consumer(builder: (context, ref, _) {
          value = ref.t('no_such_key_exists');
          return const SizedBox.shrink();
        }),
      );

      expect(value, 'no_such_key_exists');
    });

    testWidgets('auth state is seeded before the first build', (tester) async {
      // Screens read language during build. Set after the first pump it would
      // only apply on frame two — and frame one is where overflow throws.
      ManaLanguage? languageAtFirstBuild;
      var builds = 0;
      await pumpManaScreen(
        tester,
        Consumer(builder: (context, ref, _) {
          if (builds++ == 0) {
            languageAtFirstBuild = ref.watch(authFlowProvider).language;
          }
          return const SizedBox.shrink();
        }),
        language: ManaLanguage.telugu,
      );

      expect(languageAtFirstBuild, ManaLanguage.telugu);
    });

    testWidgets('memberships can be seeded for the selector screens',
        (tester) async {
      int? count;
      await pumpManaScreen(
        tester,
        Consumer(builder: (context, ref, _) {
          count = ref.watch(authFlowProvider).memberships.length;
          return const SizedBox.shrink();
        }),
        authState: const AuthFlowState(
          personId: '2',
          memberships: [
            Membership(
              membershipId: 'm1',
              businessId: 'b1',
              businessName: 'sri tirumala finance',
              role: 'Owner',
              membershipStatus: 'Active',
            ),
          ],
        ),
      );

      expect(count, 1);
    });
  });

  group('secure storage', () {
    testWidgets('LocalAuthStore reads what the harness seeded', (tester) async {
      // LocalAuthStore and ManaSession both hold a static const
      // FlutterSecureStorage, so they cannot be reached through Riverpod. If
      // this seam ever breaks, LR-009 bails to /lr-001 and its layout tests
      // start asserting that an empty page does not overflow.
      int? pinLength;
      String? mobile;
      await pumpManaScreen(
        tester,
        const SizedBox.shrink(),
        storage: rememberedDeviceStorage(pinLength: 6, mobile: '9493509919'),
      );

      pinLength = await LocalAuthStore.readPinLength();
      mobile = await LocalAuthStore.readLastMobileNumber();

      expect(pinLength, 6);
      expect(mobile, '9493509919');
    });

    testWidgets('writes are observable, so a save can be asserted',
        (tester) async {
      final store = seedSecureStorage();
      await LocalAuthStore.savePin(pin: '123456', biometricEnabled: true);

      expect(store[ManaStorageKeys.pinLength], '6');
      expect(store[ManaStorageKeys.biometricEnabled], 'true');
    });

    testWidgets('storage does not leak between tests', (tester) async {
      // The previous test wrote a PIN. A fresh seed must not see it, or tests
      // would pass or fail depending on execution order.
      seedSecureStorage();
      expect(await LocalAuthStore.readPinLength(), isNull);
    });
  });

  group('the vendored translation fixture', () {
    test('covers every row captured from ui_translations', () {
      // 87 rows at capture time, extended as screens get wired to real keys
      // (120 as of the OW-001 phase-1 wiring, migrations 20260807161236/
      // 20260807161408/20260807161614). A DROP here means the fixture was
      // edited down, and screens would start falling back to raw keys —
      // narrow ASCII that quietly weakens every width assertion. Growth is
      // fine; shrinkage is the bug this guards against.
      expect(manaTranslationsFixture.length, greaterThanOrEqualTo(120));
    });

    test('has at least English and Telugu for every key', () {
      // ManaLanguage was cut down to English/Telugu only (commit 5ef453a) —
      // older rows still carry Hindi/Tamil/Kannada from before that cut,
      // which is harmless, but new rows are not required to.
      for (final entry in manaTranslationsFixture.entries) {
        expect(
          entry.value.keys,
          containsAll({'English', 'Telugu'}),
          reason: '${entry.key} is missing English or Telugu',
        );
      }
    });

    test('has no doubled-apostrophe transcription damage', () {
      // The fixture was generated by Postgres `format('%L')`, which escapes a
      // quote by DOUBLING it. Dart does not read '' as an escape — it reads
      // 'I''m new' as two adjacent literals and concatenates them to "Im new",
      // silently, with no compile error. This asserts the SQL-style escaping
      // was actually converted to Dart-style.
      for (final entry in manaTranslationsFixture.entries) {
        for (final value in entry.value.values) {
          expect(value, isNot(contains("''")),
              reason: '${entry.key} kept SQL escaping');
          expect(value, isNot(matches(RegExp(r'\bIm\b|\bTodays\b'))),
              reason: '${entry.key} lost an apostrophe to literal concatenation');
        }
      }
    });

    test('English is present and non-empty for every key', () {
      // English is the fallback path in TranslationCache.t(); an empty one
      // would surface a raw key on screen in every language.
      for (final entry in manaTranslationsFixture.entries) {
        expect(entry.value['English'], isNotEmpty, reason: entry.key);
      }
    });
  });
}

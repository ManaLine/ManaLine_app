import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/design/theme.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'mana_translations_fixture.dart';

export 'mana_translations_fixture.dart' show manaTranslationsFixture;

/// Test harness for pumping whole SCREENS, as opposed to lone components.
///
/// WHY THIS EXISTS: every screen in this app sits on four things a bare
/// `pumpWidget` does not provide — a Riverpod scope, the translation cache,
/// flutter_secure_storage, and a GoRouter ancestor. Miss any one and the
/// screen throws before it ever lays out, so the entire overflow class of bug
/// stayed untestable and shipped twice this week (LR-007's login button and
/// LR-003).
///
/// The harness deliberately supplies the REAL `ManaTheme.light()`. Text floors,
/// tap targets and every overflow are functions of the theme's type scale, so a
/// test against Flutter's default theme would be measuring a layout that does
/// not exist in production.
///
/// What it does NOT do is stub the API service providers. Nothing here should
/// reach the network on first frame; if a screen does, that is a finding about
/// the screen, not something to paper over — a build() that fetches is exactly
/// the shape that hangs against the REPLACE-ME host.

// ---------------------------------------------------------------------------
// Translations
// ---------------------------------------------------------------------------

/// A pre-loaded [TranslationCache] that never touches Supabase.
///
/// `TranslationCache.load()` calls `Supabase.instance.client` directly, which
/// throws in a test process because `Supabase.initialize` was never called.
/// Subclassing is enough to keep production code untouched — the real class
/// stays exactly as it ships.
class FakeTranslationCache extends TranslationCache {
  FakeTranslationCache([Map<String, Map<String, String>>? rows])
      : _rows = rows ?? manaTranslationsFixture;

  final Map<String, Map<String, String>> _rows;

  @override
  Future<void> load() async {}

  @override
  bool get isLoaded => true;

  @override
  String t(String key, String languageEnumValue) {
    final row = _rows[key];
    if (row == null) return key;
    return row[languageEnumValue] ?? row['English'] ?? key;
  }
}

// ---------------------------------------------------------------------------
// Auth flow
// ---------------------------------------------------------------------------

/// [AuthFlowNotifier] that starts from a caller-supplied state.
///
/// Seeding via `build()` rather than calling setters after the first pump
/// matters: `ref.watch(authFlowProvider).language` is read during build, so a
/// language set afterwards would only be exercised on the SECOND frame — and
/// the first frame is where overflow throws.
class SeededAuthFlowNotifier extends AuthFlowNotifier {
  SeededAuthFlowNotifier(this._seed);

  final AuthFlowState _seed;

  @override
  AuthFlowState build() => _seed;
}

// ---------------------------------------------------------------------------
// Secure storage
// ---------------------------------------------------------------------------

/// Keys `LocalAuthStore` and `ManaSession` read. Both use static
/// `const FlutterSecureStorage()` instances, so they cannot be overridden
/// through Riverpod — the package's own platform double is the seam.
class ManaStorageKeys {
  ManaStorageKeys._();

  static const pinLength = 'mana_pin_length';
  static const pinValue = 'mana_pin_value';
  static const biometricEnabled = 'mana_biometric_enabled';
  static const deviceFingerprint = 'mana_device_fingerprint';
  static const lastMobileNumber = 'mana_last_mobile_number';

  static const accessToken = 'mana_session_access_token';
  static const personId = 'mana_session_person_id';
  static const lastBusinessId = 'mana_session_last_business_id';
  static const lastMembershipId = 'mana_session_last_membership_id';
}

/// Installs an in-memory secure store. Call from `setUp`, or let
/// [pumpManaScreen] do it via its `storage` argument.
///
/// Returns the backing map so a test can assert on what a screen WROTE, not
/// just what it read.
Map<String, String> seedSecureStorage([Map<String, String> initial = const {}]) {
  final data = Map<String, String>.of(initial);
  FlutterSecureStorage.setMockInitialValues(data);
  return data;
}

/// The storage state of a returning person on a trusted device — the entry
/// condition LR-009 requires. Without `pin_length` that screen immediately
/// redirects to /lr-001 and never lays out at all.
Map<String, String> rememberedDeviceStorage({
  int pinLength = 6,
  String mobile = '9493509919',
  bool biometricEnabled = false,
}) =>
    {
      ManaStorageKeys.pinLength: '$pinLength',
      ManaStorageKeys.pinValue: '1' * pinLength,
      ManaStorageKeys.biometricEnabled: '$biometricEnabled',
      ManaStorageKeys.deviceFingerprint: 'test-device-fingerprint',
      ManaStorageKeys.lastMobileNumber: mobile,
    };

// ---------------------------------------------------------------------------
// Pumping
// ---------------------------------------------------------------------------

/// The cheap Android phones this app targets. 360x640 is the small end of what
/// field agents actually carry, and it is where fixed-height layouts break
/// first.
const Size kManaSmallPhone = Size(360, 640);

/// Text scales worth testing. 2.0 is not hypothetical — Android's font-size
/// slider combined with display-size scaling reaches it, and this app's Owners
/// skew older.
const List<double> kManaTextScales = [1.0, 1.3, 1.6, 2.0];

/// Pumps [screen] inside everything a real screen expects.
///
/// [storage] seeds flutter_secure_storage BEFORE the first frame, which is
/// required for any screen whose `initState` reads it.
///
/// Returns the [ProviderContainer] so a test can read provider state back.
Future<ProviderContainer> pumpManaScreen(
  WidgetTester tester,
  Widget screen, {
  double textScale = 1.0,
  Size surfaceSize = kManaSmallPhone,
  ManaLanguage language = ManaLanguage.english,
  AuthFlowState? authState,
  Map<String, String> storage = const {},
  List<Override> overrides = const [],
  Map<String, Map<String, String>>? translations,
  /// Frames to pump after the first. Deliberately a fixed count rather than
  /// `pumpAndSettle`: several screens run a repeating shimmer that never
  /// settles, and pumpAndSettle would time out rather than report a layout
  /// fault.
  int settleFrames = 3,
}) async {
  seedSecureStorage(storage);

  // devicePixelRatio 1.0 keeps logical pixels equal to the numbers above, so
  // an assertion about "120dp" means what it says.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      translationCacheProvider
          .overrideWithValue(FakeTranslationCache(translations)),
      authFlowProvider.overrideWith(
        () => SeededAuthFlowNotifier(
          (authState ?? const AuthFlowState()).copyWith(language: language),
        ),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => screen)],
    // Screens navigate away on unmet preconditions (LR-009 -> /lr-001). Those
    // destinations are not under test, but an unmatched route would throw and
    // masquerade as a layout failure.
    errorBuilder: (_, __) => const Scaffold(body: SizedBox.shrink()),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ManaTheme.light(),
        routerConfig: router,
        // Applied inside the app so the screen's own MediaQuery.of sees it.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );

  for (var i = 0; i < settleFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  return container;
}

/// Asserts the last pump produced no exception, with a message that names the
/// conditions — a bare `takeException` failure tells you nothing about which
/// scale or language broke.
void expectNoLayoutFault(WidgetTester tester, String what) {
  expect(
    tester.takeException(),
    isNull,
    reason: '$what threw during layout — most often a RenderFlex overflow '
        'from a fixed height or a bare Row wrapping scalable/translated text',
  );
}

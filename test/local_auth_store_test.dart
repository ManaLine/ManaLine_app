import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/local_auth_store.dart';

// Covers the web/native fingerprint split from Task 11 (see
// .superpowers/sdd/2026-09-07-website-phase-0-1-app-on-web/fingerprint-investigation.md).
// `kIsWeb` is a compile-time constant and cannot be faked in a test, so the
// branching logic behind LocalAuthStore.deviceFingerprint is pulled out into
// the pure, directly-testable decideDeviceFingerprint — same route Task 7
// took for webUploadRejectionReason.
void main() {
  group('decideDeviceFingerprint', () {
    test('native, nothing persisted yet: mints one and asks to persist it', () {
      var generated = false;
      final result = decideDeviceFingerprint(
        isWeb: false,
        persisted: null,
        cached: null,
        generate: () {
          generated = true;
          return 'fresh-native-value';
        },
      );
      expect(result.value, 'fresh-native-value');
      expect(result.shouldPersist, isTrue);
      expect(generated, isTrue);
    });

    test('native, already persisted: reuses it forever, never re-persists', () {
      final result = decideDeviceFingerprint(
        isWeb: false,
        persisted: 'stored-native-value',
        cached: null,
        generate: () => throw StateError('must not generate when persisted'),
      );
      expect(result.value, 'stored-native-value');
      expect(result.shouldPersist, isFalse);
    });

    test('web, first call this session: mints one but must not persist it', () {
      final result = decideDeviceFingerprint(
        isWeb: true,
        persisted: null,
        cached: null,
        generate: () => 'fresh-web-value',
      );
      expect(result.value, 'fresh-web-value');
      expect(result.shouldPersist, isFalse);
    });

    test('web, later call same session: reuses the in-memory cache, does not regenerate', () {
      final result = decideDeviceFingerprint(
        isWeb: true,
        persisted: null,
        cached: 'cached-web-value',
        generate: () => throw StateError('must not regenerate within a session'),
      );
      expect(result.value, 'cached-web-value');
      expect(result.shouldPersist, isFalse);
    });

    test('web, a value already in storage from before this change: honoured, not replaced', () {
      final result = decideDeviceFingerprint(
        isWeb: true,
        persisted: 'legacy-persisted-web-value',
        cached: null,
        generate: () => throw StateError('must not generate when persisted'),
      );
      expect(result.value, 'legacy-persisted-web-value');
      expect(result.shouldPersist, isFalse);
    });
  });
}

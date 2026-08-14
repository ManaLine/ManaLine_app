import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/login_registration/state/auth_flow_state.dart';

/// Fetches ui_translations (0047) once and caches it — editing a word
/// means editing a row in Supabase Table Editor, not a code change.
/// Falls back to English, then to the raw key itself, if a cell is
/// empty or the key doesn't exist at all — nothing ever breaks from a
/// missing translation.
class TranslationCache {
  final Map<String, Map<String, String?>> _rows = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      // Bounded. A build made without --dart-define points at
      // REPLACE-ME.supabase.co, which does not fail — it HANGS, so this
      // future never completed and every screen rendered raw keys forever
      // with no error anywhere. A timeout turns an invisible hang into a
      // recorded failure that the next screen's load() can retry.
      // Only English/Telugu are ever looked up now (ManaLanguage was cut
      // down to those two) — the other three columns still exist in the
      // table but there's nothing left in the app that can select them.
      final rows = await Supabase.instance.client
          .from('ui_translations')
          .select('translation_key, english, telugu')
          .timeout(const Duration(seconds: 10));
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _rows[r['translation_key'] as String] = {
          'English': r['english'] as String?,
          'Telugu': r['telugu'] as String?,
        };
      }
      _loaded = true;
      lastError = null;
    } catch (e) {
      // Kept non-fatal — a missing translation must never block a screen.
      // But it is no longer INVISIBLE: this swallowed the reason entirely,
      // and the whole pre-login flow rendering raw keys ("app_name",
      // "choose_workspace") was the result of one failed fetch that nobody
      // could see. Recorded so it can be surfaced and retried.
      lastError = e;
    }
  }

  /// Why the last load failed, or null. Non-null with an empty cache means
  /// every `t()` on screen is showing a raw key.
  Object? lastError;

  bool get isLoaded => _loaded;

  String t(String key, String languageEnumValue) {
    final row = _rows[key];
    if (row == null) {
      return key; // untranslated key — shows the raw key so it's obviously missing, not blank
    }
    return row[languageEnumValue] ?? row['English'] ?? key;
  }
}

final translationCacheProvider =
    Provider<TranslationCache>((ref) => TranslationCache());

/// Riverpod-friendly helper — call ref.watch(translationLoaderProvider)
/// once near the top of a screen's build() to ensure the cache is
/// loading/loaded, then use context/ref extension `t('key')` (below)
/// anywhere in that screen's widget tree.
final translationLoaderProvider = FutureProvider<void>((ref) async {
  await ref.read(translationCacheProvider).load();
});

extension TranslateRef on WidgetRef {
  /// Looks up `key` in the current language (from authFlowProvider).
  /// Safe to call even before translationLoaderProvider resolves — just
  /// returns the raw key until the cache loads, then a rebuild (from
  /// watching translationLoaderProvider) picks up the real value.
  String t(String key) {
    final lang = watch(authFlowProvider.select((s) => s.language));
    return read(translationCacheProvider).t(key, lang.enumValue);
  }
}

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
      final rows = await Supabase.instance.client
          .from('ui_translations')
          .select('translation_key, english, telugu, hindi, tamil, kannada');
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _rows[r['translation_key'] as String] = {
          'English': r['english'] as String?,
          'Telugu': r['telugu'] as String?,
          'Hindi': r['hindi'] as String?,
          'Tamil': r['tamil'] as String?,
          'Kannada': r['kannada'] as String?,
        };
      }
      _loaded = true;
    } catch (e) {
      // Non-fatal — every lookup just falls through to the raw key
      // until a retry succeeds (e.g. next screen's load() call).
    }
  }

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
    final lang = read(authFlowProvider).language;
    return read(translationCacheProvider).t(key, lang.enumValue);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/login_registration/state/auth_flow_state.dart';
import 'mana_text.dart';

/// Caches ui_info_popups (word -> plain-language explanation) the same way
/// TranslationCache caches ui_translations — one fetch, kept in memory,
/// never blocks a screen if it fails or hasn't finished loading yet.
class InfoPopupCache {
  final Map<String, ({String? teluguLabel, String englishInfo, String? teluguInfo})> _rows = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final rows = await Supabase.instance.client
          .from('ui_info_popups')
          .select('info_key, telugu_label, english_info, telugu_info')
          .timeout(const Duration(seconds: 10));
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        _rows[r['info_key'] as String] = (
          teluguLabel: r['telugu_label'] as String?,
          englishInfo: r['english_info'] as String? ?? '',
          teluguInfo: r['telugu_info'] as String?,
        );
      }
      _loaded = true;
    } catch (_) {
      // Non-fatal — a word simply shows no (i) popup until this loads.
    }
  }

  ({String? teluguLabel, String englishInfo, String? teluguInfo})? get(String key) => _rows[key];
}

final infoPopupCacheProvider = Provider<InfoPopupCache>((ref) => InfoPopupCache());

final infoPopupLoaderProvider = FutureProvider<void>((ref) => ref.read(infoPopupCacheProvider).load());

/// A word that shows a plain-language explanation on double-tap — the
/// glossary feature (docs: "double-tap a word to see a popup, OK to
/// dismiss"). Renders exactly like [ManaText.raw] and does nothing extra
/// when `infoKey` has no row in ui_info_popups — most words don't, by
/// design, and adding one is a Table Editor edit, not a code change.
class ManaInfoWord extends ConsumerWidget {
  final String text;
  final String infoKey;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const ManaInfoWord(
    this.text, {
    super.key,
    required this.infoKey,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(infoPopupLoaderProvider);
    final entry = ref.read(infoPopupCacheProvider).get(infoKey);
    final content = ManaText.raw(text, style: style, maxLines: maxLines, overflow: overflow);
    if (entry == null) return content;
    return GestureDetector(
      onDoubleTap: () => _showPopup(context, ref, entry),
      child: content,
    );
  }

  void _showPopup(
    BuildContext context,
    WidgetRef ref,
    ({String? teluguLabel, String englishInfo, String? teluguInfo}) entry,
  ) {
    final isTelugu = ref.read(authFlowProvider).language.enumValue == 'Telugu';
    final label = isTelugu ? (entry.teluguLabel ?? text) : text;
    final info = isTelugu ? (entry.teluguInfo ?? entry.englishInfo) : entry.englishInfo;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(label),
        content: ManaText.raw(info),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const ManaText('ok'),
          ),
        ],
      ),
    );
  }
}

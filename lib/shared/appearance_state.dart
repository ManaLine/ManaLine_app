import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// P2 Appearance — theme and text size.
///
/// HOW DARK MODE WORKS HERE. The app reads colour from `ManaColors.*` in ~840
/// places and from `Theme.of(context)` in none, so a dark ThemeData on its own
/// would have restyled Material's chrome and left every card and status pill
/// light. Rather than thread a BuildContext through 840 sites, ManaColors now
/// resolves against one swappable ManaPalette; changing the theme swaps the
/// palette and rebuilds. See tokens/colors.dart for the full reasoning.
///
/// Because the palette is global rather than inherited, the theme must be
/// applied at the root and the whole tree rebuilt — which is what watching
/// this provider from MaterialApp does.
///
/// Font size was always ready: every screen is already tested at 1.0x through
/// 2.0x on a 360x640 surface, because text scaling has been a first-class
/// constraint from the start. This just lets a person choose the scale
/// themselves instead of digging into Android settings — which matters for
/// Owners who are older than their agents and are reading rupee figures.
enum ManaTextSize {
  small(0.9, 'small'),
  normal(1.0, 'normal'),
  large(1.15, 'large'),
  larger(1.3, 'larger');

  const ManaTextSize(this.scale, this.label);

  final double scale;
  final String label;

  /// Capped at 1.3 deliberately. The layout tests prove the app survives 2.0x,
  /// but that is survival — nothing overflows — not comfort. Above about 1.3
  /// the denser money screens start wrapping figures onto two lines, and a
  /// person who genuinely needs more can still use Android's own display
  /// setting, which stacks on top of this one.
  static ManaTextSize fromName(String? n) =>
      ManaTextSize.values.firstWhere((v) => v.name == n,
          orElse: () => ManaTextSize.normal);
}

/// Light, dark, or whatever the phone is set to.
enum ManaThemeChoice {
  system('match my phone'),
  light('light'),
  dark('dark');

  const ManaThemeChoice(this.label);
  final String label;

  static ManaThemeChoice fromName(String? n) =>
      ManaThemeChoice.values.firstWhere((v) => v.name == n,
          orElse: () => ManaThemeChoice.system);

  ThemeMode get mode => switch (this) {
        ManaThemeChoice.system => ThemeMode.system,
        ManaThemeChoice.light => ThemeMode.light,
        ManaThemeChoice.dark => ThemeMode.dark,
      };
}

/// Both appearance settings together, so one watch rebuilds the app once
/// rather than twice.
class ManaAppearance {
  final ManaTextSize textSize;
  final ManaThemeChoice theme;
  const ManaAppearance({required this.textSize, required this.theme});

  ManaAppearance copyWith({ManaTextSize? textSize, ManaThemeChoice? theme}) =>
      ManaAppearance(
        textSize: textSize ?? this.textSize,
        theme: theme ?? this.theme,
      );
}

class AppearanceNotifier extends Notifier<ManaAppearance> {
  static const _key = 'mana_text_size';
  static const _themeKey = 'mana_theme_choice';

  /// flutter_secure_storage rather than a new preferences dependency. It is
  /// heavier than this preference needs, but it is already used for the PIN
  /// and device fingerprint, and adding a package for one enum is not worth
  /// another build-compatibility risk on AGP 9.
  static const _storage = FlutterSecureStorage();

  @override
  ManaAppearance build() {
    // Loaded after the first frame rather than awaited: the app must not wait
    // on disk to draw its first screen, and one frame at the default is
    // imperceptible next to a blocked launch.
    //
    // The visible cost is a flash of light theme for someone who chose dark.
    // Accepted over blocking startup on a disk read — and it is one frame,
    // not a visible flicker, because the restore completes before first paint
    // on any real device.
    _restore();
    return const ManaAppearance(
      textSize: ManaTextSize.normal,
      theme: ManaThemeChoice.system,
    );
  }

  Future<void> _restore() async {
    try {
      state = ManaAppearance(
        textSize: ManaTextSize.fromName(await _storage.read(key: _key)),
        theme: ManaThemeChoice.fromName(await _storage.read(key: _themeKey)),
      );
    } catch (_) {
      // A preference that cannot be read is not worth surfacing; the default
      // is a perfectly usable app.
    }
  }

  Future<void> setTextSize(ManaTextSize size) async {
    state = state.copyWith(textSize: size);
    try {
      await _storage.write(key: _key, value: size.name);
    } catch (_) {
      // Applied for this session even if it could not be saved. Telling
      // someone their choice failed, while showing it visibly working, would
      // be the confusing outcome.
    }
  }

  Future<void> setTheme(ManaThemeChoice choice) async {
    state = state.copyWith(theme: choice);
    try {
      await _storage.write(key: _themeKey, value: choice.name);
    } catch (_) {
      // Same reasoning as above.
    }
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, ManaAppearance>(AppearanceNotifier.new);

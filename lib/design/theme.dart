import 'package:flutter/material.dart';
import 'tokens/colors.dart';
import 'tokens/typography.dart';
import 'tokens/spacing.dart';
import 'motion.dart';

class ManaTheme {
  ManaTheme._();

  /// Builds a theme for [palette] AND makes it the active one.
  ///
  /// The swap has to happen here rather than in a widget, because ~840
  /// `ManaColors.*` call sites read the palette statically at build time — the
  /// theme and those tokens must never disagree, and building a ThemeData from
  /// one palette while the tokens still return another is exactly the
  /// half-dark screen this design avoids.
  static ThemeData forPalette(ManaPalette palette) {
    ManaColors.use(palette);
    return _build(palette);
  }

  static ThemeData light() {
    ManaColors.use(ManaPalette.light);
    return _build(ManaPalette.light);
  }

  static ThemeData dark() {
    ManaColors.use(ManaPalette.dark);
    return _build(ManaPalette.dark);
  }

  static ThemeData _build(ManaPalette palette) {
    final textTheme = ManaTypography.textTheme(palette.brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      scaffoldBackgroundColor: palette.surfaceMuted,
      colorScheme: ColorScheme(
        brightness: palette.brightness,
        // brandDeep, not brand: Flutter puts onPrimary (white) text on this,
        // and small white-on-#007ACC is only 4.51:1 — too thin to read in
        // direct sun. On brandDeep it is 7.18:1.
        primary: palette.brandDeep,
        onPrimary: palette.textOnDark,
        // Amber accent carries DARK text, never white: textPrimary on accent
        // is 8.0:1, white on accent would be 1.76:1 and unreadable. True in
        // both palettes — accent is the one colour that does not change.
        secondary: palette.accent,
        onSecondary: ManaPalette.light.textPrimary,
        error: palette.statusBad,
        onError: palette.textOnDark,
        surface: palette.surface,
        onSurface: palette.textPrimary,
      ),
      textTheme: textTheme,
      // One declaration gives all ~60 GoRoute screens the same transition,
      // including any added later — they all use GoRoute's `builder:`, which
      // produces a MaterialPage and therefore honours this. Doing it
      // per-route with CustomTransitionPage would have been 60 edits and
      // would have drifted on the 61st. Flutter's default here is the M3 zoom
      // transition, which is noticeably slower than the 240ms this uses.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ManaPageTransitions(),
          TargetPlatform.iOS: ManaPageTransitions(),
          TargetPlatform.windows: ManaPageTransitions(),
          TargetPlatform.macOS: ManaPageTransitions(),
          TargetPlatform.linux: ManaPageTransitions(),
          TargetPlatform.fuchsia: ManaPageTransitions(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ManaColors.surface,
        foregroundColor: ManaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: ManaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ManaRadius.md),
          side: BorderSide(color: ManaColors.divider, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ManaColors.inkFaint,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ManaRadius.ring),
        ),
        side: BorderSide.none,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ManaColors.accent,
          foregroundColor: ManaColors.textPrimary, // 8.0:1 on accent
          disabledBackgroundColor: ManaColors.surfaceSunken,
          disabledForegroundColor: ManaColors.textDisabled,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.lg, vertical: ManaSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ManaRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Outlined = secondary action. Blue reads as interactive without
          // competing with the amber filled button for primary attention.
          foregroundColor: ManaColors.brandDeep,
          side: BorderSide(color: ManaColors.brandDeep, width: 1.2),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.lg, vertical: ManaSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ManaRadius.sm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ManaColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ManaSpacing.md, vertical: ManaSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: BorderSide(color: ManaColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: BorderSide(color: ManaColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          // Focused field = blue, matching the interactive family. Amber is
          // reserved for filled actions so it stays unambiguous.
          borderSide: BorderSide(color: ManaColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: BorderSide(color: ManaColors.statusBad),
        ),
      ),
      dividerTheme: DividerThemeData(color: ManaColors.divider, thickness: 1),
      // Visible keyboard focus everywhere — quality floor per design skill's
      // "responsive, focus-visible, reduced-motion" baseline.
      focusColor: ManaColors.brand.withValues(alpha: 0.24),
    );
  }
}

import 'package:flutter/material.dart';
import 'tokens/colors.dart';
import 'tokens/typography.dart';
import 'tokens/spacing.dart';

class ManaTheme {
  ManaTheme._();

  static ThemeData light() {
    final textTheme = ManaTypography.textTheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: ManaColors.surfaceMuted,
      colorScheme: const ColorScheme.light(
        // brandDeep, not brand: Flutter puts onPrimary (white) text on this,
        // and small white-on-#007ACC is only 4.51:1 — too thin to read in
        // direct sun. On brandDeep it is 7.18:1.
        primary: ManaColors.brandDeep,
        onPrimary: ManaColors.textOnDark,
        // Amber accent carries DARK text, never white: textPrimary on accent
        // is 8.0:1, white on accent would be 1.76:1 and unreadable.
        secondary: ManaColors.accent,
        onSecondary: ManaColors.textPrimary,
        error: ManaColors.statusBad,
        surface: ManaColors.surface,
        onSurface: ManaColors.textPrimary,
      ),
      textTheme: textTheme,
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
          side: const BorderSide(color: ManaColors.divider, width: 1),
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
          side: const BorderSide(color: ManaColors.brandDeep, width: 1.2),
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
          borderSide: const BorderSide(color: ManaColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: const BorderSide(color: ManaColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          // Focused field = blue, matching the interactive family. Amber is
          // reserved for filled actions so it stays unambiguous.
          borderSide: const BorderSide(color: ManaColors.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: const BorderSide(color: ManaColors.statusBad),
        ),
      ),
      dividerTheme: const DividerThemeData(color: ManaColors.divider, thickness: 1),
      // Visible keyboard focus everywhere — quality floor per design skill's
      // "responsive, focus-visible, reduced-motion" baseline.
      focusColor: ManaColors.brand.withValues(alpha: 0.24),
    );
  }
}

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
        primary: ManaColors.ink,
        onPrimary: ManaColors.textOnDark,
        secondary: ManaColors.brass,
        onSecondary: ManaColors.ink,
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
          backgroundColor: ManaColors.brass,
          foregroundColor: ManaColors.ink,
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
          foregroundColor: ManaColors.ink,
          side: const BorderSide(color: ManaColors.ink, width: 1.2),
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
          borderSide: const BorderSide(color: ManaColors.brass, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ManaRadius.sm),
          borderSide: const BorderSide(color: ManaColors.statusBad),
        ),
      ),
      dividerTheme: const DividerThemeData(color: ManaColors.divider, thickness: 1),
      // Visible keyboard focus everywhere — quality floor per design skill's
      // "responsive, focus-visible, reduced-motion" baseline.
      focusColor: ManaColors.brass.withValues(alpha: 0.24),
    );
  }
}

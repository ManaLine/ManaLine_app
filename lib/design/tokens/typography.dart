import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

/// MANA LINE type system.
///
/// Manrope (display/headers) + Inter (body/data). Chosen over a display
/// serif deliberately — this is a money-handling utility tool used
/// outdoors under time pressure, not a brand marketing surface; numeral
/// legibility and clear weight contrast matter more than character.
/// Both faces have solid tabular-figure support, which matters
/// everywhere a rupee amount is shown (BR-consistent monetary display).
///
/// NOTE ON OFFLINE FIRST PAINT: google_fonts fetches over network on
/// first use and caches thereafter. Given this app's whole design
/// premise is "works in low connectivity," bundle Manrope/Inter as
/// actual asset files in `assets/fonts/` for the production build
/// (`GoogleFonts.config.allowRuntimeFetching = false` + local
/// `pubspec.yaml` font declarations) rather than relying on the runtime
/// fetch — flagged here so it isn't missed at release time.
class ManaTypography {
  ManaTypography._();

  static TextTheme textTheme(Brightness brightness) {
    final baseColor = brightness == Brightness.dark
        ? ManaColors.textOnDark
        : ManaColors.textPrimary;
    const secondaryColor = ManaColors.textSecondary;

    return TextTheme(
      // Headers — Manrope, heavier weights only, used with restraint
      displayLarge: GoogleFonts.manrope(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: baseColor,
        height: 1.15,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.25,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),

      // Body — Inter, for everything read at length or scanned quickly
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: baseColor, height: 1.4),
      bodyMedium:
          GoogleFonts.inter(fontSize: 14, color: baseColor, height: 1.4),
      bodySmall:
          GoogleFonts.inter(fontSize: 13, color: secondaryColor, height: 1.35),

      // Labels — Inter, medium weight, used for form fields/buttons/chips
      labelLarge: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: baseColor),
      labelMedium: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: secondaryColor),
      labelSmall: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: secondaryColor),
    );
  }

  /// Dedicated style for monetary figures — tabular numerals so columns
  /// of amounts (Loan Portfolio, Record Book, Settlement) align cleanly,
  /// which plain body text does not guarantee.
  static TextStyle amount({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? ManaColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

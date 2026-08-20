import 'package:flutter/material.dart';
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
/// BUNDLED, NOT FETCHED. google_fonts pulled these over the network on first
/// use, so first paint depended on a request in exactly the low-connectivity
/// conditions this app is built for: a village user on 2G saw system fallback
/// fonts, and every rupee figure rendered without the tabular figures that
/// keep money columns aligned. Both families now ship in `assets/fonts/` as
/// variable TTFs and are declared in pubspec.yaml; nothing here touches the
/// network.
/// Family names as declared in pubspec.yaml. Named constants so a typo is a
/// compile error rather than a silent fallback to the system font — which is
/// the failure this whole change exists to remove, and which looks like
/// nothing more than "the app renders slightly differently today".
const _manrope = 'Manrope';
const _inter = 'Inter';

class ManaTypography {
  ManaTypography._();

  static TextTheme textTheme(Brightness brightness) {
    final baseColor = brightness == Brightness.dark
        ? ManaColors.textOnDark
        : ManaColors.textPrimary;
    final secondaryColor = ManaColors.textSecondary;

    return TextTheme(
      // Headers — Manrope, heavier weights only, used with restraint
      displayLarge: TextStyle(fontFamily: _manrope, 
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: baseColor,
        height: 1.15,
      ),
      displayMedium: TextStyle(fontFamily: _manrope, 
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.2,
      ),
      headlineMedium: TextStyle(fontFamily: _manrope, 
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: baseColor,
        height: 1.25,
      ),
      titleLarge: TextStyle(fontFamily: _manrope, 
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      titleMedium: TextStyle(fontFamily: _manrope, 
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),

      // Body — Inter, for everything read at length or scanned quickly
      bodyLarge: TextStyle(fontFamily: _inter, fontSize: 16, color: baseColor, height: 1.4),
      bodyMedium:
          TextStyle(fontFamily: _inter, fontSize: 14, color: baseColor, height: 1.4),
      bodySmall:
          TextStyle(fontFamily: _inter, fontSize: 13, color: secondaryColor, height: 1.35),

      // Labels — Inter, medium weight, used for form fields/buttons/chips
      labelLarge: TextStyle(fontFamily: _inter, 
          fontSize: 14, fontWeight: FontWeight.w600, color: baseColor),
      labelMedium: TextStyle(fontFamily: _inter, 
          fontSize: 13, fontWeight: FontWeight.w600, color: secondaryColor),
      labelSmall: TextStyle(fontFamily: _inter, 
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
    return TextStyle(fontFamily: _inter, 
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? ManaColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// Named styles for the recurring inline patterns.
///
/// WHY: 327 screens-level `TextStyle(fontSize: ...)` literals existed before
/// this, 253 of them hardcoding 13 — the legibility floor written out by hand
/// on every screen. Restyling the app meant editing 327 sites; now each
/// recurring role has one name and one definition.
///
/// GETTERS, NOT CONSTS. ManaColors is palette-switched global state (see
/// main.dart's theme note): a `static const` style would capture the palette
/// active at class-load and paint light-theme grey onto dark surfaces after a
/// switch. A getter re-reads the palette on every build, exactly like the
/// ~840 direct token call sites do.
///
/// The names are ROLES, not sizes — `note`, not `size13` — so the day the
/// floor moves the call sites already say what they meant.
class ManaType {
  ManaType._();

  /// Explanatory line under a control; hints, sort orders, empty-state text.
  /// The single most common style in the app (172 sites at adoption).
  static TextStyle get note =>
      TextStyle(fontSize: 13, color: ManaColors.textSecondary);

  /// A note that must read as an error. Same voice, status colour.
  static TextStyle get noteBad =>
      TextStyle(fontSize: 13, color: ManaColors.statusBad);

  /// A note that must read as a warning.
  static TextStyle get noteWarn =>
      TextStyle(fontSize: 13, color: ManaColors.statusWarn);

  /// Small print at the very bottom of the scale — timestamps, IDs under a
  /// name. 12 is the absolute floor; nothing renders smaller.
  static TextStyle get fine =>
      TextStyle(fontSize: 12, color: ManaColors.textSecondary);

  /// Secondary text at body size — de-emphasised, not smaller.
  static TextStyle get secondary => TextStyle(color: ManaColors.textSecondary);

  /// Body-floor text in the default colour.
  static const TextStyle small = TextStyle(fontSize: 13);

  /// Emphasis within small text — a count, a name in a dense row.
  static const TextStyle smallStrong =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// A card or section heading.
  static const TextStyle cardTitle =
      TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

  /// A sheet or dialog heading.
  static const TextStyle sheetTitle =
      TextStyle(fontWeight: FontWeight.bold, fontSize: 18);

  /// Bold emphasis at the inherited size.
  static const TextStyle strong = TextStyle(fontWeight: FontWeight.bold);

  /// Semi-bold emphasis at the inherited size — names in rows, keys in
  /// key-value pairs.
  static const TextStyle emphasis = TextStyle(fontWeight: FontWeight.w600);

  /// Heavy emphasis at the inherited size.
  static const TextStyle heavy = TextStyle(fontWeight: FontWeight.w700);

  /// Inherited size, error colour.
  static TextStyle get bad => TextStyle(color: ManaColors.statusBad);
}

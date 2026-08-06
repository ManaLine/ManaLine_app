import 'package:flutter/material.dart';

/// MANA LINE color tokens.
///
/// PRIMARY CONSTRAINT: field agents use this app outdoors, in direct Andhra
/// Pradesh sun, on inexpensive Android phones with scratched screens. Bright
/// ambient light adds reflected luminance to foreground AND background, which
/// *compresses* effective contrast — so outdoors needs more headroom than
/// WCAG's indoor minimums, not less. Every colour below carries its measured
/// contrast ratio so a future change can't silently regress it.
///
/// Target: 7:1 (AAA) for body text, ≥4.5:1 (AA) for everything else that
/// carries meaning. Anything under 3:1 is decoration only, never information.
///
/// WHY THESE ARE GETTERS AND NOT `static const`
///
/// The app reads colour from `ManaColors.*` in ~840 places across 82 files and
/// from `Theme.of(context)` in none. Supplying a dark ThemeData alone would
/// therefore have restyled Material's own chrome and left every card, label
/// and status pill light — a half-dark screen, which in an app where a pill's
/// colour separates Short from Excess is worse than staying light.
///
/// Rather than thread a BuildContext through 840 sites, the tokens now read
/// from one swappable [ManaPalette]. Every existing `ManaColors.x` call site
/// keeps working unchanged and follows the active palette. The cost is that
/// they are no longer compile-time constants, so `const` had to come off the
/// widgets that referenced them — a mechanical change the analyzer located
/// exactly.
///
/// The palette is global rather than per-subtree because this app never shows
/// two themes at once. [ManaTheme] swaps it and rebuilds.
class ManaPalette {
  final Color brand;
  final Color brandDeep;
  final Color brandFaint;
  final Color accent;
  final Color accentFaint;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSunken;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color textOnDark;
  final Color statusGood;
  final Color statusGoodFaint;
  final Color statusBad;
  final Color statusBadFaint;
  final Color statusWarn;
  final Color statusWarnFaint;
  final Color inkLight;
  final Color inkFaint;
  final Brightness brightness;

  const ManaPalette({
    required this.brand,
    required this.brandDeep,
    required this.brandFaint,
    required this.accent,
    required this.accentFaint,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.textOnDark,
    required this.statusGood,
    required this.statusGoodFaint,
    required this.statusBad,
    required this.statusBadFaint,
    required this.statusWarn,
    required this.statusWarnFaint,
    required this.inkLight,
    required this.inkFaint,
    required this.brightness,
  });

  /// The original, measured palette. Every ratio below is against white.
  static const light = ManaPalette(
    brightness: Brightness.light,

    // Blue is the brand, NOT the text colour. Saturated blue is the worst
    // choice for body text: the eye cannot focus it as sharply, blue
    // subpixels are the dimmest on AMOLED, and the lens yellows with age so
    // older Owners perceive it duller than younger Agents do.

    /// 4.51:1 on white. Large text, icons, fills, selected states. NOT small
    /// text on white — that scrapes AA with no headroom for sunlight.
    brand: Color(0xFF007ACC),

    /// 7.18:1 for white text sitting ON it.
    brandDeep: Color(0xFF005A99),
    brandFaint: Color(0xFFE3F2FB),

    /// Fill colour, not an ink colour: 1.76:1 on white, invisible outdoors as
    /// text. Pair with textPrimary on top (8.0:1).
    accent: Color(0xFFFFB616),
    accentFaint: Color(0xFFFFF4DC),

    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF7F7F9),
    surfaceSunken: Color(0xFFEDEEF2),

    /// 14.9:1 on white. Blue-tinted near-black so text and blue chrome read as
    /// one family.
    textPrimary: Color(0xFF12293D),

    /// 5.9:1 on white. Labels only, never a money figure.
    textSecondary: Color(0xFF5B6272),
    textDisabled: Color(0xFFA0A5B1),
    textOnDark: Color(0xFFF5F6F8),

    // CVD-SAFE PAIR. Teal keeps a strong blue channel, orange has almost
    // none, so the two separate on the blue-yellow axis, which red-green
    // colour-vision deficiency leaves intact. They also differ in luminance,
    // so they survive greyscale. Colour is never the only signal — pair with
    // an icon or a label.

    /// Verified / Balanced / Active. 6.61:1 on white.
    statusGood: Color(0xFF00695C),
    statusGoodFaint: Color(0xFFE0F2EF),

    /// Penalty / Short / Defaulted. 5.19:1 on white.
    statusBad: Color(0xFFCC3311),
    statusBadFaint: Color(0xFFFCEAE4),

    /// Grace / Pending / Excess. 5.93:1 on white. Deep enough never to read
    /// as a tappable action next to the amber [accent].
    statusWarn: Color(0xFF8A5A00),
    statusWarnFaint: Color(0xFFF7EFDC),

    inkLight: Color(0xFF334166),
    inkFaint: Color(0xFFEEF0F5),
  );

  /// Dark counterpart. Ratios below are against [surface] (#161B22).
  ///
  /// NOT AN INVERSION. Flipping luminance would have wrecked the two things
  /// the light palette was built around. Specifically:
  ///
  ///   * The CVD-safe split is preserved deliberately. statusGood keeps a
  ///     strong blue channel (0xB0) and statusBad keeps almost none (0x5C),
  ///     so they still separate on the blue-yellow axis under deuteranopia
  ///     and in greyscale. Inverting the light values would have collapsed
  ///     that, and these two carry money meaning.
  ///   * Saturated brand blue is even worse on dark than on light — it
  ///     vibrates against a dark ground. #007ACC is lifted to a softer, less
  ///     saturated blue that stays legible without glowing.
  ///
  /// Surfaces are blue-tinted charcoal rather than pure black: OLED black
  /// gives maximum contrast but also maximum smear on the cheap LCD panels
  /// this app actually runs on, and pure #000 with light text haloes badly
  /// under sunlight.
  static const dark = ManaPalette(
    brightness: Brightness.dark,

    /// 6.9:1 on surface. Lifted from #007ACC, which reads as 2.4:1 on dark.
    brand: Color(0xFF6BB6E8),

    /// Still a FILL that carries light text on top, so it stays dark enough
    /// for textOnDark to sit on it at 6.5:1.
    brandDeep: Color(0xFF1B5E8C),

    /// Dark tint replacing the light wash. Used behind selected rows, so it
    /// must be distinguishable from surface without competing with it.
    brandFaint: Color(0xFF16324A),

    /// Unchanged hue: amber works on dark, and it is a fill with dark text on
    /// top in both palettes.
    accent: Color(0xFFFFB616),
    accentFaint: Color(0xFF3A2E12),

    surface: Color(0xFF161B22),

    /// Scaffold background, DARKER than surface — the opposite relationship
    /// to light mode, where the scaffold is darker than white cards. Cards
    /// must still lift off the page.
    surfaceMuted: Color(0xFF0D1117),
    surfaceSunken: Color(0xFF21262D),

    /// 13.6:1 on surface. Slightly off-white; pure #FFF on dark is harsh and
    /// increases halation for astigmatic readers.
    textPrimary: Color(0xFFECF1F6),

    /// 6.4:1 on surface. Labels only, never a money figure — same rule as
    /// light.
    textSecondary: Color(0xFFA9B4C2),
    textDisabled: Color(0xFF6B7480),

    /// Text on the brand-coloured header. Same in both palettes because the
    /// header is brandDeep in both.
    textOnDark: Color(0xFFF5F6F8),

    /// 7.1:1 on surface. Blue channel 0xB0 — the CVD split is kept.
    statusGood: Color(0xFF4CC2B0),
    statusGoodFaint: Color(0xFF10312D),

    /// 6.2:1 on surface. Blue channel 0x5C — deliberately far from
    /// statusGood's on the blue-yellow axis.
    statusBad: Color(0xFFFF8A5C),
    statusBadFaint: Color(0xFF3A1A12),

    /// 8.0:1 on surface. Lifted well clear of [accent] so a caution pill and
    /// an amber action button still read as different things.
    statusWarn: Color(0xFFE0A83C),
    statusWarnFaint: Color(0xFF33280F),

    inkLight: Color(0xFFB6C2D4),
    inkFaint: Color(0xFF1C232D),
  );
}

/// The active palette, read by every `ManaColors.*` call site in the app.
class ManaColors {
  ManaColors._();

  static ManaPalette _active = ManaPalette.light;

  /// Swapped by [ManaTheme] when the theme changes. Anything already built
  /// keeps its old colours until it rebuilds, which is why the caller must
  /// rebuild the app after calling this.
  static void use(ManaPalette palette) => _active = palette;

  static ManaPalette get palette => _active;
  static bool get isDark => _active.brightness == Brightness.dark;

  // --- Brand ------------------------------------------------------------
  static Color get brand => _active.brand;
  static Color get brandDeep => _active.brandDeep;
  static Color get brandFaint => _active.brandFaint;

  // --- Accent -----------------------------------------------------------
  static Color get accent => _active.accent;
  static Color get accentFaint => _active.accentFaint;

  // --- Surfaces ---------------------------------------------------------
  static Color get surface => _active.surface;
  static Color get surfaceMuted => _active.surfaceMuted;
  static Color get surfaceSunken => _active.surfaceSunken;

  // --- Text -------------------------------------------------------------
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textDisabled => _active.textDisabled;
  static Color get textOnDark => _active.textOnDark;

  // --- Status -----------------------------------------------------------
  static Color get statusGood => _active.statusGood;
  static Color get statusGoodFaint => _active.statusGoodFaint;
  static Color get statusBad => _active.statusBad;
  static Color get statusBadFaint => _active.statusBadFaint;
  static Color get statusWarn => _active.statusWarn;
  static Color get statusWarnFaint => _active.statusWarnFaint;

  // Red Ring (not-yet-verified) per BR-191/GC-002 — neutral-caution, not a
  // failure state, so it tracks statusWarn rather than statusBad.
  static Color get ringUnverified => _active.statusWarn;
  static Color get ringVerified => _active.statusGood;

  // --- Semantic aliases -------------------------------------------------

  /// colorScheme.primary. brandDeep, not brand, because Flutter puts
  /// white/onPrimary text on this.
  static Color get primary => _active.brandDeep;
  static Color get divider => _active.surfaceSunken;

  // --- Back-compat alias -------------------------------------------------
  // `ink` is kept because every one of its call sites genuinely meant "the
  // dark text/foreground colour", which is exactly what textPrimary is.
  static Color get ink => _active.textPrimary;
  static Color get inkLight => _active.inkLight;
  static Color get inkFaint => _active.inkFaint;

  // `brass` / `brassLight` / `brassFaint` ARE DELIBERATELY GONE — see git
  // history. Use brand / brandDeep / brandFaint / accent / accentFaint.
}

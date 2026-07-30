import 'package:flutter/material.dart';

/// MANA LINE color tokens.
///
/// PRIMARY CONSTRAINT: field agents use this app outdoors, in direct Andhra
/// Pradesh sun, on inexpensive Android phones with scratched screens. Bright
/// ambient light adds reflected luminance to foreground AND background, which
/// *compresses* effective contrast — so outdoors needs more headroom than
/// WCAG's indoor minimums, not less. Every colour below carries its measured
/// contrast ratio against white so a future change can't silently regress it.
///
/// Target: 7:1 (AAA) for body text, ≥4.5:1 (AA) for everything else that
/// carries meaning. Anything under 3:1 is decoration only, never information.
///
/// A NOTE ON THE PREVIOUS PALETTE: `textPrimary` used to be an alias of the
/// brand colour (`textPrimary = ink`), which meant one token did two jobs —
/// changing the brand silently repainted every line of body text in the app.
/// They are deliberately separate now. Brand colour and text colour are
/// different decisions and must stay independently changeable.
class ManaColors {
  ManaColors._();

  // --- Brand ------------------------------------------------------------
  // Blue is the brand, NOT the text colour. Saturated blue is the worst
  // choice for body text: the eye cannot focus it as sharply (chromatic
  // aberration), blue subpixels are the dimmest on AMOLED, and the lens
  // yellows with age so older Owners perceive it duller than younger Agents
  // do. Used for chrome — headers, links, selected states — the way PhonePe
  // uses its purple.

  /// 4.51:1 on white. Fine for large text, icons, fills and selected states.
  /// NOT for small text on white: that scrapes the AA minimum with no
  /// headroom left for sunlight.
  static const brand = Color(0xFF007ACC);

  /// 7.18:1 for white text sitting ON it. Use wherever small white labels sit
  /// on blue (app bars, filled primary buttons) — white on [brand] is only
  /// 4.51:1, too thin for small type outdoors.
  static const brandDeep = Color(0xFF005A99);

  /// Light blue wash for selected rows, info banners, chips.
  static const brandFaint = Color(0xFFE3F2FB);

  // --- Accent -----------------------------------------------------------

  /// Filled primary actions, with [textPrimary] ON TOP — that pairing is
  /// 8.0:1, nearly double the 4.74:1 the previous brass accent gave.
  ///
  /// NEVER use for small text or thin icons on white: 1.76:1, effectively
  /// invisible outdoors. This is a fill colour, not an ink colour.
  static const accent = Color(0xFFFFB616);
  static const accentFaint = Color(0xFFFFF4DC);

  // --- Surfaces ---------------------------------------------------------
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF7F7F9);
  static const surfaceSunken = Color(0xFFEDEEF2); // list dividers, disabled fields

  // --- Text -------------------------------------------------------------

  /// 14.9:1 on white. Near-black, but blue-tinted so text and blue chrome
  /// read as one family rather than two unrelated palettes. Deliberately as
  /// legible as the navy it replaces (14.06:1) — text contrast was not traded
  /// away to gain a blue brand.
  static const textPrimary = Color(0xFF12293D);

  /// 5.9:1 on white. Labels and secondary lines only, never a money figure.
  static const textSecondary = Color(0xFF5B6272);
  static const textDisabled = Color(0xFFA0A5B1);
  static const textOnDark = Color(0xFFF5F6F8);

  // --- Status -----------------------------------------------------------
  // CVD-SAFE PAIR. The previous statusGood #2E7D4F / statusBad #C0392B was
  // the single worst pairing available: red-green deficiency affects ~8% of
  // men, which in a field-agent population is not a rounding error, and those
  // two colours also sat at almost identical luminance (0.158 vs 0.143) — so
  // under deuteranopia, or in greyscale, they collapsed into two similar
  // muddy tones. They were carrying money-critical meaning (Short/Excess,
  // penalty, defaulted).
  //
  // The fix is the canonical teal/orange split: teal keeps a strong blue
  // channel (0x5C), orange has almost none (0x11), so the two separate on the
  // blue-yellow axis, which red-green CVD leaves intact. They also now differ
  // in luminance (0.109 vs 0.152) so they survive greyscale and monochrome
  // rendering too.
  //
  // Colour still must never be the ONLY signal — pair with an icon or a text
  // label (ManaStatusPill already prints the label, which is the right shape).

  /// Verified / Balanced / Active / Full Collection. 6.61:1 on white.
  static const statusGood = Color(0xFF00695C);
  static const statusGoodFaint = Color(0xFFE0F2EF);

  /// Penalty / Short / Rejected / Defaulted. 5.19:1 on white.
  static const statusBad = Color(0xFFCC3311);
  static const statusBadFaint = Color(0xFFFCEAE4);

  /// Grace Period / Pending / Excess / Partial. 5.93:1 on white.
  ///
  /// Moved from #B8860B because [accent] is now amber: a bright amber action
  /// button and an amber "caution" pill in the same view would have made amber
  /// mean two opposite things. This is deep enough that it never reads as a
  /// tappable action.
  static const statusWarn = Color(0xFF8A5A00);
  static const statusWarnFaint = Color(0xFFF7EFDC);

  // Red Ring (not-yet-verified) per BR-191/GC-002 — neutral-caution, not a
  // failure state, so it tracks statusWarn rather than statusBad. Previously
  // identical to statusBad, which overstated it.
  static const ringUnverified = statusWarn;
  static const ringVerified = statusGood;

  // --- Semantic aliases -------------------------------------------------

  /// colorScheme.primary. [brandDeep], not [brand], because Flutter puts
  /// white/onPrimary text on this and small white-on-[brand] is too thin.
  static const primary = brandDeep;
  static const divider = surfaceSunken;

  // --- Back-compat alias -------------------------------------------------
  // `ink` is kept because every one of its ~30 call sites genuinely meant "the
  // dark text/foreground colour", which is exactly what textPrimary is.
  static const ink = textPrimary;
  static const inkLight = Color(0xFF334166);
  static const inkFaint = Color(0xFFEEF0F5);

  // `brass` / `brassLight` / `brassFaint` ARE DELIBERATELY GONE. Aliasing
  // brass to accent looked harmless and was not: accent is a FILL colour at
  // 1.76:1 on white, while nearly all 49 brass call sites were icons, dots,
  // progress fills and text on LIGHT surfaces — including the PIN entry dots,
  // which would have been near-invisible during login. Every site has been
  // remapped explicitly (brand for foreground on light, accent for fills
  // carrying dark text, brandFaint for tints), and the names are removed so
  // the ambiguity cannot come back: `brass` no longer compiles, which is the
  // point. Use brand / brandDeep / brandFaint / accent / accentFaint.
}

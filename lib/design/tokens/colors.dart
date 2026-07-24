import 'package:flutter/material.dart';

/// MANA LINE color tokens.
///
/// Design rationale (not arbitrary — see design plan in conversation):
/// Grounded in the physical object this app replaces: a paper account
/// book (khata/passbook) written in dark ink, with a brass-coin accent
/// for the one action that matters (collect, confirm, approve). Avoids
/// the generic AI-default warm-cream+terracotta palette on purpose.
///
/// Status colors are desaturated enough to stay legible in direct
/// sunlight (field agents work outdoors) against a white/near-white
/// ground, and map 1:1 to the spec's own status vocabulary — never
/// invent a new color for a status the spec already named.
class ManaColors {
  ManaColors._();

  // --- Brand core -----------------------------------------------------
  static const ink = Color(0xFF1B2B4B); // primary — ledger ink
  static const inkLight = Color(0xFF334166);
  static const inkFaint = Color(0xFFEEF0F5); // ink tinted for subtle surfaces

  static const brass = Color(0xFFC68A2E); // accent — primary actions only
  static const brassLight = Color(0xFFE0AC5C);
  static const brassFaint = Color(0xFFFBF1E1);

  // --- Surfaces ---------------------------------------------------------
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF7F7F9);
  static const surfaceSunken = Color(0xFFEDEEF2); // e.g. list dividers, disabled fields

  // --- Text ---------------------------------------------------------
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF5B6272);
  static const textDisabled = Color(0xFFA0A5B1);
  static const textOnDark = Color(0xFFF5F6F8);

  // --- Status (map 1:1 to spec vocabulary — do not invent new ones) -----
  // Verified / Balanced / Active / Full Collection
  static const statusGood = Color(0xFF2E7D4F);
  static const statusGoodFaint = Color(0xFFE5F3EA);

  // Penalty / Short / Rejected / Defaulted
  static const statusBad = Color(0xFFC0392B);
  static const statusBadFaint = Color(0xFFFBEAE8);

  // Grace Period / Pending / Excess / Partial
  static const statusWarn = Color(0xFFB8860B);
  static const statusWarnFaint = Color(0xFFFAF1DD);

  // Red Ring (not-yet-verified) per BR-191/GC-002 — distinct from statusBad,
  // this is neutral-caution, not a failure state.
  static const ringUnverified = Color(0xFFC0392B);
  static const ringVerified = statusGood;

  // --- Semantic aliases used throughout the design system --------------
  static const primary = ink;
  static const accent = brass;
  static const divider = surfaceSunken;
}

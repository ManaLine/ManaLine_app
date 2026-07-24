/// Spacing scale — 4pt base grid. Kept small/disciplined on purpose:
/// this app is used one-handed in the field, dense-but-legible beats
/// airy-but-scrolly for a due-list an Agent taps through dozens of times
/// a day.
class ManaSpacing {
  ManaSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Radius tokens. The signature shape: a soft, slightly asymmetric
/// "ring" radius echoing the Green/Red Verification Ring (BR-191/
/// GC-002) — applied consistently to cards/chips/avatars app-wide so
/// the ring motif reads as one coherent visual language, not just a
/// one-off avatar decoration.
class ManaRadius {
  ManaRadius._();
  static const sm = 6.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const ring = 999.0; // fully circular — avatars, status pills, ring accents
}

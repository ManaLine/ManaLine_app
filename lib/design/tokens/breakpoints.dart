/// Where the layout changes its mind.
///
/// The design system had NO breakpoint before this file — not one
/// `MediaQuery...size.width` in lib/design/ or lib/shared/. Every screen was
/// built for a 360x640 handset and tested at that surface, which is why the
/// web answer is to clamp rather than to reflow: reflowing ~85 screens would
/// re-open the overflow bug class that has already shipped four times.
class ManaBreakpoints {
  const ManaBreakpoints._();

  /// Below this, a viewport is a handset and nothing here applies. This used
  /// to be the whole story — but it is an assumption about today's device
  /// fleet (every targeted Android handset sits under it), not a mechanism:
  /// an Android tablet or an unfolded foldable in portrait can exceed 600dp,
  /// and `setPreferredOrientations` (main.dart) is a request the platform
  /// routinely ignores on large screens. `ManaWebFrame` now also gates on
  /// `kIsWeb`, which is what actually makes the clamp incapable of changing
  /// the Android build — by construction, not by fleet assumption.
  static const compact = 600.0;

  /// How wide the centred column is allowed to get. Roughly a large handset,
  /// so the screens render in the shape they were designed and tested in.
  static const columnMax = 480.0;
}

/// Routes that have been laid out for a wide window and must NOT be clamped.
///
/// Empty on purpose. Plan 2 adds a path here as each of the five workflows
/// becomes genuinely responsive — so a screen is only ever let out of the
/// column once somebody has laid it out and tested it at that width.
///
/// Mutable rather than const because the widget test needs to add and remove
/// an entry; nothing in the app writes to it at runtime.
final Set<String> kManaWideRoutes = <String>{};

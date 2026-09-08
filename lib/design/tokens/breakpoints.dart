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

  /// A tablet, or a browser window somebody has narrowed. Two columns fit;
  /// a nav rail does not, so the bottom nav stays.
  ///
  /// Deliberately the same number as [compact]: `compact` names the ceiling
  /// of the phone range, `medium` the floor of the tablet range. Call sites
  /// read better for having both names, and `mana_breakpoints_test.dart`
  /// pins them together so they cannot silently drift apart later.
  static const medium = 600.0;

  /// A desk. Wide enough for a nav rail beside content, and for the ledger
  /// table's columns to be read across without crowding.
  static const expanded = 1024.0;

  /// Which width class a viewport falls into.
  static ManaWidthClass of(double width) => width >= expanded
      ? ManaWidthClass.expanded
      : width >= medium
          ? ManaWidthClass.medium
          : ManaWidthClass.compact;
}

/// Which of the three layouts a viewport gets.
///
/// Named for what the space affords rather than for a device, because the same
/// browser window changes class when somebody drags its edge — and a tablet in
/// portrait is a phone-shaped space regardless of what it is called.
enum ManaWidthClass { compact, medium, expanded }

/// Routes that have been laid out for a wide window and must NOT be clamped.
///
/// Empty on purpose. Plan 2 adds a path here as each of the five workflows
/// becomes genuinely responsive — so a screen is only ever let out of the
/// column once somebody has laid it out and tested it at that width.
///
/// Mutable rather than const because the widget test needs to add and remove
/// an entry; nothing in the app writes to it at runtime.
final Set<String> kManaWideRoutes = <String>{};

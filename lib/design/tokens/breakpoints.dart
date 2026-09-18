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

  /// A desk. Wide enough for a nav rail beside content, and for a
  /// multi-column layout to be read across without crowding.
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
/// Filled by Plan 2a Task 4, as each workflow became genuinely responsive —
/// a screen is only ever let out of the column once somebody has laid it out
/// and tested it at that width. `/ow-017`, `/ag-010` and `/ow-017-statement`
/// joined that way: both history screens gained a desk-width table layout,
/// and the statement screen a two-column filter grid.
///
/// Plan 3a Task 1 removed all three. The owner decided the website shows
/// accounts, not transaction history, so the desk-width history layout has
/// no consumer and was deleted along with the two routes that reached it and
/// the statement route that hung off `/ow-017`. `/ow-013` (Account Review)
/// is the one survivor: it renders no history view, so it carried none of
/// the pairing concern above — its own card grid (2 columns at medium, 3 at
/// expanded) is self-contained inside `ow_013_account_review.dart`.
///
/// Mutable rather than const because the widget test needs to add and remove
/// an entry; nothing in the app writes to it at runtime.
/// Two more joined on 2026-09-18, and for a different reason than the rest.
///
/// `/ow-013` earned its place by being converted: somebody laid out a screen
/// that already existed. `/web-home` and `/ow-bulk-onboarding-menu` were
/// DRAWN for a desk and never belonged in the column at all. The web home is
/// the only screen the web build has that Android does not, and the bulk
/// onboarding menu exists precisely because the Owner said the work is too
/// messy on a phone -- clamping either to 480px produced the thing they
/// described on seeing it: "it looks like a mobile device screen", a
/// navigation rail meant for 1024px squeezed beside a 350px column, both
/// floating in the middle of an empty 1920px window.
///
/// The bar has not moved. A route still only gets out once its screen has a
/// layout for the width, and both of these have one plus a test at desk size.
final Set<String> kManaWideRoutes = <String>{
  '/ow-013',
  '/web-home',
  '/ow-bulk-onboarding-menu',
};

/// How wide the reading measure may get on a desk, once a screen is out of
/// [kManaWideRoutes].
///
/// Letting go of the 480px column is not the same as having none: a form or a
/// card grid run edge to edge across a 2560px monitor is its own kind of
/// unreadable, and the eye loses the start of the next line. 1200 is about
/// three comfortable card columns plus gutters.
const kManaDeskContentMax = 1200.0;

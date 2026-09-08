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
/// Filled by Plan 2a Task 4, as each workflow becomes genuinely responsive —
/// a screen is only ever let out of the column once somebody has laid it out
/// and tested it at that width. `/ow-017` and `/ag-010` arrive together: both
/// render `ManaLedgerHistoryView`, which now branches to a ManaLedgerTable at
/// `expanded` width, so leaving one route in the set without the other would
/// give the Owner a table the Agent was never laid out for, or the reverse.
///
/// A third `ManaLedgerHistoryView` build site exists — OW-002 (Workforce
/// Management) opens one agent's ledger via a raw `Navigator.push`, not a
/// GoRouter route — and it is DELIBERATELY absent here, not an omission: it
/// has no route path of its own to add (GoRouter's `currentLocation()` keeps
/// reporting `/ow-002` while it is pushed), and `/ow-002` itself is not in
/// this set, so `ManaWebFrame` keeps clamping it to 480. Because the view
/// branches on `LayoutBuilder` constraints rather than `MediaQuery` (see
/// `ManaLedgerHistoryView`'s doc comment), that clamp is what keeps this
/// third call site rendering the card list correctly with no special case.
///
/// Mutable rather than const because the widget test needs to add and remove
/// an entry; nothing in the app writes to it at runtime.
/// `/ow-013` (Account Review) joined afterward, alone rather than paired: it
/// renders no `ManaLedgerHistoryView`, so it carries none of the pairing
/// concern above — its own card grid (2 columns at medium, 3 at expanded)
/// is self-contained inside `ow_013_account_review.dart` and has no sibling
/// screen sharing the same widget to keep in step with.
///
/// `/ow-017-statement` joined afterward too, also alone: Task 5 gave
/// `ow_017_statement_screen.dart` a `ManaFormGrid` for its filter fields, but
/// the route itself was never added here, so `ManaWebFrame` kept clamping it
/// to 480 and the two-column path never ran outside `mana_form_grid_test.dart`'s
/// synthetic widgets. It is Owner-only (reached from `/ow-017`'s statement
/// action) with no Agent counterpart, so it carries none of the `/ow-017`
/// pairing concern either.
final Set<String> kManaWideRoutes = <String>{
  '/ow-017',
  '/ag-010',
  '/ow-013',
  '/ow-017-statement',
};

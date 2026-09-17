import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'mana_fit_text.dart';

/// The app bar, for every screen that has one.
///
/// There were 79 of them across 65 files, each assembling its own — and 30
/// carried a hand-written `BackButton(onPressed: () => context.go('/ow-001'))`.
/// Those were not a style choice. Navigation used `go()`, which REPLACES the
/// router stack, so there was frequently nothing to pop and each screen had to
/// name its own way home. When one of them named the wrong home, or forgot,
/// nobody noticed until an Agent ended up on the Owner's dashboard.
///
/// The rule lives here now: pop what is there, and fall back to [homeRoute]
/// only when there is nothing. Screens state where home is; they do not
/// implement going there.
///
/// Deliberately thin. A title, what to do with back, actions, and a bottom
/// slot for the handful of screens with tabs or a filter row. Anything a
/// screen wants beyond that belongs in its body, not in the chrome.
class ManaAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// The standard trailing actions -- notifications, add expense, search --
  /// which every Owner and Agent screen carries and no screen assembles.
  ///
  /// A FUNCTION POINTER, set once by the app layer at startup, because those
  /// three actions read app state (the inbox count, the current session's
  /// business) and this is the design layer. A component library that knows
  /// about membership requests is no longer a component library -- the same
  /// reason ManaNotificationBell lives in shared/ rather than here.
  ///
  /// It is given the route it is drawing on, and answers with nothing for the
  /// routes that have no workspace behind them: login and registration, and
  /// the customer and investor workspaces, where there is no business to
  /// record an expense against.
  ///
  /// Null until set, so a bar drawn in a test or the design showcase is
  /// simply a bar.
  static List<Widget> Function(BuildContext context, String location)?
      trailingActionsBuilder;

  /// Already translated. This takes a String rather than a key so a screen can
  /// title itself with a customer's name as easily as with a label.
  ///
  /// Null for a bar that carries no title -- an OTP screen is its own
  /// heading, and repeating it in the chrome says nothing.
  final String? title;

  /// False suppresses the back arrow outright, even when the route could be
  /// popped.
  ///
  /// This is not the same as leaving [homeRoute] null, and the difference is
  /// load-bearing: LR-008 creates a PIN and has no back BY SPEC, because
  /// backing out of it leaves an account without one. An implicit arrow would
  /// hand somebody that exit.
  final bool implyLeading;

  /// Where back goes when the stack is empty — a browser refresh, a deep link,
  /// or a `go()` that replaced everything.
  ///
  /// Null does NOT mean "no arrow". It means this bar names no destination,
  /// and AppBar's own rule then applies: an arrow when the route can be
  /// popped, none when it cannot. That is what a root screen gets, and it is
  /// also why a screen with an implicit arrow today converts to this widget
  /// unchanged. (An earlier version of this comment said "no back arrow is
  /// drawn at all", which is only true of a route with nothing behind it.)
  final String? homeRoute;

  /// Back does something other than leave: unwinding a wizard step, warning
  /// about unsaved work, handing control to a parent that owns the stack.
  ///
  /// Takes precedence over [homeRoute]. A screen that wants both should do
  /// its own popping inside the callback -- if this widget popped first, the
  /// callback would run against a screen already gone.
  final VoidCallback? onBack;

  /// Only for a bar that is deliberately not the app's chrome -- a camera
  /// surface, a support workspace that is not a lending workspace. Passing
  /// these on an ordinary screen is how a design system stops being one.
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Passed as `extra` to [homeRoute]. Every workspace home needs a
  /// businessId to render anything.
  final Object? homeExtra;

  /// Overridable only for tests — the real value is always [kIsWeb]. A
  /// static tear-off rather than `() => kIsWeb` inline because a default
  /// parameter value must be a compile-time constant (same pattern as
  /// `ManaWebFrame.isWeb`).
  ///
  /// [homeRoute] is a dashboard route (`/ow-001`, `/cw-001`, …) that
  /// `manaWebRouter` never registers — Plan 3a's web build has no
  /// workspace dashboards, only `/web-home`. Every one of the ~30 screens
  /// that pass a `homeRoute` would dead-end into the web router's
  /// errorBuilder the moment its stack is empty and the fallback fires.
  /// Branching here, once, is what makes the fix apply to all of them
  /// without editing each call site — and each call site staying wrong is
  /// exactly the failure mode CLAUDE.md warns about for a shared widget.
  final bool Function() isWeb;

  /// Extra, screen-specific actions.
  ///
  /// On an Owner or Agent screen these come BEFORE the standard three
  /// (notifications, add expense, search), which the screen does not assemble
  /// -- see [manaWorkspaceActions]. A header that each screen fills in for
  /// itself is how this app ended up with 79 different bars.
  final List<Widget> actions;

  /// Tabs, a search field, a filter row. Supply [bottomHeight] with it.
  final PreferredSizeWidget? bottom;

  const ManaAppBar({
    super.key,
    this.title,
    this.implyLeading = true,
    this.homeRoute,
    this.homeExtra,
    this.onBack,
    this.backgroundColor,
    this.foregroundColor,
    this.actions = const [],
    this.bottom,
    this.isWeb = _realIsWeb,
  });

  static bool _realIsWeb() => kIsWeb;

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  /// The standard three, for the route this bar is drawing on.
  ///
  /// Guarded: a bar rendered outside a GoRoute -- the design showcase, a
  /// widget test that pumps a screen bare -- has no location to ask about,
  /// and chrome must never be the thing that takes a screen down.
  List<Widget> _trailing(BuildContext context) {
    final builder = trailingActionsBuilder;
    if (builder == null) return const [];
    try {
      return builder(context, GoRouterState.of(context).uri.path);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      // ONE LINE, AND IT SHRINKS. An AppBar has a fixed toolbarHeight, so a
      // second row is not available here the way it is in a list -- which is
      // why this ellipsised and why the handset read "Workforce Ma...".
      //
      // A harder floor than the default for that reason: 0.7, because the
      // alternative on this widget is not another line, it is dots on a
      // screen title. "Agent Management" at 0.7 fits a 360dp bar with the
      // four actions beside it at every scale this app tests.
      automaticallyImplyLeading: implyLeading,
      title: title == null
          ? null
          : ManaFitText(title!, maxLines: 1, minScale: 0.7),
      leading: onBack != null
          ? BackButton(onPressed: onBack)
          : homeRoute == null
          ? null
          : BackButton(
              onPressed: () {
                // Pop first. The fallback is for when there is genuinely
                // nothing behind this screen -- it is not the normal path.
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else if (isWeb()) {
                  // homeRoute names an Android dashboard (/ow-001, /cw-001,
                  // ...) that manaWebRouter never registers -- every one of
                  // these would land on the "screen lives in the app"
                  // error screen instead of home. /web-home is the only
                  // destination the web build actually has.
                  context.go('/web-home');
                } else {
                  context.go(homeRoute!, extra: homeExtra);
                }
              },
            ),
      actions: [...actions, ..._trailing(context)],
      bottom: bottom,
    );
  }
}

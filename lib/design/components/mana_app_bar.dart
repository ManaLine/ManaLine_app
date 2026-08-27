import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'mana_text.dart';

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
  });

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      // One line, and it may be a person's name, so it ellipsizes rather than
      // wrapping the bar to two rows at a large text scale.
      automaticallyImplyLeading: implyLeading,
      title: title == null
          ? null
          : ManaText.raw(title!, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                } else {
                  context.go(homeRoute!, extra: homeExtra);
                }
              },
            ),
      actions: actions,
      bottom: bottom,
    );
  }
}

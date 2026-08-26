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
  final String title;

  /// Where back goes when the stack is empty — a browser refresh, a deep link,
  /// or a `go()` that replaced everything. Null means this screen is a root:
  /// no back arrow is drawn at all.
  final String? homeRoute;

  /// Passed as `extra` to [homeRoute]. Every workspace home needs a
  /// businessId to render anything.
  final Object? homeExtra;

  final List<Widget> actions;

  /// Tabs, a search field, a filter row. Supply [bottomHeight] with it.
  final PreferredSizeWidget? bottom;

  const ManaAppBar({
    super.key,
    required this.title,
    this.homeRoute,
    this.homeExtra,
    this.actions = const [],
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // One line, and it may be a person's name, so it ellipsizes rather than
      // wrapping the bar to two rows at a large text scale.
      title: ManaText.raw(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: homeRoute == null
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

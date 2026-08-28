/// The app shell: one Scaffold that carries the navigation drawer and the
/// identity header every workspace screen sits under.
///
/// WHY THIS IS A COMPONENT: before this, there was no `Drawer` anywhere in the
/// app — all 57 screens reached each other through quick-action grids and the
/// back stack, so "go to Workforce from a customer screen" meant unwinding to a
/// dashboard first. Putting the drawer in one place is the only way it stays
/// the same drawer on every screen; the previous attempt at consistent
/// navigation (ManaHeaderBlock) drifted the moment screens hand-rolled AppBars
/// around it.
///
/// LAYOUT DECISION, and it is load-bearing: the header is ONE row —
/// menu, the business name, then the workspace's own [actions] (search,
/// notifications).
///
/// It used to be two rows: identity + actions above, then the date/clock and
/// Settings / Switch / Logout below. Both rows were then stacked under the
/// dashboards' own ManaHeaderBlock, so a phone gave up roughly a third of its
/// height to chrome before showing a single number. Everything that made the
/// second row has moved into the drawer, which is where a rarely-used global
/// control belongs and where there is vertical room for it: the clock now sits
/// under the business name in the drawer header, and Settings / Switch /
/// Logout are drawer rows.
///
/// The clock comes from `manaClock12*()`, never `DateTime.now()` — a header
/// showing a different day from the one the database stamps rows with reads as
/// the app being wrong about the business day.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../../shared/mana_time.dart';
import '../../shared/translation_service.dart';
import 'mana_text.dart';
import 'mana_header.dart' show kManaMinTapTarget;

/// One expandable group in the drawer — "Customers", "Workforce", "Investors".
///
/// The sections are supplied by the caller rather than hardcoded here because
/// the drawer is shared by all four workspaces and an Agent's "Customers" is
/// not an Owner's: same label, different destinations and different
/// permissions. Hardcoding the Owner's set would put dead rows in the other
/// three drawers.
class ManaDrawerSection {
  final IconData icon;

  /// Translation key — passed through [ManaText], so it obeys the locked Title
  /// Case standard like every other label.
  final String labelKey;
  final List<ManaDrawerAction> actions;

  /// Set INSTEAD of [actions] for a row that is a destination in its own
  /// right rather than a group — Profile and Logout, which have nothing
  /// beneath them. Rendered as a plain tile, so it acts on the first tap;
  /// giving it a chevron that opens a list containing only itself would be
  /// two taps to do one thing.
  final VoidCallback? onTap;

  const ManaDrawerSection({
    required this.icon,
    required this.labelKey,
    this.actions = const [],
    this.onTap,
  });

  /// No children — render as a plain tile. A leaf with a null [onTap] is
  /// legitimate: it shows disabled, which is how this drawer has always
  /// signalled "exists, not yours" rather than hiding the row.
  bool get isLeaf => actions.isEmpty;
}

/// One destination inside a [ManaDrawerSection].
class ManaDrawerAction {
  final String labelKey;

  /// Null renders the row disabled rather than hiding it, so a permission the
  /// user does not have reads as "not yours" instead of the row silently not
  /// existing — a missing row looks like a bug to someone who has seen it on a
  /// colleague's phone.
  final VoidCallback? onTap;

  const ManaDrawerAction({required this.labelKey, this.onTap});
}

/// The global rows every workspace's drawer ends with — Profile, Switch
/// Workspace, Switch Role, Settings, Logout, in that order.
///
/// These used to be icons in the header's second row (Settings / Switch /
/// Logout) plus, on the Owner dashboard, a separate overflow menu. Both are
/// gone; the drawer is now the single place a global control lives, and this
/// helper is what stops the four workspaces from each inventing their own
/// order and labels for the same five things.
///
/// A null callback renders the row disabled rather than dropping it — same
/// reasoning as [ManaDrawerAction.onTap].
List<ManaDrawerSection> manaGlobalDrawerSections({
  VoidCallback? onProfile,
  VoidCallback? onSwitchWorkspace,
  VoidCallback? onSwitchRole,
  VoidCallback? onSettings,
  VoidCallback? onLogout,
}) {
  return [
    ManaDrawerSection(
      icon: Icons.person_outline,
      labelKey: 'profile',
      onTap: onProfile,
    ),
    ManaDrawerSection(
      icon: Icons.swap_horiz,
      labelKey: 'switch_workspace',
      onTap: onSwitchWorkspace,
    ),
    ManaDrawerSection(
      icon: Icons.badge_outlined,
      labelKey: 'switch_role',
      onTap: onSwitchRole,
    ),
    ManaDrawerSection(
      icon: Icons.settings_outlined,
      labelKey: 'settings',
      onTap: onSettings,
    ),
    ManaDrawerSection(
      icon: Icons.logout,
      labelKey: 'logout',
      onTap: onLogout,
    ),
  ];
}

class ManaAppShell extends StatelessWidget {
  /// Shown as the header's main line. Passed in rather than read from a
  /// provider so the shell never reaches the network — the same reason the
  /// test harness seeds providers instead of letting screens fetch in
  /// initState.
  final String userName;

  /// Shown beneath [userName]. Null before a business is selected (the
  /// business selector and role selector both sit above that point).
  final String? businessName;

  final List<ManaDrawerSection> sections;

  /// Optional business logo, shown between the menu button and the identity
  /// block. Sized and clipped here.
  final Widget? leading;

  /// The screen's OWN header controls — search, notifications. These are the
  /// only icons left in the header; Settings / Switch / Logout used to sit
  /// beside them and are drawer rows now (see [sections]).
  ///
  /// Use `ManaHeaderAction` so the 48dp target and the accessible name cannot
  /// be forgotten.
  final List<Widget> actions;

  final Widget body;

  /// Optional bottom navigation, passed straight through to the Scaffold.
  final Widget? bottomNavigationBar;

  final Widget? floatingActionButton;

  /// Injected in tests so the rendered clock is deterministic. Production
  /// leaves it null and reads the IST wall clock.
  final DateTime? now;

  /// Second line under the business name — the day and date. Lives in the
  /// header rather than in a second block below it; see [_ShellHeader].
  final String? subtitle;

  /// Tapping the logo. Null leaves it inert.
  final VoidCallback? onLeadingTap;

  const ManaAppShell({
    super.key,
    required this.userName,
    required this.body,
    this.businessName,
    this.subtitle,
    this.sections = const [],
    this.leading,
    this.onLeadingTap,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _ManaDrawer(
        userName: userName,
        businessName: businessName,
        sections: sections,
        now: now,
      ),
      body: Column(
        children: [
          _ShellHeader(
            businessName: businessName,
            userName: userName,
            subtitle: subtitle,
            leading: leading,
            onLeadingTap: onLeadingTap,
            actions: actions,
          ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// THE header. Not "the top one of two".
///
/// Screens used to draw their own ManaHeaderBlock immediately under this
/// bar, so the business name, the logo and the date appeared twice, one
/// row apart, in two different colours — see the OW-001 screenshots that
/// prompted this. Everything those blocks carried now lives here:
/// [leading] takes the business logo, [subtitle] the day and date, and
/// [actions] the notification and search buttons. One bar, one truth.
class _ShellHeader extends StatelessWidget {
  /// The header's title line. Falls back to [userName] before a business is
  /// chosen, so the bar is never anonymous.
  final String? businessName;
  final String userName;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onLeadingTap;
  final List<Widget> actions;

  const _ShellHeader({
    required this.businessName,
    required this.userName,
    required this.subtitle,
    required this.leading,
    required this.onLeadingTap,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // brandDeep, not brand: this block carries small white text, and white on
      // brand is 4.51:1 — too thin to read outdoors in sunlight.
      color: ManaColors.brandDeep,
      padding: EdgeInsets.only(
        // Tight: the header is chrome on the screen somebody looks at most,
        // and every dp here is one the dashboard does not get.
        top: MediaQuery.paddingOf(context).top + ManaSpacing.xs,
        left: ManaSpacing.sm,
        right: ManaSpacing.sm,
        bottom: ManaSpacing.xs,
      ),
      // One row, and the name is allowed two lines inside it.
      //
      // This was one row, then two, and is one again -- worth writing down.
      // Everything on a single line meant the name was the only thing that
      // could be shortened, so "Sri Satyanarayana Bus..." was what the screen
      // said. Moving the icons to a second row fixed that and cost a whole
      // row of height on the screen somebody looks at most.
      //
      // A name that WRAPS needs neither. The icons keep the first line, the
      // name takes up to two lines beside them, and the date sits under it in
      // the same column -- roughly half the height of the two-row version and
      // still no ellipsis until a name runs past two lines.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Builder, because opening the drawer needs a context BELOW the
          // Scaffold — `Scaffold.of(context)` at the shell's own level
          // finds the parent route's Scaffold, or throws.
          Builder(
            builder: (inner) => _ShellIcon(
              icon: Icons.menu,
              label: 'Menu',
              onPressed: () => Scaffold.of(inner).openDrawer(),
            ),
          ),
          if (leading != null) ...[
            Semantics(
              button: onLeadingTap != null,
              label: onLeadingTap != null ? 'Business Profile' : null,
              child: InkWell(
                onTap: onLeadingTap,
                borderRadius: BorderRadius.circular(ManaRadius.ring),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ManaRadius.ring),
                  child: SizedBox(width: 28, height: 28, child: leading),
                ),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    (businessName != null && businessName!.isNotEmpty)
                        ? businessName!
                        : userName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // 15, not 16: two lines of a long name at 16 pushed the
                      // header taller than the single row it replaced.
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: ManaColors.textOnDark,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: ManaColors.textOnDark,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _ShellIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ShellIcon({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      // The Semantics below is the single accessible name; left on, the tooltip
      // publishes its own node and the label is announced twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ManaRadius.ring),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kManaMinTapTarget,
              minHeight: kManaMinTapTarget,
            ),
            child: Icon(
              icon,
              size: 22,
              color: onPressed == null
                  ? ManaColors.textOnDark.withValues(alpha: 0.4)
                  : ManaColors.textOnDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _ManaDrawer extends ConsumerStatefulWidget {
  final String userName;
  final String? businessName;
  final List<ManaDrawerSection> sections;
  final DateTime? now;

  const _ManaDrawer({
    required this.userName,
    required this.businessName,
    required this.sections,
    required this.now,
  });

  @override
  ConsumerState<_ManaDrawer> createState() => _ManaDrawerState();
}

class _ManaDrawerState extends ConsumerState<_ManaDrawer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Only runs while the drawer is on screen: Flutter's DrawerController
    // does not build its child while the drawer is closed, so this State is
    // created on open and disposed on close. That is the whole reason the
    // seconds field is affordable — a clock ticking behind every screen
    // would be a rebuild per second for something nobody is looking at.
    //
    // Skipped entirely when `now` is injected, so tests stay deterministic
    // and do not leave a live timer running past the test.
    if (widget.now == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userName;
    final businessName = widget.businessName;
    final sections = widget.sections;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              color: ManaColors.brandDeep,
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ManaColors.textOnDark,
                    ),
                  ),
                  if (businessName != null)
                    Text(
                      businessName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: ManaColors.textOnDark,
                        height: 1.3,
                      ),
                    ),
                  // The date and IST clock, moved out of the header. Seconds
                  // are shown because this one actually ticks — see the
                  // timer in initState.
                  const SizedBox(height: ManaSpacing.xs),
                  Text(
                    '${manaDisplayDateWithWeekday(widget.now)}  •  '
                    '${manaClock12WithSeconds(widget.now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: ManaColors.textOnDark,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            for (final s in sections)
              if (s.isLeaf)
                // A destination, not a group — Profile, Logout. Plain tile so
                // one tap does the thing.
                ListTile(
                  leading: Icon(s.icon, color: ManaColors.brandDeep),
                  title: ManaText(ref.t(s.labelKey)),
                  enabled: s.onTap != null,
                  onTap: s.onTap == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          s.onTap!();
                        },
                )
              else
                ExpansionTile(
                  leading: Icon(s.icon, color: ManaColors.brandDeep),
                  title: ManaText(ref.t(s.labelKey)),
                  // Every child is a full-width tile rather than an indented
                  // label, so the tap target stays the row.
                  children: [
                    for (final a in s.actions)
                      ListTile(
                        // Indent only the content, so the row itself — and
                        // its tap target — still spans the drawer.
                        contentPadding: const EdgeInsets.only(
                          left: ManaSpacing.xl,
                          right: ManaSpacing.lg,
                        ),
                        title: ManaText(ref.t(a.labelKey)),
                        enabled: a.onTap != null,
                        onTap: a.onTap == null
                            ? null
                            : () {
                                // Close the drawer before navigating, or it
                                // stays mounted over the destination and the
                                // next Back dismisses the drawer instead of
                                // the screen.
                                Navigator.of(context).pop();
                                a.onTap!();
                              },
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

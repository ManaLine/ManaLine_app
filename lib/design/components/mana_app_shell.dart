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
/// LAYOUT DECISION, and it is load-bearing: the spec reads "right = date
/// dd-mm-yyyy and IST 12-hour time, then Settings / Switch / Logout". Rendered
/// literally, and with the dashboards' own notifications and search actions
/// added, that is a menu button, a logo, a two-line name block, a two-line date
/// block and five icon buttons in one Row — well past 360dp before any text
/// scaling, and overflow is this codebase's most-shipped bug class (five
/// times). So the header is two rows:
///
///   1. menu, optional logo, identity, and the workspace's own [actions]
///      (notifications, search — the things that belong to the screen);
///   2. the date and IST clock on the left, then Settings / Switch / Logout on
///      the right.
///
/// That keeps the spec's grouping — date/time and the three global controls
/// together, away from the per-screen actions — and fits at 2.0x.
///
/// The clock comes from `manaClock12()`, never `DateTime.now()` — a header
/// showing a different day from the one the database stamps rows with reads as
/// the app being wrong about the business day.
library;

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

  const ManaDrawerSection({
    required this.icon,
    required this.labelKey,
    required this.actions,
  });
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

  /// The screen's OWN header controls — notifications, search. Kept separate
  /// from Settings/Switch/Logout because those three are global and belong on
  /// the second row; mixing them put five icons in one row.
  ///
  /// Use `ManaHeaderAction` so the 48dp target and the accessible name cannot
  /// be forgotten.
  final List<Widget> actions;

  final VoidCallback? onSettings;

  /// Switch workspace / role.
  final VoidCallback? onSwitch;

  final VoidCallback? onLogout;

  final Widget body;

  /// Optional bottom navigation, passed straight through to the Scaffold.
  final Widget? bottomNavigationBar;

  final Widget? floatingActionButton;

  /// Injected in tests so the rendered clock is deterministic. Production
  /// leaves it null and reads the IST wall clock.
  final DateTime? now;

  const ManaAppShell({
    super.key,
    required this.userName,
    required this.body,
    this.businessName,
    this.sections = const [],
    this.leading,
    this.actions = const [],
    this.onSettings,
    this.onSwitch,
    this.onLogout,
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
      ),
      body: Column(
        children: [
          _ShellHeader(
            userName: userName,
            businessName: businessName,
            leading: leading,
            actions: actions,
            onSettings: onSettings,
            onSwitch: onSwitch,
            onLogout: onLogout,
            now: now,
          ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _ShellHeader extends StatelessWidget {
  final String userName;
  final String? businessName;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onSettings;
  final VoidCallback? onSwitch;
  final VoidCallback? onLogout;
  final DateTime? now;

  const _ShellHeader({
    required this.userName,
    required this.businessName,
    required this.leading,
    required this.actions,
    required this.onSettings,
    required this.onSwitch,
    required this.onLogout,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // brandDeep, not brand: this block carries small white text, and white on
      // brand is 4.51:1 — too thin to read outdoors in sunlight.
      color: ManaColors.brandDeep,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + ManaSpacing.sm,
        left: ManaSpacing.sm,
        right: ManaSpacing.sm,
        bottom: ManaSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(ManaRadius.ring),
                  child: SizedBox(width: 32, height: 32, child: leading),
                ),
                const SizedBox(width: ManaSpacing.sm),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ManaColors.textOnDark,
                        ),
                      ),
                      if (businessName != null)
                        Text(
                          businessName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            // Not a dimmed white — at 13sp on blue, opacity
                            // drops this under the contrast floor.
                            color: ManaColors.textOnDark,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              ...actions,
            ],
          ),
          // Second row: clock, then the three global controls. See the layout
          // note at the top of this file for why these are not in row one.
          Row(
            children: [
              // Expanded, not a bare Text: at 2.0x the date string alone is
              // wider than the space left beside three 48dp buttons, and an
              // unflexible child beside flexible siblings is the exact shape
              // that has overflowed here five times.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: ManaSpacing.xs),
                  child: Text(
                    '${manaDisplayDate(now)}  •  ${manaClock12(now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: ManaColors.textOnDark,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              _ShellIcon(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onPressed: onSettings),
              _ShellIcon(
                  icon: Icons.swap_horiz,
                  label: 'Switch Workspace Or Role',
                  onPressed: onSwitch),
              _ShellIcon(
                  icon: Icons.logout, label: 'Logout', onPressed: onLogout),
            ],
          ),
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

class _ManaDrawer extends ConsumerWidget {
  final String userName;
  final String? businessName;
  final List<ManaDrawerSection> sections;

  const _ManaDrawer({
    required this.userName,
    required this.businessName,
    required this.sections,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      businessName!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: ManaColors.textOnDark,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
            for (final s in sections)
              ExpansionTile(
                leading: Icon(s.icon, color: ManaColors.brandDeep),
                title: ManaText(ref.t(s.labelKey)),
                // Every child is a full-width tile rather than an indented
                // label, so the tap target stays the row.
                children: [
                  for (final a in s.actions)
                    ListTile(
                      // Indent only the content, so the row itself — and its
                      // tap target — still spans the drawer.
                      contentPadding: const EdgeInsets.only(
                        left: ManaSpacing.xl,
                        right: ManaSpacing.lg,
                      ),
                      title: ManaText(ref.t(a.labelKey)),
                      enabled: a.onTap != null,
                      onTap: a.onTap == null
                          ? null
                          : () {
                              // Close the drawer before navigating, or it stays
                              // mounted over the destination and the next Back
                              // dismisses the drawer instead of the screen.
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

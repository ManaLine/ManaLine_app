/// PhonePe-style coloured header block, plus the quick-action grid and bottom
/// navigation that go with it.
///
/// WHY THESE ARE COMPONENTS: 50 screens each hand-rolled their own `AppBar`,
/// and bottom navigation existed in only 2 of the 4 workspaces — so "consistent
/// navigation patterns" was not achievable by editing screens one at a time.
/// It has to live in one place or it drifts again with the next screen someone
/// adds.
///
/// ACCESSIBILITY DECISIONS BAKED IN HERE, not left to call sites:
///  * Every tappable thing is at least 48dp — the Material minimum, and the
///    realistic minimum for a thumb on a dusty screen while standing up.
///  * Every icon-only control carries a semantic label. 20 of 36 IconButtons
///    in this app had neither tooltip nor label, so screen readers announced
///    them as unlabelled buttons.
///  * The header uses brandDeep, not brand, because it carries small white
///    text — white on brand is 4.51:1, too thin outdoors; on brandDeep it is
///    7.18:1.
///  * Nothing here relies on colour alone: the selected nav item changes icon
///    fill AND weight AND colour, so it survives colour-vision deficiency and
///    greyscale.
library;

import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../motion.dart';

/// Minimum interactive size. Material specifies 48dp; this app's users are
/// often standing, one-handed, in a hurry, sometimes with wet or dusty hands,
/// so it is treated as a hard floor rather than a guideline.
const double kManaMinTapTarget = 48.0;

/// A coloured header block that scrolls with the content rather than sitting in
/// a fixed AppBar — the PhonePe pattern. Carries identity (who/where you are)
/// and optionally a hero figure, then hands off to the page body.
///
/// Prefer this over `AppBar` on dashboard-style screens. Keep `AppBar` for
/// leaf/detail screens, where a conventional back-titled bar is the more
/// predictable affordance.
class ManaHeaderBlock extends StatelessWidget {
  /// Main line — business name, customer name, screen identity.
  final String title;

  /// Supporting line — MLID, status, role.
  final String? subtitle;

  /// Optional leading avatar/logo. Sized and clipped by this widget.
  final Widget? leading;

  /// Trailing controls. Each is forced to the 48dp minimum and must carry its
  /// own semantic label — use [ManaHeaderAction] rather than a bare IconButton.
  final List<Widget> actions;

  /// Optional content below the identity row, inside the coloured area —
  /// typically a hero amount, or a status strip.
  final Widget? child;

  const ManaHeaderBlock({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      // The block is dark, so everything inside it draws light. Stated once
      // here rather than by each action hardcoding a colour -- the same
      // actions now also sit in a light ManaAppBar.
      data: IconThemeData(color: ManaColors.textOnDark),
      child: _block(context),
    );
  }

  Widget _block(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ManaColors.brandDeep,
      padding: EdgeInsets.only(
        // Respect the notch/status bar without a second SafeArea nesting.
        top: MediaQuery.paddingOf(context).top + ManaSpacing.md,
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        bottom: ManaSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(ManaRadius.ring),
                  child: SizedBox(width: 40, height: 40, child: leading),
                ),
                const SizedBox(width: ManaSpacing.md),
              ],
              Expanded(
                // Header identity is a heading for assistive tech, so a
                // screen reader can jump straight to it.
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ManaColors.textOnDark,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            // Not a dimmed white: at 13sp on blue, opacity
                            // would push this under the contrast floor.
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
          if (child != null) ...[
            const SizedBox(height: ManaSpacing.lg),
            child!,
          ],
        ],
      ),
    );
  }
}

/// An icon control for [ManaHeaderBlock]. Exists so the 48dp target and the
/// semantic label cannot be forgotten — both are required parameters in
/// practice, because `label` has no default.
class ManaHeaderAction extends StatelessWidget {
  final IconData icon;

  /// Spoken by screen readers and shown as a long-press tooltip. Describe the
  /// ACTION ("Notifications", "Search customers"), not the glyph.
  final String label;
  final VoidCallback? onPressed;

  /// Optional count badge — notifications, pending items.
  final int? badgeCount;

  /// Draws the glyph heavier. For the one action in a bar that CREATES
  /// something, so it separates at a glance from the ones that only look
  /// things up.
  final bool bold;

  const ManaHeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badgeCount,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeCount != null && badgeCount! > 0;
    return Tooltip(
      message: label,
      // Tooltip publishes its own semantics node containing `message`. Left on,
      // a screen reader announces the label twice — once from the tooltip and
      // once from the Semantics below — and the badge count gets separated from
      // the name it belongs to. The Semantics wrapper here is the single source
      // of the accessible name; the tooltip stays purely visual (long-press for
      // sighted users who don't recognise the glyph).
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: showBadge ? '$label, $badgeCount unread' : label,
        // Otherwise the badge's own Text('3') and the Icon contribute stray
        // nodes that fragment the announcement.
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ManaRadius.ring),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kManaMinTapTarget,
              minHeight: kManaMinTapTarget,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inherited, not hardcoded white.
                //
                // This drew textOnDark unconditionally, which is right inside
                // the coloured ManaHeaderBlock and invisible in a ManaAppBar,
                // whose background is surface. Now that these actions appear
                // in both, the colour comes from the surrounding IconTheme --
                // which AppBar sets from its foregroundColor, and which
                // ManaHeaderBlock sets to textOnDark below.
                Icon(
                  icon,
                  color: IconTheme.of(context).color ?? ManaColors.textOnDark,
                  size: 24,
                  weight: bold ? 700 : null,
                  grade: bold ? 200 : null,
                ),
                if (showBadge)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        // Amber badge with dark text: 8.0:1, and it reads as
                        // "attention" without borrowing the error colour for
                        // something that isn't an error.
                        color: ManaColors.accent,
                        borderRadius: BorderRadius.circular(ManaRadius.ring),
                      ),
                      child: Text(
                        badgeCount! > 99 ? '99+' : '$badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ManaColors.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tile in a [ManaActionGrid].
class ManaAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Small count/flag shown on the tile — e.g. pending approvals waiting.
  final int? badgeCount;

  const ManaAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount,
  });
}

/// The quick-action grid. Fixed 4-up on phones, widening on larger screens
/// rather than stretching tiles to absurd widths — that is the "predictable
/// across devices" part; a `Wrap` would reflow unpredictably between a 5"
/// phone and a tablet and move the tile a user's thumb has memorised.
class ManaActionGrid extends StatelessWidget {
  final List<ManaAction> actions;

  const ManaActionGrid({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 6
        : width >= 600
            ? 5
            : 4;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - (columns - 1) * ManaSpacing.sm) / columns;
        return Wrap(
          spacing: ManaSpacing.sm,
          runSpacing: ManaSpacing.md,
          children: [
            for (final a in actions)
              SizedBox(width: tileWidth, child: _ActionTile(action: a)),
          ],
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  final ManaAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final disabled = action.onTap == null;
    final showBadge = action.badgeCount != null && action.badgeCount! > 0;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: showBadge ? '${action.label}, ${action.badgeCount} pending' : action.label,
      excludeSemantics: true,
      // Press-scale rather than a ripple for tiles and cards. A ripple tells
      // you where you touched; a slight shrink of the whole surface tells you
      // the surface IS the button and that the tap registered — which matters
      // more outdoors, where a ripple can be almost invisible in sunlight.
      // Small controls (header icons, nav items) keep the ripple, since at
      // that size it's the expected affordance.
      child: ManaPressable(
        onTap: action.onTap,
        child: Padding(
          // Vertical padding plus the icon puck keeps the whole tile well over
          // the 48dp floor, so the tap area is the tile and not just the icon.
          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: kManaMinTapTarget,
                    height: kManaMinTapTarget,
                    decoration: BoxDecoration(
                      color: disabled ? ManaColors.surfaceSunken : ManaColors.brandFaint,
                      borderRadius: BorderRadius.circular(ManaRadius.md),
                    ),
                    child: Icon(
                      action.icon,
                      size: 24,
                      color: disabled ? ManaColors.textDisabled : ManaColors.brandDeep,
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: ManaColors.accent,
                          borderRadius: BorderRadius.circular(ManaRadius.ring),
                          border: Border.all(color: ManaColors.surface, width: 1.5),
                        ),
                        child: Text(
                          action.badgeCount! > 99 ? '99+' : '${action.badgeCount}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ManaColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: ManaSpacing.xs),
              Text(
                action.label,
                textAlign: TextAlign.center,
                // Two lines, because "Withdrawal Requests" cannot fit one line
                // at 13sp in a quarter-width tile — and truncating an action
                // label to "Withdrawal…" makes it ambiguous with other actions.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  color: disabled ? ManaColors.textDisabled : ManaColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One destination in [ManaBottomNav].
class ManaNavItem {
  final IconData icon;

  /// Filled counterpart of [icon], shown when selected. Selection is signalled
  /// by icon FILL, weight and colour together — never colour alone.
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  const ManaNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });
}

/// Shared bottom navigation. Bottom nav previously existed in only 2 of the 4
/// workspaces, which meant Customers and Investors had no persistent way home
/// — every journey was a back-stack unwind.
class ManaBottomNav extends StatelessWidget {
  final List<ManaNavItem> items;
  final int currentIndex;

  const ManaBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ManaColors.surface,
        border: Border(top: BorderSide(color: ManaColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(child: _NavButton(item: items[i], selected: i == currentIndex)),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final ManaNavItem item;
  final bool selected;

  const _NavButton({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = selected ? ManaColors.brandDeep : ManaColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        // No tap feedback or navigation on the current tab — re-navigating to
        // where you already are pushes a duplicate route and breaks Back.
        onTap: selected ? null : item.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kManaMinTapTarget + 8),
          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
          child: Column(
            // min, NOT the default max. Scaffold measures bottomNavigationBar
            // with LOOSE constraints — maxHeight is the whole screen — so a
            // mainAxisSize.max Column expanded to fill it and centred the icons
            // vertically. The nav bar became full-screen-tall with its content
            // floating in the middle, and the body was left with no height at
            // all, so the page rendered blank. Sizing to content is what keeps
            // the bar the height of a bar.
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.selectedIcon : item.icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  // Weight shift as well as colour, so selection is legible
                  // without relying on hue.
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

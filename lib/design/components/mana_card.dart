import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// A card in a list, with the rhythm and the padding already decided.
///
/// WHAT THIS IS NOT: a restyling of Card. `cardTheme` in theme.dart already
/// fixes colour, elevation, radius and border, and every Card in the app
/// already picks those up. Nothing about the chrome was drifting.
///
/// WHAT WAS DRIFTING is the boilerplate around it. 163 raw `Card(` sites, of
/// which 71 wrapped a `Padding` — 46 at `md`, 23 at `lg`, 2 at `sm` — and 23
/// set `margin: only(bottom: sm)` while 6 used `md` and a handful used ad-hoc
/// numbers like `top: 4` or `horizontal: 6`. So a list of cards had a slightly
/// different vertical rhythm depending on which screen you were on, and every
/// new card was three nested widgets of ceremony before the content.
///
/// [gap] is the space BELOW the card, because these stack downwards in a
/// ListView and the last one's trailing space is the list's own bottom padding
/// — not something each card should be arguing about.
class ManaCard extends StatelessWidget {
  final Widget child;

  /// Inner padding. `md` is the list-row default; `lg` suits a card that is
  /// the subject of its screen rather than one row among many.
  final double padding;

  /// Space below the card. The list rhythm.
  final double gap;

  /// Makes the whole card tappable, with the ripple clipped to the card's own
  /// radius — the detail hand-rolled InkWell-inside-Card usually gets wrong,
  /// leaving a square ripple bleeding past a rounded corner.
  final VoidCallback? onTap;

  const ManaCard({
    super.key,
    required this.child,
    this.padding = ManaSpacing.md,
    this.gap = ManaSpacing.sm,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: EdgeInsets.all(padding),
      child: child,
    );

    // The theme's shape drives the ink clip, so a card and its ripple can
    // never disagree about their corners.
    final shape = Theme.of(context).cardTheme.shape;

    return Card(
      margin: EdgeInsets.only(bottom: gap),
      child: onTap == null
          ? padded
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: padded,
            ),
    );
  }
}

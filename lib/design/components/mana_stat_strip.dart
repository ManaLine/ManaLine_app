/// A horizontally scrolling row of count-and-status cards — the summary strip
/// at the top of OW-002, OW-003, OW-006, AG-002 and AG-003.
///
/// WHY THIS EXISTS: those five screens each had their own copy of this widget,
/// identical apart from card width and value font size. All five wrapped the
/// list in `SizedBox(height: 84)`, and all five threw
/// "A RenderFlex overflowed by 6.0 pixels" the moment label text moved to the
/// 13sp legibility floor.
///
/// The instructive part is that raising 84 to a bigger number does not fix it.
/// A fixed pixel height wrapping scalable text is a latent overflow by
/// construction: whatever number you pick, a user raising their system font
/// size — which older Owners routinely do, and Android's slider plus
/// display-size scaling reach 2x — breaks it again. Even scaling the constant
/// by the text scaler is not enough, because a longer label ("Pending
/// Acceptance") wraps to a second line and adds height the constant knows
/// nothing about.
///
/// So this component has NO height at all. `IntrinsicHeight` measures the
/// tallest card and the strip becomes exactly that tall, at any text scale,
/// with any label. Overflow stops being tuned and becomes impossible.
///
/// Cost note: IntrinsicHeight requires a second layout pass over its children,
/// which is why it carries a general warning. With ~6 fixed-width cards, once
/// per build, that is measured in microseconds — the right trade for removing
/// a whole class of layout bug.
library;

import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_text.dart';

/// One cell: a headline value with a status label beneath it.
class ManaStat {
  /// Pre-formatted — callers pass counts as strings, or currency via their own
  /// formatter, so this component never guesses at formatting.
  final String value;
  final String label;
  final ManaStatus status;

  const ManaStat({required this.value, required this.label, required this.status});
}

class ManaStatStrip extends StatelessWidget {
  final List<ManaStat> stats;

  /// Card width. Wide enough by default that the app's longest status labels
  /// ("Pending Acceptance", "Pending Invitations") fit on one line — a wrapped
  /// label is legal here now, but it still looks worse than a wider card.
  final double cardWidth;

  /// Size of the headline value. Clamped to a 16sp floor by [_valueSize] — most
  /// of these strips carry currency, and three call sites were passing 15,
  /// which silently sat below the money legibility floor. Enforcing it here
  /// rather than trusting each caller is the whole reason this is a component.
  final double valueFontSize;

  const ManaStatStrip({
    super.key,
    required this.stats,
    this.cardWidth = 148,
    this.valueFontSize = 20,
  });

  double get _valueSize => valueFontSize < 16 ? 16 : valueFontSize;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          // stretch, so every card matches the tallest rather than floating at
          // different heights when one label wraps.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++)
              Padding(
                padding: EdgeInsets.only(right: i == stats.length - 1 ? 0 : ManaSpacing.sm),
                child: _StatCard(
                  stat: stats[i],
                  width: cardWidth,
                  valueFontSize: _valueSize,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final ManaStat stat;
  final double width;
  final double valueFontSize;

  const _StatCard({required this.stat, required this.width, required this.valueFontSize});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        width: width,
        padding: const EdgeInsets.all(ManaSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // min, not max: under stretch the card already fills the row's
          // height, and a max-size Column inside an intrinsic measurement pass
          // is what produced the original overflow.
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ManaText.raw(
              stat.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: valueFontSize,
                color: ManaColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            ManaStatusPill(label: stat.label, status: stat.status),
          ],
        ),
      ),
    );
  }
}

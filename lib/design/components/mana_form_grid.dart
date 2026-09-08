/// A form's fields, flowed into columns once there is room for them.
///
/// On a phone every filter/field stacks single-file — there is nowhere else
/// for it to go. A tablet or a desk has width to spare, and a form read as
/// one column across the whole window forces the eye down a needlessly tall
/// page. This widget is the shared answer: below [ManaWidthClass.medium] it
/// is a plain vertical stack; at or above it, children flow into
/// [columnsAtMedium] columns.
///
/// LAYOUT-ONLY, on purpose, same boundary as [ManaLedgerTable]: this widget
/// takes children already built by the caller and knows nothing about what a
/// field is — no [TextField], no validation, no label. That is what lets
/// OW-017's period filters and Plans 2b/2c/2e's forms share it without
/// sharing behaviour.
///
/// THE ORPHAN-CHILD DETAIL. A naive `Row`-per-line-of-N approach stretches a
/// lone last child (an odd count, or any count not divisible by the column
/// count) to fill the whole row width via `Expanded`, so it reads wider than
/// its row-mates — a grid that looks approximated rather than built. This
/// widget instead gives every child the SAME fixed width up front (the
/// window's width, minus the inter-column gaps, divided evenly by the column
/// count) and lets a `Wrap` place them — a `Wrap` never stretches a short
/// final row, so the last child keeps the same width as everything above it
/// with no special case for the remainder.
library;

import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/spacing.dart';

class ManaFormGrid extends StatelessWidget {
  final List<Widget> children;

  /// Columns used at [ManaWidthClass.medium] and [ManaWidthClass.expanded]
  /// alike — a form grid does not need a third tier the way the ledger
  /// table's column widths do; two columns already uses a desk's width well
  /// without crowding a tablet.
  final int columnsAtMedium;

  const ManaFormGrid({
    super.key,
    required this.children,
    this.columnsAtMedium = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // An unbounded incoming width (e.g. inside a horizontally-scrolling
        // ancestor) has no meaningful column width to divide by — fall back
        // to the single-column stack, the same as a compact viewport.
        final isCompact = !constraints.maxWidth.isFinite ||
            ManaBreakpoints.of(constraints.maxWidth) == ManaWidthClass.compact;
        final columns = isCompact ? 1 : columnsAtMedium.clamp(1, children.isEmpty ? 1 : children.length);

        if (columns <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: ManaSpacing.md),
                children[i],
              ],
            ],
          );
        }

        final totalGaps = ManaSpacing.lg * (columns - 1);
        final columnWidth = (constraints.maxWidth - totalGaps) / columns;

        return Wrap(
          spacing: ManaSpacing.lg,
          runSpacing: ManaSpacing.md,
          children: [
            for (final child in children)
              SizedBox(width: columnWidth, child: child),
          ],
        );
      },
    );
  }
}

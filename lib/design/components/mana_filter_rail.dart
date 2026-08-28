import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'mana_header.dart' show kManaMinTapTarget;
import 'mana_text.dart';

/// One option in a [ManaFilterChip].
class ManaFilterOption<T> {
  final T value;

  /// Already translated. What the chip reads when this option is chosen.
  final String label;

  const ManaFilterOption(this.value, this.label);
}

/// A filter, shown as its current answer.
///
/// The alternative -- a labelled dropdown in a fixed grid slot -- does not
/// survive this app. Four of them across a 360px phone is 84dp each before a
/// single Telugu label is measured, and the value is the part that gets
/// truncated: "Srikalahasti — Uranduru Colony" becomes "Srika…" in the one
/// control an Agent changes on every village. A chip is the width of its own
/// answer, so the answer is always legible; what does not fit scrolls.
class ManaFilterChip<T> extends StatelessWidget {
  /// What is being filtered — "Village", "Status". Drawn small and quiet.
  final String label;

  final T value;
  final List<ManaFilterOption<T>> options;
  final ValueChanged<T> onChanged;

  /// True when this chip is narrowing the list. A filter that is doing
  /// something must not look like one that is not — an Agent finishing a round
  /// under a village filter believes they have visited everybody.
  final bool active;

  const ManaFilterChip({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.value == value);
    final selected = index < 0 ? null : options[index];

    // Keyed by INDEX, not by value.
    //
    // PopupMenuButton cannot tell a selection of null from a dismissed menu --
    // its own callback is `if (newValue == null) onCanceled() else
    // onSelected(newValue)`. Every "All" option here is null by design (all
    // villages, any status, any frequency), so choosing All did nothing at
    // all: pick Panagallu and there was no way back to the whole round.
    // An index is never null, so the menu can always say what was chosen.
    return PopupMenuButton<int>(
      initialValue: index < 0 ? null : index,
      onSelected: (i) => onChanged(options[i].value),
      tooltip: label,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: ManaText.raw(options[i].label),
          ),
      ],
      child: Container(
        // 48dp tall like every other tappable thing here: this is worked
        // one-handed, standing up, and a chip is not exempt.
        constraints: const BoxConstraints(minHeight: kManaMinTapTarget),
        padding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.md, vertical: ManaSpacing.xs),
        decoration: BoxDecoration(
          color: active ? ManaColors.brandFaint : ManaColors.surface,
          border: Border.all(
            color: active ? ManaColors.brand : ManaColors.divider,
            width: active ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(ManaRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(label, style: ManaType.note, maxLines: 1),
                ManaText.raw(
                  selected?.label ?? '',
                  maxLines: 1,
                  style: active ? ManaType.emphasis : null,
                ),
              ],
            ),
            const SizedBox(width: ManaSpacing.xs),
            Icon(Icons.arrow_drop_down,
                size: 20, color: ManaColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// The one line a book is filtered through.
///
/// It scrolls sideways rather than reflowing into a grid, and that is the
/// whole design. Five filters in a wrapping grid is three rows of controls at
/// 2.0x before a single customer appears — on the screen whose entire job is
/// the list underneath. Scrolling spends horizontal space, which this app has
/// none of but can borrow, instead of vertical space, which it cannot.
///
/// Order matters because the right-hand end is the part that has to be
/// scrolled to: the filters an Agent changes on every village come first.
class ManaFilterRail extends StatelessWidget {
  final List<Widget> filters;

  /// Sits at the left, outside the scroll, so it is always reachable. The
  /// round's own name search lives here — the header's magnifier opens
  /// Universal Search, which is a different question and must not share a
  /// glyph with this one.
  final Widget? leading;

  const ManaFilterRail({super.key, required this.filters, this.leading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: ManaSpacing.xs),
        ],
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: ManaSpacing.xs),
                  filters[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

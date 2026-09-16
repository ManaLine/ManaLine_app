import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import 'mana_amount.dart';
import 'mana_text.dart';

/// A label and the rupee figure it names, on one line.
///
/// OW-011's Final Review and AG-006's Settlement Summary are the two ends of
/// the same handover -- the Owner closing the day, the Agent handing over
/// what they hold -- and both read as a column of these. They had one each,
/// differing only in which weights they reached for.
///
/// The screens themselves are NOT merged and should not be. They call
/// different RPCs on different tables: close_business_day is the Owner's, and
/// putting it behind anything an Agent renders would be a route to a
/// permission the role does not have. What is shared here is how a money line
/// LOOKS, which is common to both because a rupee figure beside its label is
/// the same reading job either way.
///
/// The amount is never allowed to be clipped in favour of the label -- see
/// the note on the value side below.
class ManaMoneyRow extends StatelessWidget {
  final String label;

  /// `num`, not `int`, since 2026-09-16. Screens hold money as int and as
  /// double in different places, and three local label-and-figure helpers
  /// wanted to delegate here rather than each grow its own copy of the
  /// stacking rule below. Widening the parameter was cheaper and safer than
  /// three copies of a decision about money.
  final num amount;

  /// The line somebody is meant to land on -- a closing balance, a
  /// difference. Heavier and larger, not a different colour.
  final bool emphasize;

  /// Only for a figure whose SIGN carries meaning, like a short or an excess.
  /// Colour is not decoration on a money screen.
  ///
  /// A TONE, not a Colour, since 2026-09-16. The amount is drawn by
  /// [ManaAmount] now, which owns the mapping from meaning to colour so that
  /// "short" is the same red everywhere rather than whatever each caller
  /// reached for. One caller passed this and it passed statusGood/statusBad,
  /// which are exactly positive/negative.
  final ManaAmountTone? tone;

  const ManaMoneyRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    // THE LABEL'S STYLE, NOT THE AMOUNT'S.
    //
    // These were one TextStyle covering both, at 13sp normally and 15sp when
    // emphasised -- so the figures an Owner reads to decide whether the day's
    // cash balances were set BELOW the 16sp floor ManaAmount declares for
    // money, in the shared component both day-closing screens are built from.
    // Twenty-three call sites, all of them under the floor, and nothing in the
    // suite could see it.
    //
    // The amount now goes through ManaAmount: the floor, tabular figures so a
    // column of them aligns instead of jittering, a screen-reader label that
    // says "rupees" rather than spelling the glyphs, and no wrap mid-number.
    final labelStyle = TextStyle(
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      fontSize: emphasize ? 15 : 13,
    );
    // The COLOUR IS ON THE FIGURE ALONE. It used to tint the label too, because
    // one style covered both. What carries the meaning is the number's sign,
    // and tinting the word beside it is the decoration this component's own
    // comment says money screens do not get.
    final money = ManaAmount(
      amount,
      size: emphasize ? ManaAmountSize.standard : ManaAmountSize.compact,
      tone: tone ?? ManaAmountTone.neutral,
      semanticLabel: label,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // WHEN THE TWO NO LONGER FIT, THE ROW STACKS. It does not shrink either
      // side.
      //
      // Raising the figure to the 16sp money floor made it wide enough to stop
      // fitting beside its label at 2.0x text scale, and OW-011's layout test
      // said so immediately -- four failures, the overflow bug class this
      // project has shipped four times.
      //
      // The obvious repair is the forbidden one. Letting the amount ellipsise
      // would turn "₹1,23,456" into "₹1,23..." on the screen an Owner reads to
      // decide whether the day's cash balances, and this file's own comment
      // already says why that is not an option: a truncated rupee figure is a
      // wrong number presented as a right one.
      //
      // So the LAYOUT gives instead. The width the figure needs is measured
      // against the width there is, and if the label would be left less than a
      // third of the row the pair stacks -- label above, figure below, both
      // whole. A third because below that a two-line label is unreadable
      // anyway, so the row was already failing, just silently.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(
              text: manaRupees(amount),
              style: TextStyle(
                fontSize: emphasize
                    ? ManaAmountSize.standard.fontSize
                    : ManaAmountSize.compact.fontSize,
                fontWeight: emphasize
                    ? ManaAmountSize.standard.weight
                    : ManaAmountSize.compact.weight,
              ),
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();

          final roomForLabel =
              constraints.maxWidth - painter.width - ManaSpacing.sm;
          final stack = roomForLabel < constraints.maxWidth / 3;

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ManaText.raw(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle),
                money,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The LABEL is the side that gives way. It ellipsises; the
              // amount does not.
              Expanded(
                child: ManaText.raw(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle),
              ),
              const SizedBox(width: ManaSpacing.sm),
              money,
            ],
          );
        },
      ),
    );
  }
}

/// A rupee ENTRY field. Named for the input, not the amount: ManaAmountField
/// already exists in mana_amount.dart and displays a figure. Two widgets with
/// one name is how somebody ends up rendering a number where they meant to
/// collect one.
class ManaRupeeInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback? onChanged;

  const ManaRupeeInput({
    super.key,
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: '₹ '),
          onChanged: onChanged == null ? null : (_) => onChanged!(),
        ),
      );
}

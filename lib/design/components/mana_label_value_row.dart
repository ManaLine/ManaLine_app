import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'mana_amount.dart';
import 'mana_text.dart';

/// A label on the left, its value on the right, with NEITHER side unbounded.
///
/// This existed three times -- twice in AG-004, once in OW-004 -- and every
/// copy overflowed. OW-004's Summary tab overflowed by 136px at 1.0x text
/// scale in English, on the plain 360dp default: not an accessibility-scale
/// edge case, the ordinary screen. AG-004's two copies guarded the LABEL with
/// maxLines/ellipsis and left the value bare, which overflows just the same,
/// only on the other side.
///
/// The rule the copies each got wrong: a Row containing a flexible child and
/// an unflexible one gives the unflexible one its full natural width first.
/// That is the overflow bug class this project has shipped four times.
///
/// The value WRAPS rather than ellipsising. These rows carry names, villages,
/// joined addresses and rupee figures -- an ellipsis on any of them hides
/// exactly the part that tells one person or one amount from another, on the
/// screen used to identify somebody before money moves. Wrapping costs a line;
/// truncating costs the fact.
class ManaLabelValueRow extends StatelessWidget {
  final String label;

  /// Pre-formatted text. A rupee figure goes in [amount] instead, NOT here.
  final String value;

  /// Set when the value is MONEY.
  ///
  /// Seven of this component's fifty-one call sites pass a rupee figure, and
  /// they used to pass it as a String -- so a customer's outstanding balance
  /// was drawn at ManaType.smallStrong, 13sp, with proportional digits, beside
  /// a village name rendered identically. Given an amount the row draws
  /// ManaAmount: the 16sp floor, tabular figures so a column of them aligns,
  /// and a screen reader that says "rupees" rather than spelling the glyphs.
  final num? amount;

  /// Drawn after the value, inside the row's bounds -- a call button, say.
  /// Must be intrinsically bounded; it is the one child that is not flexible.
  final Widget? trailing;

  /// Tighter vertical padding, for rows stacked inside a card rather than
  /// listed down a tab. AG-004's Loan Information rows were already spaced
  /// this way and the spacing is theirs, not an accident worth flattening.
  final bool dense;

  /// Overrides the value's text style -- for rows whose value is a headline
  /// amount rather than a plain figure. The bounding is unchanged either way;
  /// a bigger style is exactly when the old bare-value rows broke.
  final TextStyle? valueStyle;

  const ManaLabelValueRow({
    super.key,
    required this.label,
    this.value = '',
    this.amount,
    this.trailing,
    this.dense = false,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 2 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: ManaText.raw(label, style: ManaType.note)),
            const SizedBox(width: ManaSpacing.xs),
            Expanded(
              flex: 6,
              child: amount != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: ManaAmount(amount!,
                          size: ManaAmountSize.compact, semanticLabel: label),
                    )
                  : ManaText.raw(value,
                      style: valueStyle ?? ManaType.smallStrong,
                      textAlign: TextAlign.right),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

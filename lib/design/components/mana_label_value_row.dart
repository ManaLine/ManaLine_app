import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import '../tokens/typography.dart';
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
  final String value;

  /// Drawn after the value, inside the row's bounds -- a call button, say.
  /// Must be intrinsically bounded; it is the one child that is not flexible.
  final Widget? trailing;

  /// Tighter vertical padding, for rows stacked inside a card rather than
  /// listed down a tab. AG-004's Loan Information rows were already spaced
  /// this way and the spacing is theirs, not an accident worth flattening.
  final bool dense;

  const ManaLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.dense = false,
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
              child: ManaText.raw(value,
                  style: ManaType.smallStrong, textAlign: TextAlign.right),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

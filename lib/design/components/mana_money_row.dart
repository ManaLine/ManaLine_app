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
  final int amount;

  /// The line somebody is meant to land on -- a closing balance, a
  /// difference. Heavier and larger, not a different colour.
  final bool emphasize;

  /// Only for a figure whose SIGN carries meaning, like a short or an excess.
  /// Colour is not decoration on a money screen.
  final Color? color;

  const ManaMoneyRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
      fontSize: emphasize ? 15 : 13,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The LABEL is the side that gives way. It ellipsises; the amount
          // does not, because a truncated rupee figure is a wrong number
          // presented as a right one, and this row is read to decide whether
          // cash balances.
          Expanded(
            child: ManaText.raw(label,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
          ),
          const SizedBox(width: ManaSpacing.sm),
          ManaText.raw(manaRupees(amount),
              style: style, textAlign: TextAlign.right),
        ],
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

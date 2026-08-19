import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/translation_service.dart';
import '../tokens/spacing.dart';
import 'mana_text.dart';

/// The All / Daily / Weekly / Monthly narrowing control on Collection Mode.
///
/// Replaces the row of ChoiceChips that OW-006 and AG-002 each carried a copy
/// of. Chips cost a full line of width that a collection round — the screen an
/// Agent works standing up, one-handed — needs for the due list itself, and at
/// larger text scales the row wrapped to two lines.
///
/// All four options are always offered, including ones the round does not
/// currently contain. The chips used to hide themselves when the round held
/// fewer than two frequencies, which was right when they occupied a whole
/// line; inside a closed dropdown an option that empties the list costs
/// nothing, and a control that silently disappears is harder to trust than one
/// that is always in the same place.
///
/// Labelled "Frequency", not "Sort By": it narrows the list, it does not
/// reorder it. The real sort order (penalty → grace → today's due → village)
/// is stated in its own line directly below.
class ManaFrequencyPicker extends ConsumerWidget {
  /// 'Daily' | 'Weekly' | 'Monthly', or null for the whole round.
  final String? value;
  final ValueChanged<String?> onChanged;

  const ManaFrequencyPicker({super.key, required this.value, required this.onChanged});

  /// The stored values are the `loans.repayment_type` strings, so they are
  /// NOT translated — only their labels are.
  static const options = <String?>[null, 'Daily', 'Weekly', 'Monthly'];

  static String _labelKey(String? v) => switch (v) {
        'Daily' => 'daily',
        'Weekly' => 'weekly',
        'Monthly' => 'monthly',
        _ => 'all',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: ref.t('frequency'),
          isDense: true,
        ),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: ManaText(_labelKey(o))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../design/components/mana_text.dart';

/// One address field the PIN code directory may already know the answer to.
///
/// Three shapes, one control:
///   * nothing known for this PIN — a plain text field, as before;
///   * one answer — the value, filled in and unchanged by the person;
///   * several — a short list of what actually exists at that PIN.
///
/// WHY A LIST RATHER THAN A PREFILL: mandal is ambiguous for 9,931 of the
/// 17,183 PINs in `lgd_villages` and district for 3,451 of them. "Fill it in
/// when the PIN agrees" therefore leaves the commonest field blank most of the
/// time, which is how somebody standing at a doorstep ends up typing a mandal
/// the reference already holds — or a typo of it.
///
/// A dropdown rather than an autocomplete because these are closed sets: a
/// mandal that is not in the directory for its PIN is a mistake, not a
/// discovery. The controller stays the source of truth, so validation and the
/// save path are untouched.
/// What the directory offers for one field at a PIN, narrowed by whatever is
/// already chosen above it.
///
/// [rows] are `app.suggest_villages` rows — village/mandal/district/state for
/// one PIN. Widest first: a state narrows the districts, a district narrows
/// the mandals. Sorted, de-duplicated, blanks dropped.
///
/// The reference carries the same village under both the old and the new
/// district name after the post-2022 splits, which is why de-duplication is
/// not optional: without it a PIN answers twice for every place in it.
List<String> manaReferenceOptions(
  List<Map<String, dynamic>> rows,
  String key, {
  String state = '',
  String district = '',
}) {
  final out = <String>{};
  for (final r in rows) {
    if (key != 'state' && state.isNotEmpty && (r['state'] ?? '') != state) {
      continue;
    }
    if (key == 'mandal' &&
        district.isNotEmpty &&
        (r['district'] ?? '') != district) {
      continue;
    }
    final v = (r[key] as String?)?.trim() ?? '';
    if (v.isNotEmpty) out.add(v);
  }
  return out.toList()..sort();
}

class ManaReferenceField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  /// What the directory offers, already narrowed by whatever is chosen above
  /// this field. Empty means the directory has nothing for this PIN.
  final List<String> options;

  /// Called after the controller changes so the caller can re-narrow the
  /// fields below this one.
  final VoidCallback onChanged;

  const ManaReferenceField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => onChanged(),
      );
    }
    final current = controller.text.trim();
    return DropdownButtonFormField<String>(
      // isExpanded: a DropdownButton sizes to its widest item and overflows
      // rather than shrinking — measured at 1.0x on OW-002.
      isExpanded: true,
      initialValue: options.contains(current) ? current : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: ManaText.raw(o, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        controller.text = v ?? '';
        onChanged();
      },
    );
  }
}

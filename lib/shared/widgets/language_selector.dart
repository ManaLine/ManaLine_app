import 'package:flutter/material.dart';
import '../../design/tokens/colors.dart';

/// GC-001 Runtime Language Selector (per LR-002 spec).
/// Fixed V1 list of five — no admin-configurable language table this
/// release, per the locked schema's `preferred_language_enum`.
enum ManaLanguage {
  english('English', 'English'),
  telugu('Telugu', 'తెలుగు'),
  hindi('Hindi', 'हिन्दी'),
  tamil('Tamil', 'தமிழ்'),
  kannada('Kannada', 'ಕನ್ನಡ');

  final String enumValue; // exact value stored in persons.preferred_language
  final String nativeLabel;
  const ManaLanguage(this.enumValue, this.nativeLabel);
}

/// Stateless selector — the caller owns current-language state (via
/// Riverpod provider, see app/providers.dart) and persistence to
/// `persons.preferred_language` at auth time (LR-006/007/009) per the
/// spec's own confirmed persistence rule. This widget only renders and
/// emits the choice.
class ManaLanguageSelector extends StatelessWidget {
  final ManaLanguage current;
  final ValueChanged<ManaLanguage> onChanged;
  final bool compact;

  const ManaLanguageSelector({
    super.key,
    required this.current,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return DropdownButtonHideUnderline(
        child: DropdownButton<ManaLanguage>(
          value: current,
          icon: const Icon(Icons.language, size: 18, color: ManaColors.textSecondary),
          items: ManaLanguage.values
              .map((l) => DropdownMenuItem(value: l, child: Text(l.nativeLabel)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
    }

    return Wrap(
      spacing: 8,
      children: ManaLanguage.values.map((l) {
        final selected = l == current;
        return ChoiceChip(
          label: Text(l.nativeLabel),
          selected: selected,
          onSelected: (_) => onChanged(l),
          selectedColor: ManaColors.brassFaint,
          labelStyle: TextStyle(
            color: selected ? ManaColors.brass : ManaColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        );
      }).toList(),
    );
  }
}

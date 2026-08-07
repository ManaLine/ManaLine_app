import 'package:flutter/material.dart';
import '../../design/tokens/colors.dart';
import '../../design/components/mana_text.dart';

/// GC-001 Runtime Language Selector (per LR-002 spec).
/// Cut down to English + Telugu — the other three (Hindi/Tamil/Kannada)
/// are no longer offered in the UI. `preferred_language_enum` in the
/// database still has all five values; existing rows are untouched, this
/// only changes what a person can newly pick.
enum ManaLanguage {
  english('English', 'English'),
  telugu('Telugu', 'తెలుగు');

  final String enumValue; // exact value stored in persons.preferred_language
  final String nativeLabel;
  const ManaLanguage(this.enumValue, this.nativeLabel);
}

/// Compact dropdown language selector — used on registration, login, and
/// settings screens. Compact by default since it is a footer-level
/// control, not the main content.
class ManaLanguageSelector extends StatelessWidget {
  final ManaLanguage current;
  final ValueChanged<ManaLanguage> onChanged;

  const ManaLanguageSelector({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.language, size: 18, color: ManaColors.textSecondary),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<ManaLanguage>(
            value: current,
            isDense: true,
            items: ManaLanguage.values
                .map((l) => DropdownMenuItem<ManaLanguage>(
                      value: l,
                      child: ManaText.raw(l.nativeLabel),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

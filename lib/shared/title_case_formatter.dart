import 'package:flutter/services.dart';

/// Real, working title-case enforcement — unlike `textCapitalization`
/// (a TextField property), which is only a HINT to the on-screen mobile
/// keyboard and has zero effect on Flutter Web with a physical keyboard.
/// This formatter actually transforms the text as it's typed, on every
/// platform, by capitalizing the first letter of each word.
///
/// Preserves cursor position so typing feels natural (doesn't jump to
/// the end on every keystroke).
class TitleCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final capitalized = newValue.text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    if (capitalized == newValue.text) return newValue;

    return newValue.copyWith(
      text: capitalized,
      selection: newValue.selection,
    );
  }
}

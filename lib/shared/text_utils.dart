/// Title-cases a person's name for display, e.g. "gangavarapu sai ram" ->
/// "Gangavarapu Sai Ram". Applied where a name is parsed out of a raw
/// Postgrest row into a display model (fullName/agentName/etc.), so every
/// screen reading that field shows it consistently regardless of how it
/// was capitalized at entry (registration/add-existing forms don't
/// enforce casing, and Indian personal names have no internal-capital
/// convention like "McDonald" that a blind title-case could mangle, so
/// this is safe to apply uniformly rather than only at input time).
String titleCaseName(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

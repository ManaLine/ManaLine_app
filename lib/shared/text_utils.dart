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

/// Investor interest, quoted the way this trade actually quotes it:
/// RUPEES PER 100 OF PRINCIPAL, PER MONTH. `investments.roi_rate` stores
/// that figure — 1.5 means ₹1.50 per ₹100 per month.
///
/// It was previously rendered as "1.5%", which is ambiguous at best and
/// wrong at worst: read as an annual percentage it understates the real
/// rate by 12x. Every display goes through here so the six render sites
/// cannot drift apart again.
///
/// NOTE: nothing in this app computes interest from roi_rate yet — not in
/// Dart, and not in app.get_investment_statement, which only returns the
/// raw figure. So this is currently a labelling fix. When the interest
/// engine is built, "per 100 per month" is the definition it must use:
/// monthly interest = principal / 100 * roi_rate.
String roiLabel(num ratePer100PerMonth) =>
    '₹${ratePer100PerMonth.toStringAsFixed(2)} / 100 / month';

/// The same figure as an annual percentage, for a secondary line where the
/// yearly cost is the more familiar number. ₹1.50/100/month -> "18% / year".
String roiAnnualEquivalent(num ratePer100PerMonth) =>
    '${(ratePer100PerMonth * 12).toStringAsFixed(1)}% / year';

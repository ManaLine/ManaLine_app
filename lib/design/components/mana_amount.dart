/// The single way this app renders money.
///
/// WHY A COMPONENT AND NOT A HELPER FUNCTION: rupee figures were being
/// formatted at 44 different call sites, each choosing its own font size (26
/// of them at 11–12sp, i.e. the most important numbers in the app were among
/// its smallest text), its own weight, and its own colour. That is impossible
/// to keep consistent by review, and a misread digit here is a financial
/// error, not a cosmetic one. Centralising it means the legibility floor is
/// structural rather than a convention someone has to remember.
///
/// Three things this fixes that a `NumberFormat` call cannot:
///
///  1. TABULAR FIGURES. Proportional digits make column-aligned amounts in a
///     list jitter — `1` is narrower than `8`, so ₹1,111 and ₹8,888 occupy
///     different widths and the decimal positions don't line up. Scanning a
///     column of collections for the odd one out is a core task here, and
///     `FontFeature.tabularFigures()` is what makes that possible.
///
///  2. A SCREEN-READER LABEL THAT ISN'T THE GLYPH SOUP. TalkBack reading
///     "₹1,23,456" character by character is useless. This announces
///     "1,23,456 rupees" via a semantics label instead.
///
///  3. NO WRAPPING MID-NUMBER. An amount that line-breaks between the ₹ and
///     the digits, or mid-thousands-group, is briefly unreadable and can be
///     genuinely misread. Amounts never soft-wrap.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../tokens/colors.dart';

/// Indian-format currency, no decimals: ₹1,23,456 (lakh grouping, not
/// thousands). Matches the existing `_currency` formatters this replaces.
final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// How prominent an amount is. Sizes are floors, not suggestions — see the
/// typography rationale in the class doc.
enum ManaAmountSize {
  /// Secondary figures inside a dense row. 16sp — the absolute floor for
  /// money in this app.
  compact(16, FontWeight.w600),

  /// The default for list rows and summary cards.
  standard(18, FontWeight.w700),

  /// The one figure a screen is *about* — an outstanding balance, a total due.
  /// Should be the largest text on its screen.
  hero(28, FontWeight.w700);

  const ManaAmountSize(this.fontSize, this.weight);
  final double fontSize;
  final FontWeight weight;
}

/// Semantic role of an amount, which drives its colour.
enum ManaAmountTone {
  /// Ordinary figure — the default. Uses text colour, not a status colour.
  neutral,

  /// Money received / settled / balanced.
  positive,

  /// Money owed / short / overdue / penalty.
  negative,

  /// Pending, partial, awaiting action.
  caution,

  /// Sits on a coloured (blue) surface, e.g. inside a header block.
  onBrand;
}

class ManaAmount extends StatelessWidget {
  final num value;
  final ManaAmountSize size;
  final ManaAmountTone tone;

  /// Prefix for the screen reader only, e.g. "Outstanding balance". Without
  /// it a reader hears a bare number with no idea what it measures.
  final String? semanticLabel;

  /// Shows an explicit `+`/`−` sign. For ledger deltas where direction is the
  /// point (short/excess, adjustments), not for plain balances.
  final bool showSign;

  const ManaAmount(
    this.value, {
    super.key,
    this.size = ManaAmountSize.standard,
    this.tone = ManaAmountTone.neutral,
    this.semanticLabel,
    this.showSign = false,
  });

  /// Convenience for the dominant figure on a screen.
  const ManaAmount.hero(
    this.value, {
    super.key,
    this.tone = ManaAmountTone.neutral,
    this.semanticLabel,
    this.showSign = false,
  }) : size = ManaAmountSize.hero;

  /// Convenience for figures packed into a dense row.
  const ManaAmount.compact(
    this.value, {
    super.key,
    this.tone = ManaAmountTone.neutral,
    this.semanticLabel,
    this.showSign = false,
  }) : size = ManaAmountSize.compact;

  Color get _color => switch (tone) {
        ManaAmountTone.neutral => ManaColors.textPrimary,
        ManaAmountTone.positive => ManaColors.statusGood,
        ManaAmountTone.negative => ManaColors.statusBad,
        ManaAmountTone.caution => ManaColors.statusWarn,
        ManaAmountTone.onBrand => ManaColors.textOnDark,
      };

  @override
  Widget build(BuildContext context) {
    final magnitude = _inr.format(value.abs());
    final sign = !showSign
        ? ''
        : value < 0
            ? '−' // U+2212 minus, not a hyphen: hyphens read as dashes and are
            // easy to miss at a glance on a money figure.
            : '+';
    final text = '$sign$magnitude';

    // Spoken form: "Outstanding balance, 12,340 rupees, short" rather than the
    // symbol and digits read one glyph at a time.
    final spokenSign = !showSign
        ? ''
        : value < 0
            ? 'minus '
            : 'plus ';
    final spoken = [
      if (semanticLabel != null) '$semanticLabel, ',
      spokenSign,
      _inr.format(value.abs()).replaceFirst('₹', ''),
      ' rupees',
    ].join();

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(
        text,
        // Never let an amount break across lines or shrink into
        // illegibility — ellipsis is safer than a silently truncated or
        // rewrapped number.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: size.fontSize,
          fontWeight: size.weight,
          color: _color,
          // The reason this component exists — see doc comment.
          fontFeatures: const [FontFeature.tabularFigures()],
          // Slightly tightened: tabular digits are generously spaced by
          // default and money reads better as a single block.
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// A label above an amount — the pattern used dozens of times across the
/// dashboards and ledger cards. Exists so the label/figure relationship
/// (spacing, label colour, label size) is decided once.
class ManaAmountField extends StatelessWidget {
  final String label;
  final num value;
  final ManaAmountSize size;
  final ManaAmountTone tone;
  final bool showSign;

  const ManaAmountField({
    super.key,
    required this.label,
    required this.value,
    this.size = ManaAmountSize.compact,
    this.tone = ManaAmountTone.neutral,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            // 13sp floor — see the typography rationale. Labels were at 10sp.
            fontSize: 13,
            color: ManaColors.textSecondary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        // The amount carries the label into its own spoken form, so the
        // reader hears "Collections, 4,500 rupees" as one utterance.
        ManaAmount(value, size: size, tone: tone, showSign: showSign, semanticLabel: label),
      ],
    );
  }
}

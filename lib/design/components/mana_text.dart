import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// Enforces 11_UI_Guidelines.md's locked Title Case standard at the
/// widget layer, not by convention/reviewer-memory. Applies to field
/// labels, statuses, screen names, and button/action labels — per the
/// guideline's own scope. Does NOT apply to free-text user data,
/// system-generated IDs, or database field names — callers pass those
/// through ManaText.raw() instead, which does no transformation.
///
/// Small words (a, an, the, of, in, for, and, or, to) stay lowercase
/// unless they're the first word — per the guideline's own rule.
class ManaText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool _raw;

  const ManaText(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow})
      : _raw = false;

  /// Use for free-text (names, remarks, addresses), system IDs
  /// (MLBI/MLPI/MLTI/EMI/PIN/OTP), or anything already correctly cased —
  /// bypasses title-casing entirely, per the guideline's own exclusions.
  const ManaText.raw(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow})
      : _raw = true;

  static const _minorWords = {
    'a', 'an', 'the', 'of', 'in', 'for', 'and', 'or', 'to',
  };

  String _titleCase(String input) {
    final words = input.split(' ');
    return words.asMap().entries.map((entry) {
      final isFirst = entry.key == 0;
      final word = entry.value;
      if (word.isEmpty) return word;
      // Preserve all-caps acronyms/IDs embedded mid-label (e.g. "OTP",
      // "MLID") rather than re-casing them.
      if (word == word.toUpperCase() && word.length > 1) return word;
      final lower = word.toLowerCase();
      if (!isFirst && _minorWords.contains(lower)) return lower;
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _raw ? text : _titleCase(text),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Status vocabulary shared everywhere a loan/collection/settlement/
/// membership status is rendered — one widget, one place the
/// color↔status mapping lives, so it can never drift screen to screen.
enum ManaStatus { good, bad, warn, neutral }

class ManaStatusPill extends StatelessWidget {
  final String label;
  final ManaStatus status;

  const ManaStatusPill({super.key, required this.label, required this.status});

  ({Color fg, Color bg}) get _colors => switch (status) {
        ManaStatus.good => (fg: ManaColors.statusGood, bg: ManaColors.statusGoodFaint),
        ManaStatus.bad => (fg: ManaColors.statusBad, bg: ManaColors.statusBadFaint),
        ManaStatus.warn => (fg: ManaColors.statusWarn, bg: ManaColors.statusWarnFaint),
        ManaStatus.neutral => (fg: ManaColors.textSecondary, bg: ManaColors.surfaceSunken),
      };

  @override
  Widget build(BuildContext context) {
    final c = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
      child: ManaText(
        label,
        // Ellipsis rather than wrap: a two-line pill changes the row height
        // and looks like a different component. The width bound belongs to
        // the caller — see ManaTrailingStatus for the ListTile case.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A [ManaStatusPill] safe to hand to `ListTile.trailing`.
///
/// WHY THIS EXISTS: ListTile's trailing slot assumes a bounded width and
/// asserts "Trailing widget consumes the entire tile width" when it does not
/// get one. A status pill's width is a translated string, so it is unbounded
/// by nature — "Pending Acceptance" in Telugu at 1.3x text scale fills the
/// whole tile and the row throws during layout.
///
/// This shipped as a real failure on OW-002 and was latent in eight more
/// places, hidden only because nothing had yet freed enough vertical space
/// for those rows to be laid out on a small surface. Wrapping the fix in a
/// named widget rather than repeating a ConstrainedBox at each call site
/// means the next `trailing:` pill gets it for free.
class ManaTrailingStatus extends StatelessWidget {
  final String label;
  final ManaStatus status;

  /// Roughly a third of a 360dp row — enough for the longest status in the
  /// five languages, and never enough to swallow the tile.
  final double maxWidth;

  const ManaTrailingStatus({
    super.key,
    required this.label,
    required this.status,
    this.maxWidth = 120,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: 1,
        child: ManaStatusPill(label: label, status: status),
      ),
    );
  }
}

/// The Verification Ring — the app's signature motif (BR-191/GC-002),
/// echoed here as a reusable component rather than one-off avatar code,
/// so Green/Red-Ring reads consistently on every profile photo across
/// every workspace (OW/AG/CW/IW headers all reference this).
class ManaVerificationRing extends StatelessWidget {
  final ImageProvider? photo;
  final bool isVerified; // GREEN vs RED, per persons.verification_ring
  final double size;

  /// A ring colour that means something OTHER than identity verification.
  ///
  /// The business roster asked for the ring to carry membership status --
  /// green active, red suspended, orange removed. That is a second meaning
  /// for the same circle, and the twenty-two other call sites all mean the
  /// first one, so it is an explicit opt-in rather than a reinterpretation of
  /// `isVerified`. A screen passing this is saying "on this list the ring
  /// means status", and a reader of any other screen is not left guessing
  /// which of the two they are looking at.
  final Color? ringColor;

  /// How much of the ring is drawn, 0.0 to 1.0. Null draws the whole circle.
  ///
  /// A THIRD CHANNEL, NOT A THIRD COLOUR. The Owner asked for the ring to show
  /// how complete a customer's profile is -- "circle completely closes when
  /// profile is 100 % complete" -- and the note above records why that could
  /// not be another colour: this circle already means verification on
  /// twenty-two screens and membership status on the roster. Sweep is
  /// independent of both. A half-drawn green ring still says verified; it just
  /// also says half-known.
  ///
  /// Starts at the top and travels clockwise, because that is how a person
  /// reads a gauge.
  final double? completeness;

  const ManaVerificationRing({
    super.key,
    required this.isVerified,
    this.photo,
    this.size = 44,
    this.ringColor,
    this.completeness,
  });

  @override
  Widget build(BuildContext context) {
    final ringColor = this.ringColor ??
        (isVerified ? ManaColors.ringVerified : ManaColors.ringUnverified);

    // A partial ring is PAINTED; a whole one keeps the border it always had.
    // Two reasons not to paint both: the full circle is twenty-two screens'
    // worth of established pixels and does not need re-deriving, and a
    // CustomPaint on every avatar in a list costs more than a BoxDecoration
    // for a shape that never changes.
    final sweep = completeness;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      foregroundDecoration: sweep == null
          ? null
          : _RingSweep(colour: ringColor, fraction: sweep.clamp(0.0, 1.0)),
      decoration: sweep != null
          ? const BoxDecoration(shape: BoxShape.circle)
          : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor, width: 2.5)),
      child: CircleAvatar(
        backgroundColor: ManaColors.inkFaint,
        backgroundImage: photo,
        child: photo == null
            ? Icon(Icons.person, color: ManaColors.textSecondary, size: size * 0.5)
            : null,
      ),
    );
  }
}

/// The ring, drawn only as far round as a profile is filled in.
///
/// A Decoration rather than a CustomPainter widget so it can sit in the same
/// Container the whole-circle version uses, as `foregroundDecoration` — over
/// the avatar, not behind it. A painter widget would have meant a Stack and a
/// second layout pass for every row of a collection round.
///
/// The UNFILLED part is drawn too, faintly. A ring that simply stopped would
/// read as a rendering fault at four fifths; a faint remainder reads as
/// something with more to go, which is what it is.
class _RingSweep extends Decoration {
  final Color colour;
  final double fraction;

  const _RingSweep({required this.colour, required this.fraction});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _RingSweepPainter(colour, fraction);
}

class _RingSweepPainter extends BoxPainter {
  final Color colour;
  final double fraction;

  _RingSweepPainter(this.colour, this.fraction);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    // Inset by half the stroke so the ring sits inside its box exactly where
    // Border.all would have put it, and the two versions line up if a screen
    // ever shows both.
    final rect = (offset & size).deflate(1.25);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = colour.withValues(alpha: 0.18);
    canvas.drawArc(rect, 0, 6.283185307179586, false, track);

    if (fraction <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = colour;
    // -pi/2 starts at twelve o'clock; a positive sweep runs clockwise.
    canvas.drawArc(rect, -1.5707963267948966,
        6.283185307179586 * fraction, false, arc);
  }
}

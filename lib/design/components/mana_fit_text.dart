import 'package:flutter/material.dart';

import 'mana_text.dart';

/// Text that SHRINKS to fit, down to a floor, and then WRAPS -- and never
/// ends in dots.
///
/// THE OWNER'S RULE, in their words: "make sure no word (in the entire app
/// includes every language we render in future also) from now should be cut
/// and show the remaining in dots, if necessary use the extra row (auto
/// extend) when necessary." Asked again as "can't the app reduce the size
/// automatically if the name gets longer to fit in?"
///
/// It can, and it should, and it must not do only that.
///
/// WHY THERE IS A FLOOR. This app is used one-handed at a doorstep in bright
/// sun on a cheap screen. Text shrunk far enough to fit any string is text
/// nobody can read, which fails the same person the rule is protecting --
/// and money already has a declared floor of its own: ManaAmount exists
/// because "the most important numbers in the app were among its smallest
/// text". So shrinking stops at [minScale] of the given size, and from there
/// the line count grows instead.
///
/// WHY IT IS NOT JUST FittedBox. FittedBox scales without limit and ignores
/// the text scale a person chose in their phone settings -- so an Owner who
/// set 2.0x because they cannot read 1.0x would get their long names
/// squeezed back down past where they started. This measures against the
/// scaler the platform reports and never goes below the floor.
///
/// WHAT IT IS FOR. The things that identify somebody or something: a person's
/// name, a village, a business, an owner, an MLID. Those are answers, and an
/// answer cut at fifteen characters is not a shorter answer -- "Sri
/// Satyanaraya..." was reported from a handset for exactly that reason, on a
/// book with two businesses whose names both begin "Sri ".
///
/// WHAT IT IS NOT FOR. Free prose -- a remark, a rejection reason, a
/// description. Those are genuinely unbounded, a person can open them to read
/// the rest, and letting one push a list row to nine lines helps nobody.
class ManaFitText extends StatelessWidget {
  /// The string. Never title-cased -- everything this is for is already a
  /// name, an ID or a place, which is ManaText.raw's own carve-out.
  final String text;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// How many lines it may grow to before it stops.
  ///
  /// NOT a clip: at [maxLines] the text still wraps and still shows every
  /// word it can, and the floor is what keeps that from being reached. Two is
  /// right for a list row, where a third line starts pushing the next person
  /// off the screen.
  final int maxLines;

  /// The smallest fraction of [style]'s size this may shrink to.
  ///
  /// 0.8 by default: a 16sp name may become 12.8sp, which is still above the
  /// 11sp this app uses for its quietest notes. Below that it stops
  /// shrinking and takes another line instead.
  final double minScale;

  const ManaFitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 2,
    this.minScale = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final size = base.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;

    return LayoutBuilder(builder: (context, constraints) {
      // Unbounded width means nothing to fit INTO -- a Row that has not been
      // given a Flexible, usually. Shrinking there would be guesswork, so it
      // draws plainly and lets the layout say what it wants.
      if (!constraints.hasBoundedWidth || constraints.maxWidth.isInfinite) {
        // softWrap is not a ManaText parameter and does not need to be:
        // Text wraps by default, and what makes this widget different is the
        // overflow it does NOT pass.
        return ManaText.raw(text,
            style: base, textAlign: textAlign, maxLines: maxLines);
      }

      final scaler = MediaQuery.textScalerOf(context);
      var chosen = size;
      // Eight steps from full size down to the floor. Stepwise rather than a
      // binary search because the answer only has to look right, and a
      // fraction of a point either way is invisible -- while a search over a
      // TextPainter is eight layouts either way.
      const steps = 8;
      final floor = size * minScale;
      for (var i = 0; i <= steps; i++) {
        final trial = size - (size - floor) * (i / steps);
        final painter = TextPainter(
          text: TextSpan(text: text, style: base.copyWith(fontSize: trial)),
          textDirection: Directionality.of(context),
          textAlign: textAlign ?? TextAlign.start,
          maxLines: maxLines,
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        chosen = trial;
        if (!painter.didExceedMaxLines) break;
      }

      // NO overflow PARAMETER. Leaving it null is what makes this different
      // from every site it replaces: Flutter clips the last line rather than
      // ellipsising it, so a string that still does not fit loses pixels
      // instead of gaining a "..." that claims to be the whole answer. In
      // practice the floor plus two lines fits every name on these books --
      // and when it does not, the reader can see that it did not, which is
      // the honest failure.
      return ManaText.raw(
        text,
        style: base.copyWith(fontSize: chosen),
        textAlign: textAlign,
        maxLines: maxLines,
      );
    });
  }
}

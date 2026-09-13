import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/theme.dart';
import 'package:mana_line/design/tokens/colors.dart';

/// Buttons an Owner presses standing in a field in the middle of the day.
///
/// The question that started this was whether the amber primary button is
/// readable in bright sun. It is -- it is the most readable pair in the
/// palette, and that is not an accident: hi-vis clothing is this colour
/// because a high-luminance surface with dark marks on it survives glare.
///
/// Glare does not pick colours it dislikes. It adds a roughly constant
/// luminance to every pixel, which compresses every contrast ratio toward 1.
/// So the pairs that stay legible longest are the ones that started highest,
/// and the useful test is the ratio itself.
double _luminance(Color c) {
  double channel(double v) {
    final s = v;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('the label survives the sun', () {
    test('dark ink on the amber primary clears AAA', () {
      // 7:1 is AAA for normal text. This pair measures about 8.48.
      final ratio = _contrast(ManaColors.accent, ManaColors.textPrimary);
      expect(ratio, greaterThan(7.0),
          reason: 'the primary button label measured $ratio:1');
    });

    test('white on the blue used under text clears AAA too', () {
      // brandDeep, not brand. colorScheme.primary and every outlined button
      // use the deep one; the lighter `brand` is for icons, borders and
      // selected states, never as a page-coloured background under text.
      final ratio = _contrast(ManaColors.brandDeep, Colors.white);
      expect(ratio, greaterThan(7.0),
          reason: 'white on brandDeep measured $ratio:1');
    });
  });

  group('the shape survives it as well', () {
    test('the amber fill alone is NOT distinguishable from the page', () {
      // This is the actual weakness, and the reason for the border. 1.76:1
      // against white: the label stays readable while the button's outline
      // disappears, so an Owner loses where to press rather than what it says.
      expect(_contrast(ManaColors.accent, ManaColors.surface), lessThan(3.0),
          reason: 'if this ever rises above 3:1 the border is no longer '
              'earning its place and should be reconsidered');
    });

    test('the primary button carries a border that holds when the fill does not',
        () {
      final side = ManaTheme.light()
          .elevatedButtonTheme
          .style!
          .side!
          .resolve(<WidgetState>{});
      expect(side, isNotNull, reason: 'the primary button has lost its edge');
      expect(_contrast(side!.color, ManaColors.accent), greaterThan(3.0),
          reason: 'the border must stand out from the fill it outlines');
    });
  });
}

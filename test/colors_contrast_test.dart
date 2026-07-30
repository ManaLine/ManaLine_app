import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/colors.dart';

/// Locks in the accessibility guarantees of the palette so they can't be
/// silently regressed.
///
/// This exists because the palette is a long-lived decision for an app used
/// outdoors, in direct sun, on cheap screens — and because the previous
/// palette had already drifted into two real problems that were invisible
/// without measuring:
///
///   1. `textPrimary` was an alias of the brand colour, so changing the brand
///      would have dropped all body text from 14:1 to 4.5:1 without anyone
///      touching a text style.
///   2. statusGood/statusBad were a red-green pair at near-identical
///      luminance — the worst case for the ~8% of men with red-green colour
///      vision deficiency, on money-critical signals.
///
/// A comment saying "4.51:1" rots. An assertion doesn't.

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  // Flutter's newer wide-gamut API exposes channels as 0..1 doubles.
  return 0.2126 * channel(c.r * 255.0) +
      0.7152 * channel(c.g * 255.0) +
      0.0722 * channel(c.b * 255.0);
}

/// WCAG 2.1 contrast ratio between two colours, always >= 1.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

const _white = Color(0xFFFFFFFF);

void main() {
  group('text legibility', () {
    test('textPrimary clears AAA on white', () {
      // 7:1 rather than AA's 4.5:1 on purpose: bright ambient light adds
      // reflected luminance to foreground and background alike, compressing
      // effective contrast. Outdoors needs headroom.
      expect(_contrast(ManaColors.textPrimary, _white), greaterThanOrEqualTo(7.0));
    });

    test('textPrimary is NOT the brand colour', () {
      // The specific regression that motivated splitting these tokens.
      expect(ManaColors.textPrimary, isNot(ManaColors.brand));
      expect(ManaColors.textPrimary, isNot(ManaColors.brandDeep));
    });

    test('textSecondary clears AA on white', () {
      expect(_contrast(ManaColors.textSecondary, _white), greaterThanOrEqualTo(4.5));
    });
  });

  group('brand and accent', () {
    test('brand clears AA on white for icons and large text', () {
      expect(_contrast(ManaColors.brand, _white), greaterThanOrEqualTo(4.5));
    });

    test('white text on brandDeep clears AAA', () {
      // Why brandDeep exists: white on `brand` is only ~4.5:1, too thin for
      // small labels in sun. Anything carrying white text must use brandDeep.
      expect(_contrast(_white, ManaColors.brandDeep), greaterThanOrEqualTo(7.0));
    });

    test('dark text on accent clears AAA', () {
      // The accent is a fill. Its contract is that textPrimary sits on it.
      expect(_contrast(ManaColors.textPrimary, ManaColors.accent), greaterThanOrEqualTo(7.0));
    });

    test('accent is a fill colour, not an ink colour', () {
      // Asserted as a FACT, not a failure: accent on white is far below the
      // 3:1 floor for meaningful content. If someone "fixes" this by
      // darkening accent, dark-text-on-accent above will start failing —
      // which is the intended tension. Accent must never render text/icons
      // directly on a white surface.
      expect(_contrast(ManaColors.accent, _white), lessThan(3.0));
    });

    test('white on accent would be unreadable', () {
      expect(_contrast(_white, ManaColors.accent), lessThan(2.0));
    });
  });

  group('status colours are colour-vision-deficiency safe', () {
    test('each status clears AA on white', () {
      expect(_contrast(ManaColors.statusGood, _white), greaterThanOrEqualTo(4.5));
      expect(_contrast(ManaColors.statusBad, _white), greaterThanOrEqualTo(4.5));
      expect(_contrast(ManaColors.statusWarn, _white), greaterThanOrEqualTo(4.5));
    });

    test('good and bad separate on the blue axis, which red-green CVD keeps', () {
      // The mechanism: teal retains a strong blue channel, red-orange has
      // almost none. Under deuteranopia/protanopia the two then read as
      // blue-ish vs yellow-ish rather than as two similar muddy tones.
      final goodBlue = (ManaColors.statusGood.b * 255.0).round();
      final badBlue = (ManaColors.statusBad.b * 255.0).round();
      expect(goodBlue - badBlue, greaterThanOrEqualTo(48),
          reason: 'statusGood must carry markedly more blue than statusBad');
    });

    test('good and bad also differ in luminance, for greyscale robustness', () {
      // So the pair survives monochrome rendering and heavy glare, where hue
      // information is effectively gone.
      final ratio = _contrast(ManaColors.statusGood, ManaColors.statusBad);
      expect(ratio, greaterThanOrEqualTo(1.2),
          reason: 'statusGood and statusBad must not sit at the same lightness');
    });

    test('warn is distinguishable from the accent', () {
      // Both are amber-family. Warn must never be mistaken for a tappable
      // action, so it has to be clearly darker.
      expect(_luminance(ManaColors.statusWarn),
          lessThan(_luminance(ManaColors.accent) * 0.5));
    });

    test('unverified ring is caution, not failure', () {
      // Previously identical to statusBad, which overstated a merely
      // not-yet-verified state.
      expect(ManaColors.ringUnverified, isNot(ManaColors.statusBad));
    });
  });
}

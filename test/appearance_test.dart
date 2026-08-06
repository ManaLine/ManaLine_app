import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/colors.dart';
import 'package:mana_line/shared/appearance_screen.dart';
import 'package:mana_line/shared/appearance_state.dart';
import 'package:mana_line/shared/mana_biometric.dart';

import 'support/mana_harness.dart';

void main() {
  group('text size scale', () {
    test('normal is exactly 1.0, so it changes nothing', () {
      // If the default were anything else, every existing layout test would be
      // measuring a size the app never actually renders at.
      expect(ManaTextSize.normal.scale, 1.0);
    });

    test('sizes increase in order and stay inside the tested range', () {
      final scales = ManaTextSize.values.map((v) => v.scale).toList();
      for (var i = 1; i < scales.length; i++) {
        expect(scales[i], greaterThan(scales[i - 1]));
      }
      // Layout is proven to 2.0x. The cap sits well below that because this
      // multiplies with the device's own setting rather than replacing it —
      // 1.3 here on a phone already at 1.6 lands near the tested ceiling.
      expect(scales.last, lessThanOrEqualTo(1.3));
      expect(scales.first, greaterThanOrEqualTo(0.85));
    });

    test('an unknown stored value falls back to normal', () {
      // A preference written by a future version, or a corrupt read, must not
      // leave the app at an unusable size.
      expect(ManaTextSize.fromName('gigantic'), ManaTextSize.normal);
      expect(ManaTextSize.fromName(null), ManaTextSize.normal);
    });

    test('every size round-trips through its stored name', () {
      for (final v in ManaTextSize.values) {
        expect(ManaTextSize.fromName(v.name), v);
      }
    });
  });

  group('appearance screen', () {
    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const AppearanceScreen(),
          textScale: scale,
          surfaceSize: const Size(360, 1600),
        );
        expectNoLayoutFault(tester, 'Appearance at ${scale}x');
      });
    }

    testWidgets('offers every size and previews a real amount',
        (tester) async {
      await pumpManaScreen(
        tester,
        const AppearanceScreen(),
        surfaceSize: const Size(360, 1600),
      );
      for (final v in ManaTextSize.values) {
        expect(find.text(v.label.replaceRange(0, 1, v.label[0].toUpperCase())),
            findsOneWidget);
      }
      // The preview shows a rupee figure, not lorem text — reading amounts is
      // the reason someone changes text size in this app.
      expect(find.textContaining('12,450'), findsOneWidget);
    });

    testWidgets('offers all three theme choices', (tester) async {
      await pumpManaScreen(
        tester,
        const AppearanceScreen(),
        surfaceSize: const Size(360, 1600),
      );
      expect(find.text('Match My Phone'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });
  });

  group('dark palette', () {
    test('every token differs from light — no half-applied palette', () {
      // If a token were left pointing at its light value, that one element
      // would stay bright on a dark screen. Surfaces and text are the ones
      // that would show it worst.
      const l = ManaPalette.light;
      const d = ManaPalette.dark;
      expect(d.surface, isNot(l.surface));
      expect(d.surfaceMuted, isNot(l.surfaceMuted));
      expect(d.surfaceSunken, isNot(l.surfaceSunken));
      expect(d.textPrimary, isNot(l.textPrimary));
      expect(d.textSecondary, isNot(l.textSecondary));
      expect(d.brand, isNot(l.brand));
      expect(d.statusGood, isNot(l.statusGood));
      expect(d.statusBad, isNot(l.statusBad));
      expect(d.statusWarn, isNot(l.statusWarn));
    });

    test('the scaffold sits behind cards in both palettes', () {
      // Light: cards are white on a grey page. Dark: cards must be LIGHTER
      // than the page, not darker, or they sink instead of lifting.
      expect(ManaPalette.light.surface.computeLuminance(),
          greaterThan(ManaPalette.light.surfaceMuted.computeLuminance()));
      expect(ManaPalette.dark.surface.computeLuminance(),
          greaterThan(ManaPalette.dark.surfaceMuted.computeLuminance()));
    });

    test('the CVD-safe split survives in dark', () {
      // The whole point of the teal/orange pair is that they separate on the
      // blue-yellow axis, which red-green colour blindness leaves intact.
      // Inverting the light values would have destroyed that, and these two
      // carry money meaning — Short versus Excess, penalty, defaulted.
      final good = ManaPalette.dark.statusGood;
      final bad = ManaPalette.dark.statusBad;
      // ignore: deprecated_member_use
      expect(good.blue, greaterThan(bad.blue + 60),
          reason: 'teal must keep a much stronger blue channel than orange');
      // And they must not collapse in greyscale either.
      expect((good.computeLuminance() - bad.computeLuminance()).abs(),
          greaterThan(0.02));
    });

    test('body text clears 7:1 against its own surface in both palettes', () {
      // The light palette was built to AAA for body text because this is read
      // outdoors. Dark must not quietly drop below that.
      double ratio(Color fg, Color bg) {
        final a = fg.computeLuminance(), b = bg.computeLuminance();
        final hi = a > b ? a : b, lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      expect(ratio(ManaPalette.light.textPrimary, ManaPalette.light.surface),
          greaterThan(7.0));
      expect(ratio(ManaPalette.dark.textPrimary, ManaPalette.dark.surface),
          greaterThan(7.0));
      // Secondary text is labels-only, so AA is the bar, not AAA.
      expect(ratio(ManaPalette.dark.textSecondary, ManaPalette.dark.surface),
          greaterThan(4.5));
    });

    test('status colours stay legible on the dark surface', () {
      double ratio(Color fg, Color bg) {
        final a = fg.computeLuminance(), b = bg.computeLuminance();
        final hi = a > b ? a : b, lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final c in [
        ManaPalette.dark.statusGood,
        ManaPalette.dark.statusBad,
        ManaPalette.dark.statusWarn,
        ManaPalette.dark.brand,
      ]) {
        expect(ratio(c, ManaPalette.dark.surface), greaterThan(4.5));
      }
    });

    test('swapping the palette moves every ManaColors token', () {
      // ManaColors is global mutable state, which is the whole mechanism —
      // this asserts the swap actually reaches the token getters, since 840
      // call sites depend on exactly that.
      ManaColors.use(ManaPalette.light);
      final lightSurface = ManaColors.surface;
      expect(ManaColors.isDark, isFalse);

      ManaColors.use(ManaPalette.dark);
      expect(ManaColors.surface, isNot(lightSurface));
      expect(ManaColors.isDark, isTrue);

      // Left as the tests found it — a leaked dark palette would silently
      // change what every other widget test renders.
      ManaColors.use(ManaPalette.light);
    });
  });

  group('biometric outcomes', () {
    test('every result has its own words', () {
      // "You cancelled", "no hardware" and "wrong finger" are different things
      // to someone at a login screen; one generic message would tell them
      // nothing about what to do next.
      final messages = <String>{
        for (final r in ManaBiometricResult.values)
          if (r != ManaBiometricResult.ok) ManaBiometric.messageFor(r),
      };
      expect(messages.length, ManaBiometricResult.values.length - 1);
    });

    test('every failure points at the PIN as the way through', () {
      // Biometric is a convenience over the PIN, never a gate in front of it.
      // A message that does not mention the PIN leaves someone stuck.
      for (final r in ManaBiometricResult.values) {
        if (r == ManaBiometricResult.ok) continue;
        expect(ManaBiometric.messageFor(r).toUpperCase(), contains('PIN'),
            reason: '$r should tell the person they can still use their PIN');
      }
    });
  });
}

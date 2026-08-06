import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('says dark mode is absent rather than leaving a gap',
        (tester) async {
      await pumpManaScreen(
        tester,
        const AppearanceScreen(),
        surfaceSize: const Size(360, 1600),
      );
      // Stated out loud so nobody hunts for a switch that is not there.
      expect(find.textContaining('Dark mode is not available'), findsOneWidget);
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

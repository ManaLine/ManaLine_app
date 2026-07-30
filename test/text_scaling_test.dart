import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_amount.dart';
import 'package:mana_line/design/components/mana_stat_strip.dart';
import 'package:mana_line/design/components/mana_text.dart';

/// Guards against the overflow class of bug, which is what actually broke when
/// the text floors were raised.
///
/// WHAT HAPPENED: five screens sized a horizontal stat strip with a hard
/// `SizedBox(height: 84)`. Once status-pill labels moved to the 13sp floor the
/// content needed 90, and every one of them threw
/// "A RenderFlex overflowed by 6.0 pixels". Analyze cannot see this — overflow
/// only exists once real constraints are applied — and neither can a test that
/// renders at the default text scale only.
///
/// THE REAL LESSON is not "84 was too small", it is that a fixed pixel height
/// wrapping scalable text is always a latent overflow. The same box would have
/// broken the first time a user raised their system font size, which older
/// Owners routinely do. So these tests exercise 1.0x AND large scales: a fix
/// that only works at 1.0x is not a fix.
///
/// Flutter surfaces overflow as a thrown FlutterError during layout, so
/// `tester.takeException()` is a real assertion here, not a formality.
void main() {
  /// The real component the five screens now use. Testing the component
  /// itself, not a copy of it, is the point — a reproduction can drift from
  /// what ships and then pass while production overflows.
  Widget statStrip() => const ManaStatStrip(
        stats: [
          // The longest labels in the app, which is what actually broke the
          // fixed-height version.
          ManaStat(value: '12', label: 'Pending Acceptance', status: ManaStatus.warn),
          ManaStat(value: '3', label: 'Pending Invitations', status: ManaStatus.warn),
          ManaStat(value: '0', label: 'Active', status: ManaStatus.good),
        ],
      );

  Future<void> pumpAtScale(WidgetTester tester, Widget child, double scale) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  group('stat strip survives text scaling', () {
    // 2.0 is not hypothetical: Android's font-size slider plus display-size
    // scaling reach it, and this app's Owners skew older.
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('no overflow at ${scale}x', (tester) async {
        await pumpAtScale(tester, statStrip(), scale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'stat strip overflowed at ${scale}x — a fixed height cannot '
              'wrap scalable text',
        );
      });
    }
  });

  group('money survives text scaling', () {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('a label-and-amount row does not overflow at ${scale}x', (tester) async {
        // The other shape flagged as at-risk: a label on the left and a
        // currency figure on the right, competing for one row's width.
        await pumpAtScale(
          tester,
          const Row(
            children: [
              Expanded(child: ManaText.raw('Total Outstanding Balance')),
              ManaAmount(1234567),
            ],
          ),
          scale,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an amount ellipsises rather than overflowing when squeezed', (tester) async {
      // Deliberate behaviour: money must never wrap mid-number, so when there
      // genuinely is not enough width it truncates visibly instead of throwing
      // or silently reflowing into something misreadable.
      await pumpAtScale(
        tester,
        const SizedBox(width: 40, child: ManaAmount(123456789)),
        1.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

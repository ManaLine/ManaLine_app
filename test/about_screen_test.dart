import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/about_screen.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('About survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const AboutScreen(),
        textScale: scale,
        surfaceSize: const Size(360, 3000),
      );
      expectNoLayoutFault(tester, 'About at ${scale}x');
    });
  }

  testWidgets('every promise the terms make is actually on screen',
      (tester) async {
    await pumpManaScreen(
      tester,
      const AboutScreen(),
      surfaceSize: const Size(360, 3000),
    );

    // These five are the substance of the terms, not decoration. If one goes
    // missing the app is claiming something different from what was agreed.
    expect(find.textContaining('does not move money'), findsOneWidget);
    expect(find.textContaining('only people you have given a role'),
        findsOneWidget);
    expect(find.textContaining('share your PIN'), findsOneWidget);
    expect(find.textContaining('Line Score'), findsWidgets);
    expect(find.textContaining('90 days'), findsOneWidget);
  });

  testWidgets('Line Score is described as arithmetic, not judgement',
      (tester) async {
    await pumpManaScreen(
      tester,
      const AboutScreen(),
      surfaceSize: const Size(360, 3000),
    );
    // The explicit list of things it does NOT use is the part that makes the
    // score defensible to someone it has scored badly.
    expect(find.textContaining('caste'), findsOneWidget);
    expect(find.textContaining('nothing about you as a person'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/screens/lr_001_system_startup.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// LR-001 shows the brand mark at opening size — as wide as the screen allows.
///
/// It had no test at all before, which is why it is worth one now: a
/// full-width image sharing a Column with the failure card and its retry
/// button is precisely the shape this app overflows in, and it only shows up
/// at large text scale on a short screen.
///
/// The screen is pinned in its FAILURE state on purpose. On success it routes
/// straight to /lr-002 or /lr-009 and there is nothing left to measure; the
/// failure state is also the fullest the screen ever gets, so it is the one
/// that has to fit.
class _FailingTranslationCache extends FakeTranslationCache {
  @override
  Future<void> load() async {
    lastError = 'no route to host';
  }
}

const _teluguSplash = <String, Map<String, String>>{
  'every_rupee_counts': {'English': 'EVERY ₹ COUNTS', 'Telugu': 'ప్రతి ₹ లెక్కలోకి వస్తుంది'},
  'unable_to_connect_note': {
    'English': 'Unable to connect. Retrying…',
    'Telugu': 'కనెక్ట్ చేయలేకపోయాము. మళ్ళీ ప్రయత్నిస్తున్నాము…',
  },
  'retry': {'English': 'Retry', 'Telugu': 'మళ్ళీ ప్రయత్నించండి'},
  'loading_ellipsis': {'English': 'Loading…', 'Telugu': 'లోడ్ అవుతోంది…'},
};

Future<void> _pumpSplash(
  WidgetTester tester, {
  double textScale = 1.0,
  ManaLanguage language = ManaLanguage.english,
}) async {
  await pumpManaScreen(
    tester,
    const SystemStartupScreen(),
    textScale: textScale,
    language: language,
    translations: _teluguSplash,
    overrides: [
      translationCacheProvider.overrideWithValue(_FailingTranslationCache()),
    ],
  );
}

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('LR-001 survives text scale ${scale}x', (tester) async {
      await _pumpSplash(tester, textScale: scale);
      expectNoLayoutFault(tester, 'LR-001 at ${scale}x');
    });

    testWidgets('LR-001 survives text scale ${scale}x in Telugu', (tester) async {
      await _pumpSplash(tester, textScale: scale, language: ManaLanguage.telugu);
      expectNoLayoutFault(tester, 'LR-001 at ${scale}x in Telugu');
    });
  }

  testWidgets('the mark fills the width, with only a small gap', (tester) async {
    await _pumpSplash(tester);

    final logo = tester.getRect(find.byType(Image));
    final screen = tester.getRect(find.byType(Scaffold));

    // "Edge to edge with minimal gap": at least 90% of the width, and never
    // wider than the screen.
    expect(logo.width, greaterThan(screen.width * 0.9));
    expect(logo.width, lessThanOrEqualTo(screen.width));
  });

  testWidgets('the wordmark is not drawn twice', (tester) async {
    await _pumpSplash(tester);

    // "MANA LINE" and the tagline are already inside the mark. They used to be
    // laid out again as text underneath it, which at this size was the same
    // two lines twice.
    expect(find.text('MANA LINE'), findsNothing);
    expect(find.textContaining('COUNTS'), findsNothing);
  });

  testWidgets('a screen reader still gets the name and tagline', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpSplash(tester);

    // The only reader that lost anything when the duplicate text went.
    expect(
      find.bySemanticsLabel(RegExp('MANA LINE')),
      findsOneWidget,
    );
    handle.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mana_line/design/components/mana_brand_mark.dart';
import 'package:mana_line/features/login_registration/screens/lr_002_workspace_choice.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// LR-002 Workspace Choice.
///
/// WHY LANDSCAPE IS HERE: this screen shipped an overflow that none of the
/// existing layout tests could have caught, because every one of them pumps
/// a 360x640 portrait surface. The screen centred itself with two Spacers,
/// which divide up whatever vertical space is LEFT OVER — so it only breaks
/// when the viewport is SHORT, not when it is narrow. Rotating a real
/// handset overflowed it by 41px.
///
/// Text scale alone does not reproduce it either: raising the scale grows
/// the fixed children, but 640px of height still absorbs them. The short
/// axis is the variable that matters, so it is now a variable in the test.
void main() {
  for (final scale in kManaTextScales) {
    testWidgets('LR-002 survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const WorkspaceChoiceScreen(),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'LR-002 at ${scale}x');
    });

    testWidgets('LR-002 survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const WorkspaceChoiceScreen(),
        textScale: scale,
        language: ManaLanguage.telugu,
      );
      expectNoLayoutFault(tester, 'LR-002 at ${scale}x in Telugu');
    });
  }

  // The regression itself. 640x360 is the same phone rotated.
  for (final scale in kManaTextScales) {
    testWidgets('LR-002 survives landscape at ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const WorkspaceChoiceScreen(),
        textScale: scale,
        surfaceSize: const Size(640, 360),
      );
      expectNoLayoutFault(tester, 'LR-002 landscape at ${scale}x');
    });
  }

  // A genuinely cramped viewport — split-screen, or a small phone in
  // landscape with the navigation bar taking its share.
  testWidgets('LR-002 survives a very short viewport', (tester) async {
    await pumpManaScreen(
      tester,
      const WorkspaceChoiceScreen(),
      surfaceSize: const Size(360, 280),
    );
    expectNoLayoutFault(tester, 'LR-002 at 360x280');
  });

  testWidgets('LR-002 shows both products', (tester) async {
    await pumpManaScreen(tester, const WorkspaceChoiceScreen());
    expect(find.text('Mana Finance'), findsOneWidget);
    // Cheeti, not Chits: the product is spelled Cheeti everywhere in the UI
    // now. This test caught the rename, which is what it is for.
    expect(find.text('Mana Cheeti'), findsOneWidget);
  });

  testWidgets('LR-002 shows the tagline under the app name', (tester) async {
    await pumpManaScreen(tester, const WorkspaceChoiceScreen());
    expect(find.text(kManaTagline), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/account_closure_screen.dart';

import 'support/mana_harness.dart';

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Account closure survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const AccountClosureScreen(),
        textScale: scale,
        surfaceSize: const Size(360, 1600),
      );
      expectNoLayoutFault(tester, 'Account closure at ${scale}x');
    });
  }

  testWidgets('both options say they are reversible', (tester) async {
    await pumpManaScreen(
      tester,
      const AccountClosureScreen(),
      surfaceSize: const Size(360, 1600),
    );

    // The reversibility is the whole reason this screen is safe to offer at
    // all. If either sentence goes missing, the screen starts reading as a
    // one-way door and people will avoid the reversible option or be shocked
    // by the other.
    expect(find.textContaining('switch it back on'), findsOneWidget);
    expect(find.textContaining('90 days'), findsWidgets);
    expect(find.textContaining('change your mind'), findsOneWidget);
  });

  testWidgets('an owner is warned before trying, not after', (tester) async {
    await pumpManaScreen(
      tester,
      const AccountClosureScreen(),
      surfaceSize: const Size(360, 1600),
    );
    // The server refuses an Owner with a live business. Saying so up front is
    // the difference between a clear rule and a confusing error.
    expect(find.textContaining('transfer or close it first'), findsOneWidget);
  });

  testWidgets('neither action fires without a confirmation', (tester) async {
    await pumpManaScreen(
      tester,
      const AccountClosureScreen(),
      surfaceSize: const Size(360, 1600),
    );

    await tester.tap(find.text('Switch Off'));
    await tester.pumpAndSettle();
    // A dialog, not an immediate call. Tapping a destructive control once
    // must never be enough.
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}

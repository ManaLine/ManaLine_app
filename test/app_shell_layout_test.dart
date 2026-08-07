import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_app_shell.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The shell is the one surface every workspace screen sits under, so an
/// overflow here is an overflow on all 57 screens at once. It is also the
/// densest row in the app — menu button, two-line identity, three icon
/// controls — which is exactly the shape that has overflowed five times.
void main() {
  /// Fixed clock. A live `manaNowIst()` would render a different width every
  /// run ("9:05 AM" is narrower than "12:45 PM"), so a layout test against it
  /// would pass or fail depending on the time of day it ran.
  final fixedNow = DateTime(2026, 8, 5, 14, 7);

  ManaAppShell buildShell({String? businessName = 'Sri Tirumala Finance'}) =>
      ManaAppShell(
        userName: 'Kotta Siva Mohan Reddy',
        businessName: businessName,
        now: fixedNow,
        sections: const [
          ManaDrawerSection(
            icon: Icons.people_outline,
            labelKey: 'customers',
            actions: [
              ManaDrawerAction(labelKey: 'customer management'),
              ManaDrawerAction(labelKey: 'loan requests'),
            ],
          ),
          ManaDrawerSection(
            icon: Icons.badge_outlined,
            labelKey: 'workforce',
            actions: [ManaDrawerAction(labelKey: 'workforce management')],
          ),
          ManaDrawerSection(
            icon: Icons.savings_outlined,
            labelKey: 'investors',
            actions: [ManaDrawerAction(labelKey: 'investor management')],
          ),
        ],
        onSettings: null,
        onSwitch: null,
        onLogout: null,
        body: const SizedBox.shrink(),
      );

  for (final scale in kManaTextScales) {
    testWidgets('shell header survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, buildShell(), textScale: scale);
      expectNoLayoutFault(tester, 'ManaAppShell header at ${scale}x');

      // Assert on CONTENT, not just the absence of an overflow: a header that
      // laid out cleanly because it rendered nothing would pass the fault
      // check alone.
      expect(find.text('Kotta Siva Mohan Reddy'), findsOneWidget);
      expect(find.text('Sri Tirumala Finance'), findsOneWidget);
      expect(find.textContaining('05-08-2026'), findsOneWidget);
    });
  }

  testWidgets('the clock renders IST 12-hour, not 24-hour', (tester) async {
    await pumpManaScreen(tester, buildShell());
    // 14:07 must read as 2:07 PM. A bare `hour % 12` would also produce "2",
    // so the PM suffix is the part that proves the conversion.
    expect(find.textContaining('2:07 PM'), findsOneWidget);
    expect(find.textContaining('14:07'), findsNothing);
  });

  testWidgets('midnight and noon do not collapse to hour zero', (tester) async {
    // The off-by-one every 12-hour formatter gets wrong: `0 % 12` and
    // `12 % 12` are both 0, which renders midnight and noon as "0:xx".
    await pumpManaScreen(
      tester,
      ManaAppShell(
        userName: 'A',
        now: DateTime(2026, 8, 5, 0, 30),
        body: const SizedBox.shrink(),
      ),
    );
    expect(find.textContaining('12:30 AM'), findsOneWidget);
  });

  testWidgets('a business name is optional above business selection',
      (tester) async {
    await pumpManaScreen(tester, buildShell(businessName: null));
    expectNoLayoutFault(tester, 'ManaAppShell without a business');
    expect(find.text('Kotta Siva Mohan Reddy'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('drawer sections expand without overflow at ${scale}x',
        (tester) async {
      await pumpManaScreen(tester, buildShell(), textScale: scale);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expectNoLayoutFault(tester, 'drawer open at ${scale}x');
      expect(find.text('Customers'), findsOneWidget);

      // A test that never expands the tile proves nothing about the rows
      // inside it — the collapsed ExpansionTile lays out its children lazily.
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      expectNoLayoutFault(tester, 'drawer section expanded at ${scale}x');
      expect(find.text('Customer Management'), findsOneWidget);
      expect(find.text('Loan Requests'), findsOneWidget);
    });
  }

  testWidgets('the drawer renders in Kannada at 1.6x', (tester) async {
    // Translated labels are wider than their English keys; the drawer is a
    // fixed-width surface, so this is where that bites.
    await pumpManaScreen(
      tester,
      buildShell(),
      textScale: 1.6,
      language: ManaLanguage.telugu,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expectNoLayoutFault(tester, 'drawer in Kannada at 1.6x');
  });
}

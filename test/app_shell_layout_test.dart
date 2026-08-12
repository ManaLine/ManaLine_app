import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_app_shell.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The shell is the one surface every workspace screen sits under, so an
/// overflow here is an overflow on all 57 screens at once.
///
/// The header used to be two rows — menu, two-line identity and per-screen
/// actions above; date, clock and Settings/Switch/Logout below — which is
/// exactly the shape that has overflowed five times. It is one row now, and
/// everything that made the second row lives in the drawer, so the assertions
/// below follow it there.
void main() {
  /// Fixed clock. A live `manaNowIst()` would render a different width every
  /// run ("9:05 AM" is narrower than "12:45 PM"), so a layout test against it
  /// would pass or fail depending on the time of day it ran.
  ///
  /// Passing it also suppresses the drawer's one-second timer, so these tests
  /// never leave a live periodic timer behind.
  final fixedNow = DateTime(2026, 8, 5, 14, 7, 9);

  ManaAppShell buildShell({
    String? businessName = 'Sri Tirumala Finance',
    VoidCallback? onLogout,
  }) =>
      ManaAppShell(
        userName: 'Kotta Siva Mohan Reddy',
        businessName: businessName,
        now: fixedNow,
        sections: [
          const ManaDrawerSection(
            icon: Icons.people_outline,
            labelKey: 'customers',
            actions: [
              ManaDrawerAction(labelKey: 'customer management'),
              ManaDrawerAction(labelKey: 'loan requests'),
            ],
          ),
          const ManaDrawerSection(
            icon: Icons.badge_outlined,
            labelKey: 'workforce',
            actions: [ManaDrawerAction(labelKey: 'workforce management')],
          ),
          const ManaDrawerSection(
            icon: Icons.savings_outlined,
            labelKey: 'investors',
            actions: [ManaDrawerAction(labelKey: 'investor management')],
          ),
          ...manaGlobalDrawerSections(onLogout: onLogout),
        ],
        body: const SizedBox.shrink(),
      );

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
  }

  for (final scale in kManaTextScales) {
    testWidgets('shell header survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, buildShell(), textScale: scale);
      expectNoLayoutFault(tester, 'ManaAppShell header at ${scale}x');

      // Assert on CONTENT, not just the absence of an overflow: a header that
      // laid out cleanly because it rendered nothing would pass the fault
      // check alone.
      expect(find.text('Sri Tirumala Finance'), findsOneWidget);

      // The clock belongs to the drawer now. Finding it in the header would
      // mean the second row had come back.
      expect(find.textContaining('05-08-2026'), findsNothing);
    });
  }

  testWidgets('the header is a single row of chrome', (tester) async {
    // The regression this guards: the header grew back to two rows and ate a
    // third of a 640dp phone before any content was drawn.
    await pumpManaScreen(tester, buildShell());
    final header = tester.getSize(find.byType(ManaAppShell));
    final headerHeight = tester
        .getRect(find.text('Sri Tirumala Finance'))
        .bottom;
    expect(headerHeight, lessThan(header.height * 0.25),
        reason: 'the header title should sit in the top strip, not a block');
  });

  testWidgets('the drawer clock renders IST 12-hour with seconds',
      (tester) async {
    await pumpManaScreen(tester, buildShell());
    await openDrawer(tester);
    // 14:07:09 must read as 2:07:09 PM. A bare `hour % 12` would also produce
    // "2", so the PM suffix is the part that proves the conversion.
    expect(find.textContaining('2:07:09 PM'), findsOneWidget);
    expect(find.textContaining('14:07'), findsNothing);
    expect(find.textContaining('05-08-2026'), findsOneWidget);
  });

  testWidgets('midnight and noon do not collapse to hour zero', (tester) async {
    // The off-by-one every 12-hour formatter gets wrong: `0 % 12` and
    // `12 % 12` are both 0, which renders midnight and noon as "0:xx".
    await pumpManaScreen(
      tester,
      ManaAppShell(
        userName: 'A',
        now: DateTime(2026, 8, 5, 0, 30, 5),
        body: const SizedBox.shrink(),
      ),
    );
    await openDrawer(tester);
    expect(find.textContaining('12:30:05 AM'), findsOneWidget);
  });

  testWidgets('the header falls back to the user name before a business',
      (tester) async {
    await pumpManaScreen(tester, buildShell(businessName: null));
    expectNoLayoutFault(tester, 'ManaAppShell without a business');
    // Never an anonymous bar: with no business chosen the person's own name
    // is what the header shows.
    expect(find.text('Kotta Siva Mohan Reddy'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('drawer sections expand without overflow at ${scale}x',
        (tester) async {
      await pumpManaScreen(tester, buildShell(), textScale: scale);

      await openDrawer(tester);
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

  testWidgets('global rows are plain tiles that act on the first tap',
      (tester) async {
    // Profile/Switch/Settings/Logout have nothing beneath them, so they must
    // NOT render as ExpansionTiles — a chevron opening a list of one would be
    // two taps to do one thing.
    var loggedOut = false;
    await pumpManaScreen(
      tester,
      buildShell(onLogout: () => loggedOut = true),
    );
    await openDrawer(tester);

    expect(find.text('Logout'), findsOneWidget);
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(loggedOut, isTrue);
  });

  testWidgets('a global row with no callback renders disabled, not missing',
      (tester) async {
    // "Exists, not yours" rather than a row that silently is not there — a
    // missing row reads as a bug to someone who has seen it on a colleague's
    // phone.
    await pumpManaScreen(tester, buildShell());
    await openDrawer(tester);

    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Settings'), matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isFalse);
  });

  testWidgets('the drawer renders in Telugu at 1.6x', (tester) async {
    // Translated labels are wider than their English keys; the drawer is a
    // fixed-width surface, so this is where that bites.
    await pumpManaScreen(
      tester,
      buildShell(),
      textScale: 1.6,
      language: ManaLanguage.telugu,
    );
    await openDrawer(tester);
    expectNoLayoutFault(tester, 'drawer in Telugu at 1.6x');
  });
}

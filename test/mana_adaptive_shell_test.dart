import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_adaptive_shell.dart';
import 'package:mana_line/design/components/mana_header.dart';

void main() {
  // ManaNavItem's real constructor requires `selectedIcon` (the filled
  // counterpart shown when selected) alongside `icon` — the brief's sample
  // omitted it. Adjusted here to match the widget, not the other way round.
  final items = [
    ManaNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'home', onTap: () {}),
    ManaNavItem(icon: Icons.list_outlined, selectedIcon: Icons.list, label: 'history', onTap: () {}),
  ];

  Widget shell() => MaterialApp(
        home: ManaAdaptiveShell(
          items: items,
          currentIndex: 0,
          child: const SizedBox(key: Key('content')),
        ),
      );

  testWidgets('a phone keeps the bottom nav and shows no rail', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(ManaBottomNav), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a tablet still keeps the bottom nav', (tester) async {
    // 820 is medium: two columns fit, a rail does not without crowding the
    // content it is supposed to sit beside.
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(ManaBottomNav), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a desk gets the rail and drops the bottom nav', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(ManaBottomNav), findsNothing);
  });

  testWidgets('the content is always present', (tester) async {
    for (final w in const [390.0, 820.0, 1440.0]) {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(shell());
      expect(find.byKey(const Key('content')), findsOneWidget,
          reason: 'content vanished at ${w}px');
    }
  });
}

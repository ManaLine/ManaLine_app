import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/design/components/mana_web_frame.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// What [ManaWebFrame] actually sees when a real router drives it.
///
/// WHY THIS FILE EXISTS. `mana_web_frame_test.dart` passes `currentLocation`
/// as a literal string — deliberately, so the widget can be tested without
/// standing up a router. That proves the widget's own logic and nothing about
/// the wiring in `main.dart`, which is
///
///   currentLocation: () => router.routerDelegate.currentConfiguration.uri.path
///
/// On 2026-09-18 `/web-home` was added to [kManaWideRoutes], every test
/// passed, and the deployed page was still rendered in the 480px phone
/// column. The widget was right; the string it was being handed was not.
void main() {
  Future<double> contentWidth(
    WidgetTester tester, {
    required String initial,
    String? thenGoTo,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: initial,
      routes: [
        for (final path in const ['/lr-001', '/lr-009', '/web-home'])
          GoRoute(
            path: path,
            builder: (_, __) => Container(key: const Key('content')),
          ),
      ],
    );
    addTearDown(router.dispose);

    // Wired EXACTLY as main.dart wires it, because the wiring is the thing
    // under test.
    await tester.pumpWidget(MaterialApp.router(
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      builder: (context, child) => ManaWebFrame(
        currentLocation: () =>
            router.routerDelegate.currentConfiguration.uri.path,
        routeListenable: router.routeInformationProvider,
        isWeb: () => true,
        child: child!,
      ),
    ));
    await tester.pumpAndSettle();

    if (thenGoTo != null) {
      router.go(thenGoTo);
      await tester.pumpAndSettle();
    }
    return tester.getSize(find.byKey(const Key('content'))).width;
  }

  testWidgets('a signed-out page opened directly gets the reading measure',
      (tester) async {
    // The case the Owner hit: type the URL, or reload on it. Before the fix
    // this was 480 for every route alike, because the path being matched
    // against was the empty string.
    expect(await contentWidth(tester, initial: '/lr-009'),
        kManaWebReadingMeasure);
  });

  testWidgets('a signed-in route is passed straight through', (tester) async {
    // Its navigation and its measure come from the ShellRoute now. If this
    // ever clamps again, the rail goes back to floating in the middle of a
    // wide monitor.
    expect(await contentWidth(tester, initial: '/web-home'), 1440);
  });

  testWidgets('navigating between the two switches correctly', (tester) async {
    // THE HALF THAT PROVES THE LISTENER FIRES. Before the fix the builder ran
    // once and never again, so whatever was read at startup was the only
    // value it ever had -- which is why a route could be on the list and
    // still render as a phone.
    expect(
      await contentWidth(tester, initial: '/lr-009', thenGoTo: '/web-home'),
      1440,
    );
    expect(
      await contentWidth(tester, initial: '/web-home', thenGoTo: '/lr-009'),
      kManaWebReadingMeasure,
    );
  });
}

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
        for (final path in const ['/lr-001', '/web-home', '/ow-001'])
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

  testWidgets('a wide route opened directly gets the desk measure',
      (tester) async {
    // The case the Owner hit: type the URL, or reload on it. Before the fix
    // this was 480 -- a route could be in kManaWideRoutes and still render
    // as a phone, because the path being matched against was ''.
    expect(await contentWidth(tester, initial: '/web-home'),
        kManaDeskContentMax);
  });

  testWidgets('a wide route navigated TO gets it too', (tester) async {
    // The other half: arriving from somewhere else, which is what happens
    // after signing in.
    expect(
      await contentWidth(tester, initial: '/lr-001', thenGoTo: '/web-home'),
      kManaDeskContentMax,
    );
  });

  testWidgets('a route with no bespoke layout gets the reading measure',
      (tester) async {
    // Not the window, and not a phone column either. 840 is what a screen
    // drawn for 360dp can be given without its buttons becoming bands.
    expect(await contentWidth(tester, initial: '/ow-001'),
        kManaWebReadingMeasure);
  });

  testWidgets('leaving a wide route narrows back to the reading measure',
      (tester) async {
    // The half that proves the listener fires. Before the fix the builder
    // ran once and never again, so a value read at startup was the only
    // value it ever had.
    expect(
      await contentWidth(tester, initial: '/web-home', thenGoTo: '/ow-001'),
      kManaWebReadingMeasure,
    );
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/app/web_router.dart';
import 'package:mana_line/design/components/mana_header.dart';
import 'package:mana_line/features/web/state/web_destinations.dart';
import 'package:mana_line/features/web/widgets/mana_web_shell.dart';

import 'support/mana_harness.dart';

/// Every signed-in page on the website has the site's navigation.
///
/// Before 2026-09-18 the rail existed on `/web-home` and nowhere else, so 20
/// of the 21 signed-in web routes were a column of content with no way off
/// them but the browser's Back button. The Owner's instruction was exactly
/// that: "build the navigation on all pages".
/// Source with comment lines removed, because these assertions search for
/// class and route names that the surrounding prose also mentions.
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _routerSource() => _code('lib/app/web_router.dart');

void main() {
  group('the router puts every signed-in route inside the shell', () {
    test('and leaves every signed-out route outside it', () {
      final src = _routerSource();
      final shellAt = src.indexOf('ShellRoute(');
      expect(shellAt, isNonNegative, reason: 'the ShellRoute has gone');

      // Everything after the ShellRoute opens is inside it, because it is the
      // last entry in the routes list. A path declared before it is outside.
      final before = src.substring(0, shellAt);
      final inside = src.substring(shellAt);

      for (final route in kManaWebAllowedRoutes) {
        final declared = "path: '$route'";
        if (route.startsWith('/lr-')) {
          expect(before, contains(declared),
              reason: '$route is signed-out and must stay OUT of the shell: '
                  'every destination in the rail needs a session, so a rail '
                  'on the login page is a list of links back to the login '
                  'page');
          expect(inside, isNot(contains(declared)));
        } else {
          expect(inside, contains(declared),
              reason: '$route is signed-in and has no navigation on it — a '
                  'page with no way off it but the browser Back button is '
                  'the thing this shell exists to stop');
        }
      }
    });

    test('the split is 12 signed-out and 21 signed-in', () {
      // Stated as a number so adding a route makes somebody decide which
      // side it belongs on rather than inheriting whichever is nearer.
      final out = kManaWebAllowedRoutes.where((r) => r.startsWith('/lr-'));
      expect(out, hasLength(12));
      expect(kManaWebAllowedRoutes.length - out.length, 21);
    });
  });

  group('the rail', () {
    Future<List<String>> railLabels(
      WidgetTester tester, {
      required String location,
      double width = 1440,
    }) async {
      await pumpManaScreen(
        tester,
        ManaWebShell(location: location, child: const SizedBox()),
        surfaceSize: Size(width, 900),
        location: location,
      );
      await tester.pump();
      return tester
          .widgetList<Text>(find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byType(Text),
          ))
          .map((t) => t.data ?? '')
          .toList();
    }

    testWidgets('leads with Home and then the role destinations',
        (tester) async {
      final labels = await railLabels(tester, location: '/ow-013');
      expect(labels.first, 'Home');
      expect(labels, contains('Account Review'));
      expect(labels, contains('Bulk Onboarding'));
    });

    testWidgets('shows where you are', (tester) async {
      await pumpManaScreen(
        tester,
        const ManaWebShell(location: '/ow-013', child: SizedBox()),
        surfaceSize: const Size(1440, 900),
        location: '/ow-013',
      );
      await tester.pump();
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      // Home leads, so Account Review — first in the Owner list — is 1.
      expect(rail.selectedIndex, 1);
    });

    testWidgets('admits when it cannot name the page', (tester) async {
      // The bulk onboarding WIZARD is reached from the menu and is not itself
      // a destination. Highlighting the nearest thing would say "you are on
      // Bulk Onboarding" while looking at a screen it merely led to.
      const items = <ManaWebDestination>[
        ManaWebDestination(icon: Icons.home, title: 'A', route: '/a'),
      ];
      expect(manaWebSelectedIndex(items, '/somewhere-else'), -1);
      expect(manaWebSelectedIndex(items, '/a'), 0);
    });

    testWidgets('is absent on a phone-width browser', (tester) async {
      // Below the web treatment's threshold the page is already the width it
      // was drawn for, and there is nothing beside it to put a rail in.
      await pumpManaScreen(
        tester,
        const ManaWebShell(location: '/ow-013', child: SizedBox()),
        surfaceSize: const Size(390, 800),
        location: '/ow-013',
      );
      await tester.pump();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(ManaBottomNav), findsNothing,
          reason: 'most of these screens carry their own bottom bar on the '
              'handset; a second one stacked under it is worse than none');
    });

    testWidgets('lays out at four text scales in two languages',
        (tester) async {
      for (final scale in kManaTextScales) {
        await pumpManaScreen(
          tester,
          const ManaWebShell(location: '/ow-013', child: SizedBox()),
          surfaceSize: const Size(1440, 900),
          location: '/ow-013',
          textScale: scale,
        );
        await tester.pump();
        expectNoLayoutFault(tester, 'web rail at ${scale}x');
      }
    });
  });

  group('one list, two renderings', () {
    test('the cards and the rail read the same source', () {
      // ManaAdaptiveShell's own doc says a second, separately maintained nav
      // list is the shape this project's worst regressions have taken. The
      // home page's cards and the rail are two renderings of one list, and
      // neither builds its own.
      // COMMENTS STRIPPED. web_home_screen's own comment explains that it no
      // longer builds a ManaAdaptiveShell — and names the class while doing
      // it, so a naive search finds the thing in the very sentence saying it
      // is gone. This codebase has made that exact mistake seven times now;
      // stripping is cheaper than remembering.
      final home = _code('lib/features/web/screens/web_home_screen.dart');
      final shell = _code('lib/features/web/widgets/mana_web_shell.dart');
      for (final src in [home, shell]) {
        expect(src, contains('manaWebDestinations('));
      }
      expect(home, isNot(contains('ManaAdaptiveShell')),
          reason: 'the router wraps this screen in the shell now — doing it '
              'here as well would draw two rails');
    });
  });
}

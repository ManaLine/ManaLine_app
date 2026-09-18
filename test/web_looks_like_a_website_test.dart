import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_form_grid.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';
import 'package:mana_line/features/web/screens/web_home_screen.dart';
import 'package:mana_line/features/web/widgets/mana_web_shell.dart';

import 'support/mana_harness.dart';

/// The web build is a website, not a phone screen stretched.
///
/// The Owner, on seeing the first live deploy: "i want it to look like a real
/// website not mobile device screen". What they were looking at was
/// [ManaWebFrame] doing exactly what it was built to do — clamping every web
/// route to a 480px centred column, because 85 screens were drawn for 360dp
/// and laying them all out again would re-open the overflow bug class.
///
/// The clamp stays. These are the screens that are OUT of it, and this file
/// is the price of being out: a route in [kManaWideRoutes] has to prove it
/// has a desk layout, or the list becomes a way of skipping the work.
void main() {
  group('the desk-drawn routes are out of the phone column', () {
    test('and only the ones with a layout for it', () {
      expect(kManaWideRoutes, containsAll(<String>{
        '/ow-013',
        '/web-home',
        '/ow-bulk-onboarding-menu',
      }));
      // A guard against the list becoming a dumping ground. Every entry above
      // has a desk-width test; adding a fourth means adding one.
      expect(kManaWideRoutes, hasLength(3),
          reason: 'a route joins kManaWideRoutes once its screen has a '
              'layout for the width AND a test at that width — if you are '
              'adding one, add both and update this count deliberately');
    });
  });

  group('the web home at a desk', () {
    testWidgets('puts the rail against the edge and the cards in columns',
        (tester) async {
      await pumpManaScreen(
        tester,
        const ManaWebShell(
          location: '/web-home',
          child: ManaWebHomeScreen(),
        ),
        surfaceSize: const Size(1440, 900),
        location: '/web-home',
      );
      await tester.pump();

      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0,
          reason: 'a rail floating in the middle of the window, with empty '
              'space to its left, is the thing that read as an app window '
              'rather than a page');

      // THE CAP THAT MATTERS. NavigationRail has a minWidth and no maximum,
      // so with labelType.all it grows to fit its widest label — "Also
      // Available On Mobile" took it to 408px at this width, a quarter of the
      // window, and squeezed the card grid from three columns to two.
      expect(rail.width, lessThanOrEqualTo(200),
          reason: 'the rail is a strip, not a sidebar');
    });

    testWidgets('does not stretch its content across the whole window',
        (tester) async {
      await pumpManaScreen(
        tester,
        const ManaWebShell(
          location: '/web-home',
          child: ManaWebHomeScreen(),
        ),
        surfaceSize: const Size(2560, 1440),
        location: '/web-home',
      );
      await tester.pump();

      // Letting go of the 480px column is not the same as having no measure.
      final cards = tester.getRect(find.byType(ManaFormGrid).first);
      expect(cards.width, lessThanOrEqualTo(kManaDeskContentMax),
          reason: 'a card grid run edge to edge across a 2560px monitor '
              'loses the eye between rows');
    });

    testWidgets('survives a phone, which is still a browser', (tester) async {
      // Out of the clamp does not mean desk-only. Somebody will open the
      // website on the handset in their hand.
      for (final scale in kManaTextScales) {
        await pumpManaScreen(
          tester,
          const ManaWebShell(
          location: '/web-home',
          child: ManaWebHomeScreen(),
        ),
          textScale: scale,
          location: '/web-home',
        );
        await tester.pump();
        expectNoLayoutFault(tester, 'web home at ${scale}x on a phone');
      }
    });
  });

  group('the browser tab carries the product, not the toolkit', () {
    test('every icon is the MANA LINE mark, not the Flutter logo', () {
      // web/icons/* shipped as `flutter create` left them: the stock Flutter
      // logo, live on manaline.pages.dev in the tab and in the install
      // prompt. Nobody had looked at those files since the project was
      // scaffolded.
      //
      // Checked by SIZE rather than by pixels, because the stock icons are
      // small flat-colour PNGs and the mark is a photograph-dense gradient
      // circle — Icon-192 went from 5,292 bytes to an order of magnitude
      // more. A byte-exact golden would fail on any future re-export of the
      // same artwork, which is not the thing worth catching.
      const stockFlutterIcon192Bytes = 5292;
      for (final path in const [
        'web/icons/Icon-192.png',
        'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
      ]) {
        final bytes = File(path).lengthSync();
        expect(bytes, greaterThan(stockFlutterIcon192Bytes * 2),
            reason: '$path looks like it is still the stock Flutter logo');
      }
      expect(File('web/favicon.png').existsSync(), isTrue);
    });

    test('the static site has a real icon, not an HTML page', () {
      // /favicon.ico IS REQUESTED WHETHER OR NOT ANYTHING LINKS IT, and site/
      // had no icon at all -- so Cloudflare answered that request with 200 and
      // 8,813 bytes of index.html. A browser cannot read an icon out of that,
      // and a 200 is worse than a 404 because nothing downstream can tell the
      // difference between "missing" and "here it is".
      expect(File('site/favicon.ico').existsSync(), isTrue,
          reason: 'the implicit /favicon.ico request needs a real answer');
      expect(File('site/favicon.png').existsSync(), isTrue);
      for (final page in Directory('site')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'))) {
        expect(page.readAsStringSync(), contains('rel="icon"'),
            reason: '${page.uri.pathSegments.last} has no icon link');
      }
    });

    test('and the icon URLs carry a version, so a change actually arrives', () {
      // THE HALF THAT WAS ACTUALLY BROKEN. The new mark had been live for
      // hours and the Owner's tab still showed the old one: Chrome caches a
      // favicon hard, and by URL. Replacing the bytes at the same address
      // changes nothing for anybody who has already been to the site.
      final html = File('web/index.html').readAsStringSync();
      final manifest = File('web/manifest.json').readAsStringSync();
      expect(html, contains('favicon.png?v='));
      expect(html, contains('manifest.json?v='));
      expect(manifest, contains('Icon-192.png?v='),
          reason: 'the install prompt caches its icon the same way');
    });

    test('the source artwork it is generated from is still there', () {
      // The icons are derived, and the derivation is recorded in the commit
      // rather than in a script. If this file moves, regenerating them means
      // finding it first.
      expect(File('assets/images/logo.png').existsSync(), isTrue,
          reason: 'web/icons/* are resized from this');
    });
  });
}

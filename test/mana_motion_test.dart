import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_motion.dart';

/// Animation must never be the reason something cannot be read.
///
/// [ManaEntrance] works by starting at opacity 0, which makes it exactly the
/// kind of decoration that can hide content: if the animation does not run —
/// because somebody turned animations off, or because a delayed callback
/// never fired — the page is blank and nothing reports an error. That is a
/// worse outcome than having no animation at all, so it is what these test.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  ));
}

/// SCOPED TO ManaEntrance ON PURPOSE. MaterialApp wraps its route in a
/// FadeTransition of its own and Scaffold adds MouseRegions, so an unscoped
/// `find.byType` here answers a question about Flutter rather than about this
/// widget — and passes or fails for reasons that have nothing to do with it.
Finder _fadeInside(Type owner) => find.descendant(
      of: find.byType(owner),
      matching: find.byType(FadeTransition),
    );

double _opacityOf(WidgetTester tester) {
  final fades = tester.widgetList<FadeTransition>(_fadeInside(ManaEntrance));
  if (fades.isEmpty) return 1; // no animator of ours in the tree at all
  return fades.first.opacity.value;
}

void main() {
  group('ManaEntrance', () {
    testWidgets('ends fully visible', (tester) async {
      await _pump(tester, const ManaEntrance(child: Text('hello')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('hello'), findsOneWidget);
      expect(_opacityOf(tester), 1.0);
    });

    testWidgets('is visible IMMEDIATELY when animations are off',
        (tester) async {
      // Not "does not animate" — VISIBLE. Somebody who turned animations off
      // at the OS level must not be handed a blank page, and an opacity-based
      // entrance that only checks "should I animate" leaves them with one.
      await _pump(
        tester,
        const ManaEntrance(child: Text('hello')),
        disableAnimations: true,
      );
      await tester.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(_fadeInside(ManaEntrance), findsNothing,
          reason: 'with animations off the child should be returned '
              'untouched, not wrapped in a stopped animator');
    });

    testWidgets('a late index still arrives', (tester) async {
      // The stagger is capped at six so a long grid does not leave its last
      // cards apparently missing. A card at index 20 must not wait 20 steps.
      await _pump(tester, const ManaEntrance(index: 20, child: Text('last')));
      await tester.pump(const Duration(milliseconds: 55 * 6));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(_opacityOf(tester), 1.0);
    });

    testWidgets('survives being disposed mid-delay', (tester) async {
      // The delay is a Future, so the controller can outlive the widget if
      // somebody navigates away during the stagger. Without the mounted
      // check that is an exception on a dead State.
      await _pump(tester, const ManaEntrance(index: 6, child: Text('gone')));
      await tester.pump(const Duration(milliseconds: 20));
      await _pump(tester, const SizedBox());
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('ManaHoverLift', () {
    testWidgets('renders its child untouched when animations are off',
        (tester) async {
      await _pump(
        tester,
        const ManaHoverLift(child: Text('card')),
        disableAnimations: true,
      );
      expect(find.text('card'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ManaHoverLift),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
      );
    });

    testWidgets('shows a click cursor when it is live', (tester) async {
      await _pump(tester, const ManaHoverLift(child: Text('card')));
      final regions = tester.widgetList<MouseRegion>(find.descendant(
        of: find.byType(ManaHoverLift),
        matching: find.byType(MouseRegion),
      ));
      expect(regions.any((r) => r.cursor == SystemMouseCursors.click), isTrue);
    });
  });

  group('the website half honours the same rule', () {
    test('reduced motion un-hides the reveal rather than freezing it', () {
      // The CSS mirror of the test above. `.reveal` sets opacity: 0, so a
      // reduced-motion block that only kills transition-duration would leave
      // every revealed section permanently invisible.
      final css = File('site/style.css').readAsStringSync();
      final at = css.indexOf('prefers-reduced-motion');
      expect(at, isNonNegative);
      final block = css.substring(at);
      expect(block, contains('.reveal'),
          reason: 'the reduced-motion block must restore .reveal to visible, '
              'not merely stop it animating');
      expect(block, contains('opacity: 1'));
    });

    test('the reveal script is loaded by every page, not just one', () {
      // It was appended to site.js, which only videos.html loaded — so the
      // animation ran on exactly one page and silently did nothing on the
      // other five. Found by measuring the live page, not by reading it.
      for (final page in Directory('site')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'))) {
        expect(page.readAsStringSync(), contains('site.js'),
            reason: '${page.uri.pathSegments.last} does not load site.js');
      }
    });

    test('the reveal fails OPEN if the observer never reports', () {
      // Measured on the deployed site: a fresh IntersectionObserver emitted
      // nothing at all, not even the initial isIntersecting:false record it
      // is specified to, and ten sections sat at opacity 0 on production.
      // A decoration that hides content must not depend on a callback.
      final js = File('site/site.js').readAsStringSync();
      expect(js, contains('failsafe'));
      expect(js, contains('revealAll'),
          reason: 'there must be a path that shows everything without the '
              'observer having said anything');
    });

    test('prose keeps a reading measure even though the page got wider', () {
      // "Use every inch" must not become "set body copy 1,900px wide".
      final css = File('site/style.css').readAsStringSync();
      expect(css, contains('--content-width: 40rem'));
      expect(css, contains('--wide: 72rem'));
    });
  });
}

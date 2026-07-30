import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/motion.dart';

/// Guards the motion layer's two promises: that it feels immediate, and that it
/// does not drain battery.
///
/// The battery one is the easy promise to break silently — an animation that
/// never settles, or a controller left repeating, costs a frame every vsync
/// forever and shows up as "the app eats my battery" long after anyone
/// remembers adding it. `transientCallbackCount` is the direct measurement:
/// it's the number of callbacks Flutter will run on the next frame, so zero
/// means the framework has nothing scheduled and the screen is genuinely idle.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
  }) =>
      tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );

  group('duration budget', () {
    test('nothing exceeds 260ms', () {
      // Past roughly 300ms a transition stops reading as responsive and starts
      // reading as lag. Fewer frames is also less work.
      for (final d in [ManaMotion.fast, ManaMotion.normal, ManaMotion.page]) {
        expect(d.inMilliseconds, lessThanOrEqualTo(260), reason: '$d is too slow');
      }
    });

    test('tap feedback is near-instant', () {
      expect(ManaMotion.fast.inMilliseconds, lessThanOrEqualTo(120));
    });

    test('a full stagger run stays under a quarter second', () {
      final worst = ManaMotion.stagger * ManaMotion.maxStaggerItems;
      expect(worst.inMilliseconds, lessThanOrEqualTo(250),
          reason: 'a staggered list must not make a fast fetch feel slow');
    });
  });

  group('reduce motion removes the animation, not just its duration', () {
    testWidgets('ManaMotion.duration collapses to zero', (tester) async {
      late Duration reduced;
      late Duration normal;

      await pump(tester, Builder(builder: (c) {
        reduced = ManaMotion.duration(c, ManaMotion.page);
        return const SizedBox();
      }), reduceMotion: true);

      await pump(tester, Builder(builder: (c) {
        normal = ManaMotion.duration(c, ManaMotion.page);
        return const SizedBox();
      }));

      expect(reduced, Duration.zero);
      expect(normal, ManaMotion.page);
    });

    testWidgets('ManaPressable builds no animated wrapper', (tester) async {
      await pump(tester, ManaPressable(onTap: () {}, child: const Text('x')),
          reduceMotion: true);
      // Not merely a zero-duration scale — no AnimatedScale to composite at all.
      expect(find.byType(AnimatedScale), findsNothing);
    });

    testWidgets('ManaAppear renders its child directly', (tester) async {
      await pump(tester, const ManaAppear(child: Text('x')), reduceMotion: true);

      expect(find.text('x'), findsOneWidget);
      // Scoped to this widget's own subtree: MaterialApp builds its own
      // AnimatedBuilder internally, so an unscoped finder matches the framework
      // rather than the thing under test.
      expect(
        find.descendant(of: find.byType(ManaAppear), matching: find.byType(Opacity)),
        findsNothing,
        reason: 'reduce-motion must return the child, not a zero-value fade',
      );
      // And nothing is queued for a future frame.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('page transition returns the child untouched', (tester) async {
      // Under reduce-motion the builder must short-circuit, so there is no
      // Slide/Fade wrapper left composing every frame of a navigation.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: ThemeData(
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {TargetPlatform.android: ManaPageTransitions()},
              ),
            ),
            home: const Scaffold(body: Text('first')),
          ),
        ),
      );
      expect(find.text('first'), findsOneWidget);
      expect(find.byType(SlideTransition), findsNothing);
    });
  });

  group('battery: nothing keeps ticking once settled', () {
    testWidgets('ManaAppear stops scheduling frames after it finishes', (tester) async {
      await pump(tester, const ManaAppear(child: Text('x')));

      // Mid-flight there SHOULD be work scheduled.
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'the entrance should actually animate when motion is allowed');

      // Well past the end.
      await tester.pump(ManaMotion.normal * 3);
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'a settled entrance must not hold a frame callback open');
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('ManaPressable is idle until touched', (tester) async {
      await pump(tester, ManaPressable(onTap: () {}, child: const Text('x')));
      await tester.pump(const Duration(milliseconds: 300));

      // An untouched button must cost nothing.
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('ManaPressable settles again after a press', (tester) async {
      await pump(tester, ManaPressable(onTap: () {}, child: const Text('x')));

      await tester.tap(find.text('x'));
      await tester.pump(ManaMotion.fast * 3);

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a long staggered list does not animate rows nobody sees', (tester) async {
      // Index far beyond the cap must not wait index * stagger to appear —
      // otherwise item 60 arrives 1.8 seconds late, animating content the user
      // has already scrolled past.
      await pump(tester, const ManaAppear(index: 60, child: Text('x')));

      final capped = ManaMotion.stagger * ManaMotion.maxStaggerItems;
      await tester.pump(capped + ManaMotion.normal);
      // pumpAndSettle rather than a single long pump: one pump advances the
      // clock in a single frame, which leaves the ticker registered for one
      // more frame even though the tween is complete.
      await tester.pumpAndSettle();

      expect(tester.binding.transientCallbackCount, 0,
          reason: 'stagger delay must be capped, not proportional to index');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('press feedback', () {
    testWidgets('shrinks on touch down and returns on release', (tester) async {
      await pump(tester, ManaPressable(onTap: () {}, child: const Text('x')));

      double scaleNow() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      expect(scaleNow(), 1.0);

      final gesture = await tester.startGesture(tester.getCenter(find.text('x')));
      await tester.pump();
      expect(scaleNow(), lessThan(1.0), reason: 'no visible confirmation of the touch');

      await gesture.up();
      await tester.pump();
      expect(scaleNow(), 1.0);

      await tester.pump(ManaMotion.fast * 2);
    });

    testWidgets('a disabled surface gives no press feedback', (tester) async {
      await pump(tester, const ManaPressable(onTap: null, child: Text('x')));
      // Animating a press on something that does nothing is a lie about
      // affordance.
      expect(find.byType(AnimatedScale), findsNothing);
    });
  });
}

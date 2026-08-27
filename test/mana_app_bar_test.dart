import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/design/components/mana_app_bar.dart';

/// What this pins: 30 screens carried their own
/// `BackButton(onPressed: () => context.go('/ow-001'))`. Each named its own way
/// home because `go()` replaces the stack and there was often nothing to pop.
/// One of them naming the wrong home, or forgetting, was invisible until
/// somebody landed on another role's dashboard.
///
/// The rule is now in one place: pop what is there, fall back only when there
/// is nothing.
void main() {
  Widget app(GoRouter router) => MaterialApp.router(routerConfig: router);

  testWidgets('back pops when there is something to pop', (tester) async {
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        GoRoute(
          path: '/first',
          builder: (c, s) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => c.push('/second'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/second',
          builder: (c, s) => const Scaffold(
            appBar: ManaAppBar(title: 'Second', homeRoute: '/first'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Popped back to the pushing screen, NOT re-routed home.
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('back falls home when the stack is empty', (tester) async {
    // A deep link, a refresh, or a go() that replaced everything.
    final router = GoRouter(
      initialLocation: '/second',
      routes: [
        GoRoute(
          path: '/first',
          builder: (c, s) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/second',
          builder: (c, s) => const Scaffold(
            appBar: ManaAppBar(title: 'Second', homeRoute: '/first'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a root screen draws no back arrow at all', (tester) async {
    // homeRoute null means "there is nowhere behind this". Drawing an arrow
    // that does nothing is how a dead control gets shipped.
    final router = GoRouter(
      initialLocation: '/only',
      routes: [
        GoRoute(
          path: '/only',
          builder: (c, s) => const Scaffold(
            appBar: ManaAppBar(title: 'Only'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Only'), findsOneWidget);
  });
  testWidgets('onBack takes precedence over homeRoute', (tester) async {
    // A screen whose back means something other than "leave" -- unwinding a
    // wizard step, or a host that owns the stack. Before this existed, three
    // screens kept their own AppBar solely to say this.
    var called = 0;
    final router = GoRouter(
      initialLocation: '/only',
      routes: [
        GoRoute(path: '/home', builder: (c, s) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/only',
          builder: (c, s) => Scaffold(
            appBar: ManaAppBar(
              title: 'Only',
              homeRoute: '/home',
              onBack: () => called++,
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(called, 1);
    expect(find.text('home'), findsNothing,
        reason: 'onBack must win -- routing home behind its back is what the '
            'callback exists to prevent');
  });

  testWidgets('implyLeading false suppresses the arrow even when poppable',
      (tester) async {
    // LR-008 creates a PIN and has no back BY SPEC: backing out leaves an
    // account without one. A pushed route can pop, so AppBar would draw an
    // arrow unless told not to.
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        GoRoute(
          path: '/first',
          builder: (c, s) => Scaffold(
            body: Center(
              child: ElevatedButton(
                  onPressed: () => c.push('/second'), child: const Text('go')),
            ),
          ),
        ),
        GoRoute(
          path: '/second',
          builder: (c, s) => const Scaffold(
            appBar: ManaAppBar(title: 'Second', implyLeading: false),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing,
        reason: 'the route can pop, and the arrow must still not be there');
  });

  testWidgets('a null homeRoute still allows the implicit arrow', (tester) async {
    // The counterpart. A null homeRoute names no destination; it does not
    // suppress AppBar's own arrow. Every screen converted with no leading
    // relies on this, and an earlier doc comment here said the opposite.
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        GoRoute(
          path: '/first',
          builder: (c, s) => Scaffold(
            body: Center(
              child: ElevatedButton(
                  onPressed: () => c.push('/second'), child: const Text('go')),
            ),
          ),
        ),
        GoRoute(
          path: '/second',
          builder: (c, s) => const Scaffold(
            appBar: ManaAppBar(title: 'Second'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
  });
}

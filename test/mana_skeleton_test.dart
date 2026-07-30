import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_skeleton.dart';

/// These cover the failure modes that `flutter analyze` cannot see: the
/// skeleton uses a ShaderMask driven by a repeating AnimationController, and
/// both the shader and the animation are runtime concerns. A zero-size bound,
/// a disposed controller still being pumped, or a missing ancestor would all
/// analyze cleanly and then throw on screen.
void main() {
  Future<void> pumpIn(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('renders inside a group and survives animation frames', (tester) async {
    await pumpIn(
      tester,
      const ManaSkeletonGroup(
        child: Column(
          children: [
            ManaSkeleton(width: 100),
            ManaSkeleton.circle(size: 40),
            ManaSkeleton.text(width: 80),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // Advance through the sweep, including past one full cycle, so a bad
    // gradient stop or Alignment value surfaces rather than only being
    // correct at t=0.
    for (final ms in [100, 400, 700, 1400, 2100]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(tester.takeException(), isNull, reason: 'threw after ${ms}ms');
    }

    expect(find.byType(ManaSkeleton), findsNWidgets(3));
  });

  testWidgets('degrades to a static block with no group ancestor', (tester) async {
    // Documented fallback: a forgotten ManaSkeletonGroup must not throw.
    await pumpIn(tester, const ManaSkeleton(width: 50));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(ManaSkeleton), findsOneWidget);
  });

  testWidgets('ManaSkeletonList renders the requested number of cards', (tester) async {
    await pumpIn(tester, const ManaSkeletonList(itemCount: 4, itemHeight: 60));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(ManaSkeletonCard), findsNWidgets(4));
  });

  testWidgets('disposes its controller without leaving a pending ticker', (tester) async {
    await pumpIn(tester, const ManaSkeletonGroup(child: ManaSkeleton()));
    await tester.pump(const Duration(milliseconds: 200));

    // Replacing the tree tears the group down. A leaked repeating controller
    // fails the test binding's own ticker check at teardown.
    await pumpIn(tester, const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(find.byType(ManaSkeleton), findsNothing);
  });

  testWidgets('renders in a zero-width constraint without a shader error', (tester) async {
    // A ShaderMask over an empty rect is the classic crash here.
    await pumpIn(
      tester,
      const ManaSkeletonGroup(
        child: SizedBox(width: 0, child: ManaSkeleton(height: 10)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}

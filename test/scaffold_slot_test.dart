import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_header.dart';
import 'package:mana_line/design/components/mana_skeleton.dart';

import 'support/mana_harness.dart';

/// Components measured in the Scaffold SLOT they actually occupy.
///
/// WHY THIS IS SEPARATE from components_accessibility_test.dart: those tests
/// pump `ManaBottomNav` as `Scaffold(body: ...)`, where constraints are TIGHT.
/// In production it sits in `bottomNavigationBar`, which Scaffold measures with
/// LOOSE constraints — maxHeight is the whole screen. A `mainAxisSize.max`
/// Column in that slot expands to fill the display, floats its icons in the
/// middle, and leaves the body zero height, so the page renders blank.
///
/// That bug is invisible to every test that pumps the component as a body,
/// because the body slot never offers it the whole screen. The slot is part of
/// the contract, so the test has to use the real one.
void main() {
  Widget navScaffold({int currentIndex = 0}) => Scaffold(
        body: const SizedBox.expand(key: Key('body')),
        bottomNavigationBar: ManaBottomNav(
          currentIndex: currentIndex,
          items: [
            ManaNavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Home',
              onTap: () {},
            ),
            ManaNavItem(
              icon: Icons.groups_outlined,
              selectedIcon: Icons.groups,
              label: 'Customers',
              onTap: () {},
            ),
            ManaNavItem(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.bar_chart,
              label: 'Reports',
              onTap: () {},
            ),
            ManaNavItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'Profile',
              onTap: () {},
            ),
          ],
        ),
      );

  group('ManaBottomNav in the bottomNavigationBar slot', () {
    testWidgets('stays the height of a bar under loose constraints',
        (tester) async {
      await pumpManaScreen(tester, navScaffold());

      final navHeight = tester.getSize(find.byType(ManaBottomNav)).height;

      expect(navHeight, lessThan(120),
          reason: 'the nav expanded into the loose constraints Scaffold gives '
              'this slot — the Column inside needs mainAxisSize.min');
      // A floor too: a bar that collapsed to nothing is equally broken, and
      // an upper bound alone would pass for a zero-height nav.
      expect(navHeight, greaterThanOrEqualTo(kManaMinTapTarget));
    });

    testWidgets('leaves the body almost all of the screen', (tester) async {
      await pumpManaScreen(tester, navScaffold());

      final bodyHeight = tester.getSize(find.byKey(const Key('body'))).height;

      // The symptom users actually saw was a blank page, not a tall nav.
      // Asserting on the body is what catches that directly.
      expect(bodyHeight, greaterThan(kManaSmallPhone.height * 0.75),
          reason: 'the body was squeezed — a full-screen nav renders the page '
              'blank');
    });

    testWidgets('still sizes correctly at 2.0x text scale', (tester) async {
      // Bigger labels legitimately make the bar taller; what must not happen
      // is it seizing the whole screen. 120 is generous headroom for two
      // lines of 13sp at 2.0x.
      await pumpManaScreen(tester, navScaffold(), textScale: 2.0);

      expectNoLayoutFault(tester, 'ManaBottomNav at 2.0x');
      final navHeight = tester.getSize(find.byType(ManaBottomNav)).height;
      expect(navHeight, lessThan(120));
      expect(
        tester.getSize(find.byKey(const Key('body'))).height,
        greaterThan(kManaSmallPhone.height * 0.5),
      );
    });

    testWidgets('four items fit across a 360pt phone without overflowing',
        (tester) async {
      await pumpManaScreen(tester, navScaffold());

      expectNoLayoutFault(tester, 'a four-item nav on a 360pt phone');
    });
  });

  group('ManaSkeletonGroup inside a Scaffold', () {
    testWidgets('does not throw on the first frame', (tester) async {
      // The shader is built from the animation value, and the first frame is
      // the one where the controller has not ticked yet.
      await pumpManaScreen(
        tester,
        const Scaffold(
          body: ManaSkeletonGroup(
            child: Column(
              children: [
                ManaSkeleton(width: 120),
                ManaSkeleton.text(width: 200),
                ManaSkeletonCard(height: 80),
              ],
            ),
          ),
        ),
        settleFrames: 0,
      );

      expectNoLayoutFault(tester, 'ManaSkeletonGroup on first frame');
    });

    testWidgets('survives a full shimmer cycle in a Scaffold', (tester) async {
      await pumpManaScreen(
        tester,
        const Scaffold(
          body: ManaSkeletonGroup(child: ManaSkeleton(width: 120)),
        ),
        settleFrames: 0,
      );

      for (final ms in [100, 400, 900, 1600, 2400]) {
        await tester.pump(Duration(milliseconds: ms));
        expectNoLayoutFault(tester, 'ManaSkeletonGroup after ${ms}ms');
      }
    });

    testWidgets('a loading list alongside a bottom nav lays out', (tester) async {
      // The real shape of a workspace opening: skeletons in the body while the
      // nav is already painted.
      await pumpManaScreen(
        tester,
        Scaffold(
          body: const ManaSkeletonList(itemCount: 6, itemHeight: 72),
          bottomNavigationBar: ManaBottomNav(
            currentIndex: 0,
            items: [
              ManaNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
                onTap: () {},
              ),
              ManaNavItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Profile',
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expectNoLayoutFault(tester, 'a loading list above a bottom nav');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_amount.dart';
import 'package:mana_line/design/components/mana_header.dart';
import 'package:mana_line/design/components/mana_skeleton.dart';
import 'package:mana_line/design/motion.dart';

/// Enforces the accessibility properties of the shared components, because
/// "absolute accessibility" is only real if it fails the build when broken.
///
/// These specifically guard the two gaps found in the existing app: 20 of 36
/// IconButtons had no tooltip or semantic label, and tap targets were never
/// checked against the 48dp floor.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool reduceMotion = false,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
  }

  group('ManaAmount', () {
    testWidgets('formats Indian grouping and never wraps', (tester) async {
      await pump(tester, const ManaAmount(123456));

      expect(find.text('₹1,23,456'), findsOneWidget);
      final t = tester.widget<Text>(find.text('₹1,23,456'));
      expect(t.maxLines, 1, reason: 'an amount must never break across lines');
      expect(t.softWrap, isFalse);
    });

    testWidgets('uses tabular figures so columns align', (tester) async {
      // The core reason this component exists — proportional digits make a
      // column of amounts jitter and defeat scanning.
      await pump(tester, const ManaAmount(1111));
      final t = tester.widget<Text>(find.text('₹1,111'));
      expect(t.style?.fontFeatures?.map((f) => f.feature), contains('tnum'));
    });

    testWidgets('never renders money below the 16sp floor', (tester) async {
      for (final size in ManaAmountSize.values) {
        expect(size.fontSize, greaterThanOrEqualTo(16),
            reason: '${size.name} is below the money legibility floor');
      }
    });

    testWidgets('announces a spoken form, not the glyphs', (tester) async {
      await pump(tester, const ManaAmount(4500, semanticLabel: 'Collections'));

      // "Collections, 4,500 rupees" — not "rupee-sign four comma five zero zero".
      expect(
        find.bySemanticsLabel(RegExp(r'Collections, 4,500 rupees')),
        findsOneWidget,
      );
    });

    testWidgets('signed deltas use a real minus and say so aloud', (tester) async {
      await pump(tester, const ManaAmount(-250, showSign: true, semanticLabel: 'Short'));

      // U+2212, not a hyphen — a hyphen is easy to miss on a money figure.
      expect(find.text('−₹250'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Short, minus 250 rupees')), findsOneWidget);
    });

    testWidgets('ManaAmountField keeps its label above the 13sp floor', (tester) async {
      await pump(tester, const ManaAmountField(label: 'Opening', value: 1000));
      final label = tester.widget<Text>(find.text('Opening'));
      expect(label.style?.fontSize, greaterThanOrEqualTo(13));
    });
  });

  group('tap targets meet the 48dp floor', () {
    testWidgets('ManaHeaderAction', (tester) async {
      await pump(
        tester,
        ManaHeaderAction(icon: Icons.search, label: 'Search customers', onPressed: () {}),
      );

      final size = tester.getSize(find.byType(ManaHeaderAction));
      expect(size.width, greaterThanOrEqualTo(kManaMinTapTarget));
      expect(size.height, greaterThanOrEqualTo(kManaMinTapTarget));
    });

    testWidgets('ManaActionGrid tiles', (tester) async {
      await pump(
        tester,
        ManaActionGrid(
          actions: [
            for (var i = 0; i < 4; i++)
              ManaAction(icon: Icons.payments, label: 'Action $i', onTap: () {}),
          ],
        ),
      );

      // The icon puck itself is the floor; the tile is taller still because of
      // the label beneath it. Measured on the whole pressable surface, since
      // the tap target is the tile and not just the icon.
      final tile = tester.getSize(find.byType(ManaPressable).first);
      expect(tile.height, greaterThanOrEqualTo(kManaMinTapTarget));
    });

    testWidgets('ManaBottomNav items', (tester) async {
      await pump(tester, _nav(selected: 0));

      final button = tester.getSize(find.byType(InkWell).first);
      expect(button.height, greaterThanOrEqualTo(kManaMinTapTarget));
    });
  });

  group('every icon-only control carries an accessible name', () {
    testWidgets('ManaHeaderAction labels the action, not the glyph', (tester) async {
      await pump(
        tester,
        ManaHeaderAction(
          icon: Icons.notifications,
          label: 'Notifications',
          onPressed: () {},
          badgeCount: 3,
        ),
      );

      // Badge count must be spoken, or an unread indicator is invisible to a
      // screen reader user.
      expect(find.bySemanticsLabel('Notifications, 3 unread'), findsOneWidget);
      // And discoverable by long-press for sighted users who don't know the glyph.
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('ManaActionGrid tiles announce pending counts', (tester) async {
      await pump(
        tester,
        ManaActionGrid(
          actions: [
            ManaAction(icon: Icons.how_to_reg, label: 'Approvals', onTap: () {}, badgeCount: 7),
          ],
        ),
      );

      expect(find.bySemanticsLabel('Approvals, 7 pending'), findsOneWidget);
    });
  });

  group('ManaBottomNav', () {
    testWidgets('does not re-navigate to the current tab', (tester) async {
      var taps = 0;
      await pump(tester, _nav(selected: 0, onFirstTap: () => taps++));

      await tester.tap(find.text('Home'));
      await tester.pump();

      // Re-navigating to where you already are pushes a duplicate route and
      // silently breaks the Back button.
      expect(taps, 0);
    });

    testWidgets('signals selection without relying on colour alone', (tester) async {
      await pump(tester, _nav(selected: 0));

      final selected = tester.widget<Text>(find.text('Home'));
      final unselected = tester.widget<Text>(find.text('Reports'));

      // Weight differs too, so selection survives colour-vision deficiency
      // and greyscale rendering.
      expect(selected.style?.fontWeight, isNot(unselected.style?.fontWeight));
    });
  });

  group('reduced motion', () {
    testWidgets('skeleton stops shimmering when the OS asks it to', (tester) async {
      await pump(
        tester,
        const ManaSkeletonGroup(child: ManaSkeleton(width: 100)),
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 400));

      // A repeating sweep is exactly the kind of looping animation reduce-motion
      // exists to suppress. Under it there must be no ShaderMask at all.
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and still shimmers when motion is allowed', (tester) async {
      await pump(tester, const ManaSkeletonGroup(child: ManaSkeleton(width: 100)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShaderMask), findsOneWidget);
    });

    testWidgets('skeleton announces itself as loading', (tester) async {
      await pump(tester, const ManaSkeletonGroup(child: ManaSkeleton(width: 100)));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
  });
}

Widget _nav({required int selected, VoidCallback? onFirstTap}) => ManaBottomNav(
      currentIndex: selected,
      items: [
        ManaNavItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
          onTap: onFirstTap ?? () {},
        ),
        ManaNavItem(
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          label: 'Reports',
          onTap: () {},
        ),
      ],
    );

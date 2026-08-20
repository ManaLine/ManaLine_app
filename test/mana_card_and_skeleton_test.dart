import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_card.dart';
import 'package:mana_line/design/components/mana_skeleton.dart';
import 'package:mana_line/design/theme.dart';
import 'package:mana_line/design/tokens/spacing.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: ManaTheme.light(), home: Scaffold(body: child)),
    );

void main() {
  group('ManaCard', () {
    testWidgets('carries the list rhythm and inner padding by default',
        (tester) async {
      await _pump(tester, const ManaCard(child: Text('x')));

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.margin,
          const EdgeInsets.only(bottom: ManaSpacing.sm));

      // NOT `.first`: Card implements its own margin as a Padding, so the
      // first descendant is the margin, not the inner padding. Match the one
      // that actually wraps the content.
      final padding = tester.widget<Padding>(
          find.ancestor(of: find.text('x'), matching: find.byType(Padding)).first);
      expect(padding.padding, const EdgeInsets.all(ManaSpacing.md));
    });

    testWidgets('without onTap there is no ink surface to intercept gestures',
        (tester) async {
      await _pump(tester, const ManaCard(child: Text('x')));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('with onTap the whole card is tappable and the ripple is '
        'clipped to the card shape', (tester) async {
      var taps = 0;
      await _pump(tester, ManaCard(onTap: () => taps++, child: const Text('x')));

      final ink = tester.widget<InkWell>(find.byType(InkWell));
      // A square ripple bleeding past a rounded corner is the detail
      // hand-rolled InkWell-in-Card usually gets wrong.
      expect(ink.customBorder, isNotNull);

      await tester.tap(find.text('x'));
      expect(taps, 1);
    });
  });

  group('ManaSkeletonList', () {
    testWidgets('stands in for a list rather than a spinner on a blank field',
        (tester) async {
      await _pump(tester, const ManaSkeletonList());

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ManaSkeletonCard), findsWidgets);
    });

    testWidgets('placeholders never eat a scroll or pull-to-refresh gesture',
        (tester) async {
      await _pump(tester, const ManaSkeletonList());

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.physics, isA<NeverScrollableScrollPhysics>());
    });
  });
}

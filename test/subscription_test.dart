import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/subscription_screen.dart';
import 'package:mana_line/features/owner_workspace/state/subscription_state.dart';

import 'support/mana_harness.dart';

void main() {
  group('tier selection', () {
    test('an empty business starts on the cheapest plan', () {
      const u = BusinessUsage(agents: 0, customers: 0, investors: 0);
      expect(u.currentTier.name, 'Starter');
    });

    test('sitting exactly on a cap still fits that plan', () {
      // Starter is "up to 4 agents", so 4 must fit. An off-by-one here would
      // tell an Owner to upgrade a plan they are still inside.
      const u = BusinessUsage(agents: 4, customers: 150, investors: 20);
      expect(u.currentTier.name, 'Starter');
    });

    test('one over any cap moves up a plan', () {
      expect(
        const BusinessUsage(agents: 5, customers: 0, investors: 0)
            .currentTier
            .name,
        'Growth',
      );
      expect(
        const BusinessUsage(agents: 0, customers: 151, investors: 0)
            .currentTier
            .name,
        'Growth',
      );
      expect(
        const BusinessUsage(agents: 0, customers: 0, investors: 21)
            .currentTier
            .name,
        'Growth',
      );
    });

    test('any single cap decides the tier, not the average', () {
      // Two agents is Starter-sized, but 900 customers is not. The tier has to
      // be the one that satisfies EVERY cap, or an Owner would be quoted a
      // price for limits they are already past.
      const u = BusinessUsage(agents: 2, customers: 900, investors: 1);
      expect(u.currentTier.name, 'Business');
    });

    test('beyond every stated cap lands on Enterprise', () {
      const u = BusinessUsage(agents: 500, customers: 90000, investors: 900);
      expect(u.currentTier.name, 'Enterprise');
      expect(u.currentTier.isCustom, isTrue);
    });

    test('tiers are ordered cheapest first, and caps only grow', () {
      // currentTier takes the FIRST tier that fits, so an out-of-order table
      // would silently quote the wrong price.
      final numbered = kOwnerTiers.where((t) => !t.isCustom).toList();
      for (var i = 1; i < numbered.length; i++) {
        expect(numbered[i].agents!, greaterThan(numbered[i - 1].agents!));
        expect(numbered[i].customers!, greaterThan(numbered[i - 1].customers!));
        expect(numbered[i].investors!, greaterThan(numbered[i - 1].investors!));
      }
    });

    test('exactly one custom tier exists, and it is last', () {
      expect(kOwnerTiers.where((t) => t.isCustom), hasLength(1));
      expect(kOwnerTiers.last.isCustom, isTrue);
    });
  });

  group('screen', () {
    Override seed(BusinessUsage u) =>
        businessUsageProvider('b1').overrideWith((ref) async => u);

    for (final scale in kManaTextScales) {
      testWidgets('Subscription survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const SubscriptionScreen(businessId: 'b1'),
          textScale: scale,
          surfaceSize: const Size(360, 2000),
          overrides: [
            seed(const BusinessUsage(agents: 3, customers: 90, investors: 4)),
          ],
        );
        expectNoLayoutFault(tester, 'Subscription at ${scale}x');
      });
    }

    testWidgets('usage is shown against the caps of the fitting tier',
        (tester) async {
      await pumpManaScreen(
        tester,
        const SubscriptionScreen(businessId: 'b1'),
        surfaceSize: const Size(360, 2000),
        overrides: [
          seed(const BusinessUsage(agents: 3, customers: 90, investors: 4)),
        ],
      );
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('90 of 150'), findsOneWidget);
      expect(find.textContaining('Starter'), findsWidgets);
    });

    testWidgets('no purchase control is offered', (tester) async {
      await pumpManaScreen(
        tester,
        const SubscriptionScreen(businessId: 'b1'),
        surfaceSize: const Size(360, 2000),
        overrides: [
          seed(const BusinessUsage(agents: 1, customers: 1, investors: 1)),
        ],
      );
      // Billing is not built. A button that takes a payment nowhere is worse
      // than no button, so its absence is asserted rather than assumed.
      expect(find.text('Subscribe'), findsNothing);
      expect(find.text('Upgrade'), findsNothing);
      expect(find.text('Buy'), findsNothing);
      expect(find.textContaining('Nothing is being charged'), findsOneWidget);
    });
  });
}

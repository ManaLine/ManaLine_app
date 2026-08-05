import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/settings_screen.dart';

import 'support/mana_harness.dart';

/// The Settings ORDER is the P1 deliverable, not just its contents. Six of the
/// eleven rows are placeholders for P2/P3/P4 features, and the whole point of
/// shipping them now is that later phases fill a row rather than reshuffling a
/// screen people have already learned — so the order needs a test that fails
/// when it drifts.
void main() {
  /// Locked order. Profile is conditional on the workspace having a profile
  /// route, so it is asserted separately.
  const lockedOrder = [
    'Permissions',
    'Subscription',
    'Backup',
    'Forgot / Reset Password',
    'Business Transfer',
    'Share App',
    'Appearance',
    'App Version',
    'Logout',
  ];

  /// Tall enough that the whole list is laid out at once.
  ///
  /// On a 360x640 surface the ListView builds lazily and the finders below see
  /// only the top three rows — the order test would then pass while proving
  /// nothing about the seven it never rendered. The text-scale tests further
  /// down deliberately stay on the real phone size, since that is where
  /// overflow actually happens.
  const tallSurface = Size(360, 2400);

  testWidgets('rows appear in the locked order', (tester) async {
    await pumpManaScreen(
      tester,
      const SettingsScreen(homeRoute: '/ow-001'),
      surfaceSize: tallSurface,
      storage: rememberedDeviceStorage(),
    );
    expectNoLayoutFault(tester, 'Settings screen');

    // Compare by vertical position rather than by index in the widget tree:
    // the tree order is an implementation detail, where the y-order is what
    // the user actually reads.
    double yOf(String label) =>
        tester.getTopLeft(find.text(label).first).dy;

    var previous = double.negativeInfinity;
    for (final label in lockedOrder) {
      expect(find.text(label), findsWidgets, reason: '$label is missing');
      final y = yOf(label);
      expect(y, greaterThan(previous),
          reason: '$label is out of order — the locked order is $lockedOrder');
      previous = y;
    }
  });

  testWidgets('Profile leads, and the Account section is gone', (tester) async {
    await pumpManaScreen(
      tester,
      const SettingsScreen(homeRoute: '/ow-001'),
      surfaceSize: tallSurface,
      storage: rememberedDeviceStorage(),
    );

    expect(tester.getTopLeft(find.text('Profile').first).dy,
        lessThan(tester.getTopLeft(find.text('Permissions').first).dy));

    // Account held exactly one item, Logout, which now stands on its own.
    expect(find.text('Account'), findsNothing);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('unbuilt features read as Coming Soon, not as working rows',
      (tester) async {
    await pumpManaScreen(
      tester,
      const SettingsScreen(homeRoute: '/ow-001'),
      surfaceSize: tallSurface,
      storage: rememberedDeviceStorage(),
    );

    // Five placeholders. Was six until Backup shipped — the count is asserted
    // so that building a feature, or adding a new placeholder, has to be a
    // deliberate edit here rather than passing unnoticed.
    expect(find.text('Coming Soon'), findsNWidgets(5));

    // The rows must be genuinely inert. A placeholder that still accepts taps
    // would navigate nowhere and read as a broken app.
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Subscription'), matching: find.byType(ListTile)).first,
    );
    expect(tile.onTap, isNull);
    expect(tile.enabled, isFalse);
  });

  testWidgets('Backup is live for an Owner and inert for a Customer',
      (tester) async {
    await pumpManaScreen(
      tester,
      const SettingsScreen(homeRoute: '/ow-001'),
      surfaceSize: tallSurface,
      storage: rememberedDeviceStorage(),
    );
    final ownerTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Backup'), matching: find.byType(ListTile)).first,
    );
    expect(ownerTile.onTap, isNotNull, reason: 'an Owner has records to export');

    // A Customer holds no business records, so the row must stay a placeholder
    // rather than produce six empty sheets — which would read as a broken
    // export, not an empty one.
    await pumpManaScreen(
      tester,
      const SettingsScreen(homeRoute: '/cw-001'),
      surfaceSize: tallSurface,
      storage: rememberedDeviceStorage(),
    );
    final customerTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Backup'), matching: find.byType(ListTile)).first,
    );
    expect(customerTile.onTap, isNull);
  });

  for (final scale in kManaTextScales) {
    testWidgets('Settings survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const SettingsScreen(homeRoute: '/ow-001'),
        textScale: scale,
        storage: rememberedDeviceStorage(),
      );
      expectNoLayoutFault(tester, 'Settings at ${scale}x');
    });
  }
}

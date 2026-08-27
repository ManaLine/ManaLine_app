import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_identity_header.dart';

import 'support/mana_harness.dart';

/// What this pins: the one role rule that OW-016 and AG-009 used to enforce
/// by being separate files.
///
/// The Owner may change their profile photo. The Agent may not, and AG-009's
/// own note insisted the refusal be total -- "no `onEdit` affordance of any
/// kind (not even disabled)", because a greyed-out control still tells
/// somebody the door is there.
///
/// Once both screens render through one widget, that rule survives only as a
/// null check inside it. This is the test that says so. Without it, a
/// careless default on onChangePhoto hands an Agent an edit affordance the
/// role is not allowed to have, and nothing else in the suite would notice.
void main() {
  /// Both real screens put this in a ListView, so the test does too. A bare
  /// Scaffold body gives the card unbounded height and measures a layout that
  /// does not ship.
  Widget host(Widget child) => Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      );

  testWidgets('a view-only header draws no photo control at all', (tester) async {
    await pumpManaScreen(
      tester,
      host(const ManaIdentityHeader(
        fullName: 'Kandukuri Siva Rama Krishna',
        mlid: 'MLAG0000012345',
        statusLabel: 'Active',
        fields: [
          ManaIdentityField(label: 'Phone', value: '9493509919', locked: true),
        ],
      )),
    );

    expect(find.byType(InkWell), findsNothing,
        reason: 'no tappable photo when onChangePhoto is null');
    expect(find.byIcon(Icons.photo_camera), findsNothing,
        reason: 'no camera badge either -- the refusal is total, not disabled');
    // The padlock is the honest signal: this cannot be changed from here.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('an editable header draws the control and names the action',
      (tester) async {
    var tapped = 0;
    await pumpManaScreen(
      tester,
      host(ManaIdentityHeader(
        fullName: 'Karri Siri Manikanta Reddy',
        mlid: 'MLPI0000012345',
        photoActionLabel: 'Change Profile Photo',
        onChangePhoto: () => tapped++,
        fields: const [
          ManaIdentityField(label: 'Mobile Number', value: '9493509919'),
        ],
      )),
    );

    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    await tester.tap(find.byType(InkWell).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, 1, reason: 'the Owner must be able to change their photo');

    // An unlocked field carries no padlock -- the Owner's mobile is editable
    // elsewhere on that screen, so claiming otherwise would be a lie.
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('an upload in flight does not fire a second time', (tester) async {
    var tapped = 0;
    await pumpManaScreen(
      tester,
      host(ManaIdentityHeader(
        fullName: 'Karri Siri Manikanta Reddy',
        mlid: 'MLPI0000012345',
        savingPhoto: true,
        onChangePhoto: () => tapped++,
      )),
    );
    await tester.tap(find.byType(InkWell).first, warnIfMissed: false);
    // pump, not pumpAndSettle: the badge holds a CircularProgressIndicator
    // while an upload is in flight, and that animation never settles.
    await tester.pump();
    expect(tapped, 0, reason: 'tapping mid-upload must not queue another');
  });

  for (final scale in kManaTextScales) {
    testWidgets('identity header survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        host(ManaIdentityHeader(
          fullName: 'Nagabhushanam Venkata Subba Reddy',
          mlid: 'MLAG0000012345',
          statusLabel: 'Temporarily Disabled',
          onChangePhoto: () {},
          fields: const [
            ManaIdentityField(label: 'Phone', value: '9493509919', locked: true),
            ManaIdentityField(
                label: 'Joined Date', value: '12 Jun 2024', locked: true),
          ],
        )),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'identity header at ${scale}x');
    });
  }
}

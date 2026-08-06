import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/widgets/address_check_banner.dart';

import 'support/mana_harness.dart';

/// The banner is the first place the address comparison is actually SEEN, so
/// this is where the "couldn't verify is not a mismatch" rule stops being a
/// unit-test abstraction and starts being something an agent reads while
/// standing in front of a customer.
void main() {
  for (final scale in kManaTextScales) {
    testWidgets('banner is silent until it has an answer, at ${scale}x',
        (tester) async {
      await pumpManaScreen(
        tester,
        const Scaffold(body: AddressCheckBanner(customerId: 'c1')),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'AddressCheckBanner at ${scale}x');

      // No geolocator platform in a test process, so the fix attempt fails and
      // the banner must render nothing rather than an error about geography on
      // top of the collection screen.
      expect(find.byType(Row), findsNothing);
    });
  }

  testWidgets('it never blocks the screen it sits on', (tester) async {
    // The banner is informational. If it ever grew a button or absorbed taps,
    // it would be standing between an agent and a collection.
    await pumpManaScreen(
      tester,
      const Scaffold(body: AddressCheckBanner(customerId: 'c1')),
    );
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}

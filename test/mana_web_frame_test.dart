import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_web_frame.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// The clamp exists so ~85 handset screens are legible in a desktop browser
/// without laying any of them out again. Its most important property is the
/// one asserted first: BELOW the breakpoint it does nothing at all, so the
/// Android build cannot be affected by it.
void main() {
  // `flutter test` runs on the VM, where the real `kIsWeb` is always false —
  // so every test here must inject `isWeb` explicitly rather than rely on
  // the widget's default, the same way `currentLocation` is already
  // injected rather than read from a real router.
  Future<double> widthOfChildAt(
    WidgetTester tester,
    double surface, {
    String location = '/ow-001',
    bool isWeb = true,
  }) async {
    tester.view.physicalSize = Size(surface, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ManaWebFrame(
        currentLocation: () => location,
        isWeb: () => isWeb,
        child: Container(key: const Key('content'), color: Colors.red),
      ),
    ));
    return tester.getSize(find.byKey(const Key('content'))).width;
  }

  testWidgets('a handset width is untouched', (tester) async {
    expect(await widthOfChildAt(tester, 360), 360);
  });

  testWidgets('a desktop width gets the reading measure, not a phone column',
      (tester) async {
    // INVERTED 2026-09-18. This asserted ManaBreakpoints.columnMax -- 480px,
    // a phone column centred in a desk window, which is what the Owner was
    // looking at when they said "it looks like a mobile device screen".
    //
    // Still a measure, though, and that is the half worth keeping: these
    // screens are single columns of full-width rows drawn against 360dp, and
    // handed the whole window their buttons become 1,400px bands.
    expect(await widthOfChildAt(tester, 1440), kManaWebReadingMeasure);
  });

  testWidgets('a route in kManaWideRoutes gets the wider desk measure',
      (tester) async {
    // The list kept its name and changed direction. It used to name the only
    // screens ALLOWED OUT of the phone column; it now names the ones with a
    // bespoke wide layout, which get more room than the default.
    //
    // Neither then nor now does anything get the raw window width. 1440 was
    // what this asserted, and a form field 1,440px wide is not a thing this
    // app should ever draw.
    kManaWideRoutes.add('/test-wide');
    addTearDown(() => kManaWideRoutes.remove('/test-wide'));
    expect(await widthOfChildAt(tester, 1440, location: '/test-wide'),
        kManaDeskContentMax);
  });

  testWidgets('a desktop-width window is untouched off the web — I2', (tester) async {
    // The mechanism this guards: `breakpoints.dart`'s "cannot change the
    // Android build" claim used to rest only on every targeted handset
    // being under 600dp — an assumption about today's fleet, not something
    // width alone enforces. A tablet or unfolded foldable at >=600dp would
    // have been clamped. Gating on `isWeb` too makes the claim true by
    // construction: even a desktop-sized window is left alone off the web.
    expect(await widthOfChildAt(tester, 1440, isWeb: false), 1440);
  });
}

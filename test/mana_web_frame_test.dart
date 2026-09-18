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
    String location = '/lr-009',
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

  testWidgets('a signed-in route is left entirely alone', (tester) async {
    // NARROWED 2026-09-18. web_router wraps all twenty-one signed-in routes
    // in a ShellRoute that puts the navigation against the window's edge and
    // measures the content beside it. Measuring again here would measure the
    // RAIL too, and the whole assembly would float in the middle of a wide
    // monitor -- the exact complaint that started this work.
    expect(await widthOfChildAt(tester, 1440, location: '/ow-013'), 1440);
    expect(await widthOfChildAt(tester, 1440, location: '/web-home'), 1440);
  });

  testWidgets('a signed-out page keeps the reading measure whatever list it '
      'is on', (tester) async {
    // The measure is the point, and it does not get spent. A login form
    // 1,440px wide is not a thing this app should ever draw.
    //
    // NOTE it must be an /lr- path: this widget only touches signed-out
    // pages now, so a wide route anywhere else never reaches the branch.
    kManaWideRoutes.add('/lr-test-wide');
    addTearDown(() => kManaWideRoutes.remove('/lr-test-wide'));
    expect(await widthOfChildAt(tester, 1440, location: '/lr-test-wide'),
        kManaWebReadingMeasure);
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

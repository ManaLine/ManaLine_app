import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_web_frame.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// The clamp exists so ~85 handset screens are legible in a desktop browser
/// without laying any of them out again. Its most important property is the
/// one asserted first: BELOW the breakpoint it does nothing at all, so the
/// Android build cannot be affected by it.
void main() {
  Future<double> widthOfChildAt(WidgetTester tester, double surface,
      {String location = '/ow-001'}) async {
    tester.view.physicalSize = Size(surface, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ManaWebFrame(
        currentLocation: () => location,
        child: Container(key: const Key('content'), color: Colors.red),
      ),
    ));
    return tester.getSize(find.byKey(const Key('content'))).width;
  }

  testWidgets('a handset width is untouched', (tester) async {
    expect(await widthOfChildAt(tester, 360), 360);
  });

  testWidgets('a desktop width is clamped and centred', (tester) async {
    expect(await widthOfChildAt(tester, 1440), ManaBreakpoints.columnMax);
  });

  testWidgets('a route in kManaWideRoutes keeps the full width', (tester) async {
    // Plan 2 opts each responsive workflow out by adding its path here. Until
    // a screen has actually been laid out for a wide window, being clamped is
    // the correct outcome, not a limitation.
    kManaWideRoutes.add('/test-wide');
    addTearDown(() => kManaWideRoutes.remove('/test-wide'));
    expect(await widthOfChildAt(tester, 1440, location: '/test-wide'), 1440);
  });
}

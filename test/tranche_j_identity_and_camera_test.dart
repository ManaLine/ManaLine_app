import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_brand_mark.dart';
import 'package:mana_line/design/components/mana_logo_backdrop.dart';
import 'package:mana_line/features/login_registration/screens/lr_002_workspace_choice.dart';

import 'support/mana_harness.dart';

/// Three findings: where the logo belongs, where the wordmark sits, and a
/// camera that forgot which way it was pointing on every single capture.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  group('items 2 and 3 - the logo goes behind the screen', () {
    test('neither pre-login screen puts a logo beside the wordmark', () {
      for (final f in const [
        'features/login_registration/screens/lr_002_workspace_choice.dart',
        'features/login_registration/screens/lr_009_daily_login.dart',
      ]) {
        final src = lib(f);
        expect(src, contains('ManaLogoBackdrop'), reason: '$f has no backdrop');
        expect(src, contains('logoSize: 0'),
            reason: '$f still draws the 44dp mark beside the wordmark, which '
                'at that size on a 360dp bar is a smudge competing with the '
                'one word it is meant to support');
      }
    });

    test('the wordmark centres itself once the logo is gone', () {
      // Item 3, and it falls out of the component rather than needing a
      // change: the horizontal layout balances the logo with an equal spacer
      // on the other side, and BOTH are behind `if (logoSize > 0)`. With no
      // logo the words are Expanded across the full width and centred in it.
      final mark = lib('design/components/mana_brand_mark.dart');
      expect(mark, contains('if (logoSize > 0) ...['));
      expect(mark, contains('if (logoSize > 0) SizedBox(width: logoSize'));
      expect(mark, contains('Expanded(child: _words(centred: true))'));
    });

    test('the backdrop cannot swallow a tap', () {
      // The Stack's first child covers the screen. Without IgnorePointer it
      // would eat gestures over most of it -- including, on the chooser, the
      // two cards that are the only controls there.
      expect(lib('design/components/mana_logo_backdrop.dart'),
          contains('IgnorePointer'));
    });

    test('it sizes to the SHORTER edge', () {
      // On a landscape handset the height runs out first, and sizing to width
      // there would push the mark off both ends.
      expect(lib('design/components/mana_logo_backdrop.dart'),
          contains('size.width < size.height ? size.width : size.height'));
    });

    test('the opacity is named, not inlined', () {
      // It is exactly the sort of number somebody raises while looking at a
      // bright desk monitor, and these screens are read in a field.
      expect(kManaBackdropOpacity, lessThan(0.15),
          reason: 'a backdrop that competes with the text over it turns '
              'legible text into grey on grey in daylight');
      expect(kManaBackdropOpacity, greaterThan(0.0),
          reason: 'and "visible opacity" was the instruction');
    });

    testWidgets('the chooser still works with the backdrop behind it',
        (tester) async {
      await pumpManaScreen(tester, const WorkspaceChoiceScreen());
      expectNoLayoutFault(tester, 'the chooser with a backdrop');
      expect(find.byType(ManaLogoBackdrop), findsOneWidget);
      expect(find.byType(ManaBrandMark), findsOneWidget);
      // The two product cards are still the two controls, still reachable.
      expect(find.byType(Card), findsNWidgets(2));
      final bottom = tester.getBottomLeft(find.byType(Card).last).dy;
      expect(bottom, lessThanOrEqualTo(kManaSmallPhone.height),
          reason: 'the backdrop must not have pushed anything off screen');
    });

    testWidgets('and at 2.0x too', (tester) async {
      await pumpManaScreen(tester, const WorkspaceChoiceScreen(),
          textScale: 2.0);
      expectNoLayoutFault(tester, 'the chooser with a backdrop at 2.0x');
    });
  });

  group('item 8 - the camera remembers which way it was pointing', () {
    final capture = lib('shared/live_face_capture_screen.dart');

    test('it opens on the remembered lens', () {
      expect(capture, contains('final preferred = await _lastLens();'));
      expect(capture, contains('_rememberLens('));
    });

    test('it remembers a DIRECTION, not an index', () {
      // _cameras is whatever the platform enumerates and its order is not
      // promised. Remembering "camera 1" would point at a different lens on a
      // handset that reports them the other way round, or on a phone with
      // three.
      expect(capture, contains('_cameras.indexWhere((c) => c.lensDirection == preferred)'));
      final store = capture.substring(capture.indexOf('Future<void> _rememberLens('));
      expect(store.substring(0, store.indexOf('\n  }')), contains('lens.name'));
    });

    test('it records the lens only after the open succeeds', () {
      // Storing the choice first would make one bad camera permanent.
      final flip = capture.substring(capture.indexOf('Future<void> _flip() async {'));
      final body = flip.substring(0, flip.indexOf('} catch'));
      expect(body.indexOf('_openCamera(_cameras[_cameraIndex])'),
          lessThan(body.indexOf('_rememberLens(')),
          reason: 'a lens that failed to open is not a lens to come back to');
    });

    test('front is still the fallback, twice', () {
      // Once for a first run with nothing stored, and once for a remembered
      // lens this device does not have. Falling back to whatever is first
      // would make the default wrong on a phone that enumerates rear-first.
      final read = capture.substring(capture.indexOf('Future<CameraLensDirection> _lastLens()'));
      expect(read.substring(0, read.indexOf('\n  }')),
          contains('return CameraLensDirection.front;'));
      expect(capture, contains('.indexWhere((c) => c.lensDirection == CameraLensDirection.front)'));
    });

    test('a storage failure costs a tap, never a capture', () {
      // Both calls are wrapped. A preference that could not be saved must not
      // take down the photograph being taken right now.
      final read = capture.substring(capture.indexOf('Future<CameraLensDirection> _lastLens()'));
      expect(read.substring(0, read.indexOf('\n  }')), contains('} catch (_) {'));
      final write = capture.substring(capture.indexOf('Future<void> _rememberLens('));
      expect(write.substring(0, write.indexOf('\n  }')), contains('} catch (_) {'));
    });

    test('it reuses the storage the app already carries', () {
      // appearance_state.dart makes the same call and writes down the reason:
      // adding a package for one enum is not worth another
      // build-compatibility risk on AGP 9.
      expect(capture, contains('FlutterSecureStorage()'));
      expect(File('pubspec.yaml').readAsStringSync().contains('shared_preferences'),
          isFalse,
          reason: 'a new dependency was not added for one preference');
    });
  });
}

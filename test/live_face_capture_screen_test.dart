import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mana_line/shared/live_face_capture_screen.dart';

/// Covers I1: `_pickPhoto`'s two rejection branches (oversized, undecodable)
/// used to write into `_error`, and `build()` checked `_error != null` BEFORE
/// the `kIsWeb` branch — so a rejected web upload replaced the whole picker
/// with a terminal error screen and no way to try another file short of
/// leaving LR-004 and re-entering it.
///
/// `file_selector` (the plugin `_pickPhoto` drives) cannot be faked in a
/// widget test in this project — there is no fake/mock file-picker seam
/// anywhere else in the app either. So the validation `_pickPhoto` performs
/// was pulled out into the pure `webUploadRejectionReason(bytes)`, tested
/// directly here. The "picker stays on screen" half of the fix is a widget
/// rendering change in `build()`/`_buildWebPicker` (moving `_error` display
/// inline, after the `kIsWeb` check rather than before it) that has no
/// meaningful behaviour left to assert without also faking `file_selector` —
/// this test locks the guard logic that feeds that inline error message.
void main() {
  group('webUploadRejectionReason', () {
    test('accepts a normal decodable photo', () {
      final image = img.Image(width: 32, height: 32);
      final bytes = Uint8List.fromList(img.encodePng(image));

      expect(webUploadRejectionReason(bytes), isNull);
    });

    test('rejects a file over the decode-cost bound', () {
      final oversized = Uint8List(24 * 1024 * 1024 + 1);

      final reason = webUploadRejectionReason(oversized);

      expect(reason, isNotNull);
      expect(reason, contains('unusually large'));
    });

    test('rejects bytes that are not a decodable image', () {
      final notAPhoto = Uint8List.fromList('this is a text file, not a jpeg'.codeUnits);

      final reason = webUploadRejectionReason(notAPhoto);

      expect(reason, isNotNull);
      expect(reason, contains('not a readable image'));
    });
  });
}

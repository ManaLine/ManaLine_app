import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_file_share.dart';

/// The helper's contract is thin on purpose: bytes in, a file in front of the
/// user, and a filename that survives. The platform halves are exercised on
/// their platforms — what a unit test can hold honestly is that the API
/// exists and rejects the input that would produce a nameless download.
void main() {
  test('a filename is required and must not be blank', () {
    expect(
      () => manaShareBytes(bytes: Uint8List(0), fileName: ''),
      throwsArgumentError,
    );
  });
}

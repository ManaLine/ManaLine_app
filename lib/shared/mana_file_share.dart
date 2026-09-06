import 'dart:typed_data';

import 'mana_file_share_io.dart'
    if (dart.library.js_interop) 'mana_file_share_web.dart' as impl;

/// Hand [bytes] to the person as a file called [fileName].
///
/// WHY THIS EXISTS: three services — the ledger statement, the backup export
/// and the loan-import template — each carried the same four lines:
/// getTemporaryDirectory, File(...), writeAsBytes, SharePlus. That is
/// triplicated code, and it is the ONLY reason dart:io appeared in any of
/// them. On the web dart:io is a stub that compiles and throws on use, so all
/// three would have failed in a browser at the moment somebody pressed
/// Export — the point at which they had already waited for the file to build.
///
/// A conditional import rather than a `kIsWeb` branch, because the branch
/// would still have to COMPILE `File` on web. This way the web bundle never
/// sees dart:io at all.
Future<void> manaShareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) {
  if (fileName.trim().isEmpty) {
    throw ArgumentError.value(
        fileName, 'fileName', 'A download with no filename is unopenable');
  }
  return impl.shareBytes(bytes: bytes, fileName: fileName, subject: subject);
}

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: a Blob and a click on an invisible anchor — the plain browser
/// download, not the Web Share API.
///
/// Web Share with files is unevenly supported (Firefox does not have it at
/// all), and an export that silently does nothing on one browser is exactly
/// the failure this whole task exists to remove. A download works everywhere.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  anchor.click();
  // Revoked on the next turn of the event loop: revoking synchronously can
  // beat the browser to reading the URL the click just queued.
  Future<void>.delayed(Duration.zero, () => web.URL.revokeObjectURL(url));
}

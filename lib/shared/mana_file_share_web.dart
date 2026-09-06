import 'dart:async';
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
  // No equivalent in a browser download — there is no share sheet to carry
  // a subject line into. Accepted (to match the io half's signature) and
  // intentionally ignored here.
  String? subject,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    // octet-stream forces a save-to-disk everywhere instead of letting some
    // browsers try to open the .xlsx inline; the file extension still tells
    // the OS which app to hand it to.
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  // Must be in the DOM before click(): Chromium will download from a
  // detached anchor, but Firefox has a long history of ignoring click() on
  // one that isn't. Remove it again once the download is queued, even if
  // click() throws — an anchor left behind is a small leak either way.
  web.document.body?.appendChild(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
  }
  // Revoking hands the browser 10 seconds to finish reading the blob before
  // the URL goes away. This helper's callers include the full book backup
  // export, so the cost of guessing too short is a truncated or empty
  // download with no error shown anywhere — worse than holding the object
  // URL a few extra seconds after a click nobody is waiting on.
  unawaited(
    Future<void>.delayed(
      const Duration(seconds: 10),
      () => web.URL.revokeObjectURL(url),
    ),
  );
}

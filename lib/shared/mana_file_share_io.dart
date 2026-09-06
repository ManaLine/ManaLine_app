import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Android/iOS: a real file in the temp directory, handed to the system share
/// sheet. Unchanged from what the three services each did inline.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: fileName)],
      subject: subject,
    ),
  );
}

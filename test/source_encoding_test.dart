import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a failure that is invisible in review and invisible to
/// `flutter analyze`: a source file saved so that its UTF-8 bytes get read as
/// CP1252 and re-encoded, turning ₹ into "â‚¹" and — into "â€”".
///
/// Six screen files had it. On the handset the investor stat cards rendered
/// "â‚¹0" while every other screen showed ₹ correctly, which reads as a font
/// or locale problem and is neither — the bytes in the file were wrong.
void main() {
  test('no Dart source is double-encoded', () {
    // The tell-tales of UTF-8-read-as-CP1252. Any of these in a source file
    // means the file has been through a bad round trip.
    const mojibake = <String, String>{
      'â‚¹': '₹',
      'â€”': '—',
      'â€™': '’',
      'â€œ': '“',
      'â€¢': '•',
      'â†’': '→',
      'â€¦': '…',
      'Â§': '§',
      'Â·': '·',
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);

      for (final entry in mojibake.entries) {
        if (text.contains(entry.key)) {
          offenders.add('${entity.path}: "${entry.key}" should be "${entry.value}"');
        }
      }
      // A BOM is not corruption on its own, but it is how one of these files
      // got there, and Dart does not need one.
      if (text.startsWith('﻿')) {
        offenders.add('${entity.path}: starts with a byte-order mark');
      }
    }

    expect(offenders, isEmpty,
        reason: 'Double-encoded source files:\n${offenders.join("\n")}');
  });
}

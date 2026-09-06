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
///
/// WIDENED BEYOND lib/ ON 2026-09-06, because it missed one. tool/build_apk.ps1
/// edited pubspec.yaml and lib/shared/app_version.dart with PowerShell 5.1's
/// `Get-Content -Raw` / `Set-Content -Encoding utf8` — a pair that decodes with
/// the system ANSI codepage and writes back UTF-8 with a BOM. Eleven characters
/// broke across the two files, one of them the version label, so the APK built
/// from it read "Test V-0.1 Â· build 2" on the splash screen of every handset.
///
/// This guard was already here and did not fire, because pubspec.yaml is not
/// under lib/ and neither is the script that did it. Anything a tool edits in
/// place is in scope now: lib/, tool/, and pubspec.yaml itself.
///
/// test/ stays OUT of scope on purpose — the mojibake table below is a table OF
/// the corrupt sequences, so a guard that scanned its own source would report
/// all nine of them, every run, forever.
void main() {
  test('no source, script or manifest is double-encoded', () {
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

    // lib/ for source, tool/ for the scripts that edit source, and pubspec
    // itself — the file that actually broke, and the one Android reads the
    // version out of.
    final targets = <File>[
      for (final root in ['lib', 'tool'])
        if (Directory(root).existsSync())
          ...Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) =>
                  f.path.endsWith('.dart') || f.path.endsWith('.ps1')),
      if (File('pubspec.yaml').existsSync()) File('pubspec.yaml'),
    ];

    // A scan that finds nothing passes without checking anything.
    expect(targets.length, greaterThan(50),
        reason: 'Only ${targets.length} files scanned — the roots or the '
            'extensions have drifted and this guard is checking almost '
            'nothing.');

    for (final entity in targets) {
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

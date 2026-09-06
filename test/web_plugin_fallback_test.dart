import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Four plugins and one core library compile for the web and throw when used.
///
/// `flutter build web` succeeds today with `dart:io` imported in three
/// services and `camera` in a fourth — dart2js accepts every one of them,
/// because the web SDK ships dart:io as a STUB that compiles and throws on
/// use, and a plugin with no web implementation only fails when its method
/// channel is called. So the build says nothing at all about whether the app
/// works in a browser, and the failure surfaces on a screen, in front of an
/// Owner, on first use.
///
/// Two ways a file may hold one of these, and only two:
///
///  1. Conditional import — the file is named `*_io.dart` and is only ever
///     reached through a `dart.library.io` conditional export. Preferred: the
///     web bundle then never compiles it at all.
///  2. A `kIsWeb` branch in the same file, for a plugin whose Dart API has no
///     `dart:io` types in its signatures and can simply be skipped.
const _webHostile = <String, String>{
  "import 'dart:io'": 'dart:io is a stub on web and throws on use',
  'package:camera/': 'camera has no web implementation',
  'package:google_mlkit_face_detection/':
      'ML Kit face detection has no web implementation',
  'package:local_auth/': 'local_auth has no web implementation',
  'package:geocoding/': 'geocoding has no web implementation',
};

void main() {
  test('no web-hostile API is reachable from a web build unguarded', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // A scan that finds nothing passes without checking anything.
    expect(dartFiles.length, greaterThan(100),
        reason: 'Only ${dartFiles.length} files scanned — lib/ moved and this '
            'guard is checking almost nothing.');

    final offenders = <String>[];

    for (final file in dartFiles) {
      // Platform-specific halves of a conditional import are the sanctioned
      // home for this code — the web bundle never compiles them.
      if (file.path.endsWith('_io.dart')) continue;

      final source = file.readAsStringSync();
      final guarded = source.contains('kIsWeb');

      for (final entry in _webHostile.entries) {
        if (source.contains(entry.key) && !guarded) {
          offenders.add('${file.path}: ${entry.key} — ${entry.value}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Reachable on web and will throw at runtime:\n'
            '${offenders.join("\n")}\n\n'
            'Move it behind a conditional import (a *_io.dart half) or a '
            'kIsWeb branch with a real fallback. Not a silent catch.');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nothing draws a stored file without resolving it first.
///
/// THE BUG THIS EXISTS FOR: `loans.live_photo_url`, `persons.profile_photo_url`,
/// `businesses.logo_url` and `customer_documents.file_url` used to hold a
/// signed URL valid for a year, so every display site could write
/// `NetworkImage(value)` and be done. They hold an object PATH now — the link
/// is minted on demand and expires in minutes — and a path is not a URL.
///
/// When that changed, three display sites were updated and thirteen were not.
/// The missed ones silently drew nothing: `NetworkImage('148/photo.jpg')` is
/// a perfectly valid Dart expression that fails at load time, so neither the
/// analyzer nor any widget test noticed. It did not show on the handset
/// either, because those images were already cached from before the change —
/// only a fresh install would have shown blank circles everywhere.
///
/// THE RULE: a file that constructs a network image must resolve the value in
/// the same file, through ManaStoredFile or ManaStoredImage. No allowlist —
/// every file that draws one today already does this, and a new file that
/// does not is exactly the mistake being guarded against.
///
/// Deliberately not "is this variable a stored column", which cannot be
/// decided statically. The blunt rule is checkable and the resolver is cheap.
const _networkImagePattern = r'\b(?:NetworkImage|Image\.network|CachedNetworkImage)\s*\(';

const _resolvers = ['ManaStoredFile', 'ManaStoredImage'];

void main() {
  final pattern = RegExp(_networkImagePattern);

  test('the guard catches a file that draws without resolving', () {
    // A scanner that finds nothing proves nothing unless it can catch the
    // real failure. This is verbatim the shape of all thirteen missed sites.
    const bad = '''
      CircleAvatar(
        backgroundImage: profile.profilePhotoUrl != null
            ? NetworkImage(profile.profilePhotoUrl!)
            : null,
      )
    ''';
    expect(pattern.hasMatch(bad), isTrue);
    expect(_resolvers.any(bad.contains), isFalse,
        reason: 'no resolver in the file — this is what must fail');

    const good = '''
      ManaStoredImage(
        bucket: 'profile-photos',
        stored: profile.profilePhotoUrl,
        builder: (context, image) => CircleAvatar(backgroundImage: image),
      )
    ''';
    expect(_resolvers.any(good.contains), isTrue);
  });

  test('every file drawing a network image resolves it in the same file', () {
    final violations = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      if (_resolvers.any(source.contains)) continue;

      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      violations.add('${file.path}:$line');
    }

    expect(
      violations,
      isEmpty,
      reason: 'These draw a network image without resolving a stored path in '
          'the same file. The columns hold object paths, not URLs — go '
          'through ManaStoredImage (or ManaStoredFile.signedUrl if you need '
          'the string). Offenders:\n  ${violations.join('\n  ')}',
    );
  });
}

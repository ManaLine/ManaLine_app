import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/app_version.dart';

/// The build number in Dart and the one in pubspec.yaml are the same number.
///
/// THE PROBLEM THIS EXISTS FOR: `versionCode` was 1 and `versionName` was
/// 0.1.0 for every build ever made. `dumpsys package` could not tell one APK
/// from another, so answering "is the latest code on that phone?" meant
/// comparing the APK's file mtime against the newest .dart file and trusting
/// the inference. A tester holding the handset had nothing at all.
///
/// The fix puts the number in two places, because Android reads it from
/// pubspec (`version: 0.1.0+N` → versionCode) and the screen reads it from
/// Dart. Two files holding one fact drift the first time somebody bumps one
/// and forgets the other — and the failure is silent and wrong in the worst
/// way: the screen would confidently name a build that is not the one running.
///
/// `tool/build_apk.ps1` bumps both together. This fails if anything else did
/// not.
void main() {
  /// `version: 0.1.0+7` → 7. Null when the `+N` is missing entirely, which is
  /// the state that started this: Flutter then defaults versionCode to 1 and
  /// every build looks alike.
  int? pubspecBuildNumber(String yaml) {
    final line = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
        .firstMatch(yaml)
        ?.group(1);
    if (line == null) return null;
    final plus = line.indexOf('+');
    if (plus < 0) return null;
    return int.tryParse(line.substring(plus + 1));
  }

  test('pubspec declares a build number at all', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspecBuildNumber(yaml),
      isNotNull,
      reason: 'pubspec.yaml has no `+N` on its version. Android then defaults '
          'versionCode to 1 for every build, which is exactly the state that '
          'made two APKs indistinguishable on a handset.',
    );
  });

  test('Dart and pubspec agree on which build this is', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(
      manaBuildNumber,
      pubspecBuildNumber(yaml),
      reason: 'manaBuildNumber in lib/shared/app_version.dart does not match '
          'the +N in pubspec.yaml. The screen would name one build while the '
          'APK carries another — worse than showing nothing, because it reads '
          'as verified. Bump both, or use tool/build_apk.ps1 which does.',
    );
  });

  test('a re-cut announces itself, and an ordinary build does not', () {
    // manaBuildRevision exists so an interim APK does not have to spend the
    // next build number — CLAUDE.md rates the app at 15, 20, 25, and those are
    // reserved for a build with handset findings behind it.
    expect(manaVersionLabel, contains('build $manaBuildNumber'));
    if (manaBuildRevision == 0) {
      expect(manaVersionLabel, isNot(contains('$manaBuildNumber.')),
          reason: 'revision 0 must read as a plain build number');
    } else {
      expect(manaVersionLabel, contains('$manaBuildNumber.$manaBuildRevision'));
    }
  });

  test('the label a tester reads names the version and the build', () {
    // Both halves matter and for different people: the name is what gets
    // spoken ("are you on Test V-0.1?"), the number is what identifies the
    // exact APK when two builds share a name.
    expect(manaVersionLabel, contains(manaVersionName));
    expect(manaVersionLabel, contains('$manaBuildNumber'));
  });
}

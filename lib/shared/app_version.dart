import 'package:flutter/material.dart';

import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';

/// What build is on this handset.
///
/// WHY THIS EXISTS. `versionCode` sat at 1 and `versionName` at 0.1.0 for every
/// build ever made, so `dumpsys package` could not tell one APK from another and
/// the only evidence of what was installed was a file timestamp. Working out
/// whether a phone had the latest code meant comparing the APK's mtime against
/// the newest .dart file and trusting the inference.
///
/// A tester holding the phone had nothing at all — no way to answer "is this
/// the build with the fix in it?" without asking somebody at a computer.
///
/// TWO NUMBERS, ONE SOURCE. [manaBuildNumber] must equal the `+N` in
/// pubspec.yaml, because that is what becomes Android's versionCode. They are
/// two files and would drift the first time somebody bumped one and forgot the
/// other — so `test/app_version_test.dart` parses pubspec and fails if they
/// disagree. `tool/build_apk.ps1` bumps both together, which is the path that
/// should normally be used.
///
/// NOT read from the installed package at runtime. package_info_plus would do
/// that and cannot drift at all, but it is only a TRANSITIVE dependency here —
/// pulled in by share_plus — and building on a package nothing declares is how
/// a working feature breaks during an unrelated upgrade. A guard test buys the
/// same safety for the cost of one file.
const manaVersionName = 'Test V-0.1';

/// Bumped once per build. Must match the `+N` in pubspec.yaml's version.
const manaBuildNumber = 12;

/// "Test V-0.1 · build 7" — the name a person reads, and the number that
/// identifies the APK.
String get manaVersionLabel => '$manaVersionName · build $manaBuildNumber';

/// The version, small and quiet, at the bottom of a screen.
///
/// Shown on the splash and on login: the two screens somebody sees before they
/// can reach anything else, so the question "which build is this?" is
/// answerable without signing in. Deliberately low contrast — it is for a
/// tester, not a customer, and it must not compete with the brand mark it sits
/// under.
class ManaVersionFooter extends StatelessWidget {
  const ManaVersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: ManaSpacing.sm,
        bottom: ManaSpacing.md,
      ),
      child: ManaText.raw(
        manaVersionLabel,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
      ),
    );
  }
}

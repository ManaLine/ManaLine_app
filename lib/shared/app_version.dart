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
const manaBuildNumber = 14;

/// A re-cut of the SAME build number, shown as `14.1`, `14.2`.
///
/// WHY A SECOND NUMBER RATHER THAN JUST BUMPING. The build numbers here are not
/// only APK identifiers — they are the schedule. CLAUDE.md rates the app at
/// builds 15, 20, 25, and a rating is grounded in findings from a handset, so
/// build 15 is spoken for before it is cut. Spending 15 on an interim APK would
/// either move the rating or silently skip it.
///
/// versionCode DELIBERATELY DOES NOT MOVE. It is an integer and cannot carry a
/// `.1`, and these are debug APKs installed with `adb install -r`, which does
/// not require an increment. So the handset shows `build 14.1` and
/// `dumpsys package` still says 14 — the two answer different questions, and
/// the one a tester reads is the one that distinguishes the APKs.
///
/// Reset to 0 by tool/build_apk.ps1 whenever it bumps [manaBuildNumber], or
/// build 15 would announce itself as 15.1.
const manaBuildRevision = 4;

/// "Test V-0.1 · build 14.1" — the name a person reads, and the number that
/// identifies the APK. The revision is omitted entirely at 0, so an ordinary
/// build reads `build 14` exactly as it always has.
String get manaVersionLabel => manaBuildRevision == 0
    ? '$manaVersionName · build $manaBuildNumber'
    : '$manaVersionName · build $manaBuildNumber.$manaBuildRevision';

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

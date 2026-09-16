import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A rupee figure DRAWN on screen goes through ManaAmount.
///
/// WHY THIS EXISTS. ManaAmount declares 16sp as the floor for money and says
/// why in its own header: money was being set at 11–12sp across the app, so
/// "the most important numbers in the app were among its smallest text". It
/// also carries tabular figures, without which a column of amounts does not
/// align — `1` is narrower than `8`, so ₹1,111 and ₹8,888 occupy different
/// widths and scanning a round for the odd figure out stops working.
///
/// Nothing enforced any of that. Two findings on 2026-09-16 came from the same
/// gap: the collection round drew its balance at 13sp, and ManaMoneyRow — the
/// shared component BOTH day-closing screens are built from, 23 call sites —
/// drew every figure at 13sp, or 15sp when emphasised. The screens an Owner
/// reads to decide whether the day's cash balances were under the floor, and
/// the suite could not see it.
///
/// WHAT IS NOT BANNED. The string form is correct wherever a widget cannot go,
/// and ManaAmount's own doc lists them: snackbar sentences, semantics labels,
/// interpolated strings, values stored rather than drawn. This guard catches
/// only the narrow case of an amount handed to ManaText as the whole of its
/// content — a figure being DRAWN, where a widget fits.
///
/// THE LIST BELOW IS A BACKLOG, NOT AN EXEMPTION, and it is the point of the
/// file. `_appliedButFileMissing` in translation_keys_exist_test.dart is the
/// same shape and went 69 → 21 → empty this month. Counting the debt is what
/// made it shrink; a rule with nothing keeping score does not.
///
/// SHRINKING THIS LIST IS PROGRESS. Adding to it is not — a new file here is a
/// new screen putting money below the floor, and the fix is ManaAmount, not an
/// entry. A count that goes UP fails, and so does a count that goes down
/// without the number being corrected, because the census is answered by
/// looking rather than by editing.
void main() {
  /// Files that still draw a bare amount through ManaText, and how many times.
  ///
  /// EMPTY, as of 2026-09-16. It was 20 files and 34 sites when this guard was
  /// written a few hours earlier; converting ManaMoneyRow took 23 call sites
  /// out in one edit, and the remaining 34 were done by hand.
  ///
  /// Kept rather than deleted, exactly as `_appliedButFileMissing` is kept in
  /// translation_keys_exist_test.dart after reaching zero by the same route:
  /// the argument above it is the argument for keeping it empty. A name added
  /// here is a screen drawing money below the 16sp floor, and the fix is
  /// ManaAmount, not an entry.
  const backlog = <String, int>{};

  /// `ManaText.raw(manaRupees(x))` and `ManaText.raw('${manaRupees(x)}')` —
  /// an amount as the ENTIRE content of a text widget. An amount inside a
  /// sentence is deliberately not matched: splitting those is a judgement
  /// about the sentence, not a mechanical swap, and a guard that demanded it
  /// would be demanding the wrong thing.
  ///
  /// THE INTERPOLATED HALF IS ANCHORED, and it was not at first. Written as
  /// `'\$\{manaRupees\(` it also matched `'\${manaRupees(x)} · \$other'` --
  /// a sentence that merely BEGINS with the figure. Two of those were on the
  /// first backlog (cw_003's template line, ow_007's penalty line) and
  /// converting either would have been the guard demanding a wrong answer.
  /// The closing `\}'` is what makes it mean "and then the string ends".
  final pattern = RegExp(
    r"""ManaText\.raw\(\s*(manaRupees\(|'\$\{manaRupees\([^)]*\)\}')""",
  );

  Map<String, int> scan() {
    final found = <String, int>{};
    void walk(Directory d) {
      for (final e in d.listSync()) {
        if (e is Directory) {
          walk(e);
        } else if (e is File && e.path.endsWith('.dart')) {
          final rel =
              e.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^lib/'), '');
          final n = pattern.allMatches(e.readAsStringSync()).length;
          if (n > 0) found[rel] = n;
        }
      }
    }

    walk(Directory('lib'));
    return found;
  }

  test('no NEW screen draws money below the floor', () {
    final found = scan();
    final added = found.keys.where((f) => !backlog.containsKey(f)).toList();
    expect(added, isEmpty,
        reason: 'these draw a rupee figure through ManaText instead of '
            'ManaAmount: ${added.join(', ')}. ManaAmount carries the 16sp '
            'floor, tabular figures and the screen-reader label. Use it — do '
            'not add a name to the backlog');
  });

  test('a file on the backlog has not grown', () {
    final found = scan();
    final grown = <String>[];
    for (final e in backlog.entries) {
      final now = found[e.key] ?? 0;
      if (now > e.value) grown.add('${e.key} ${e.value} -> $now');
    }
    expect(grown, isEmpty,
        reason: 'a file already carrying this debt added more of it: '
            '${grown.join('; ')}');
  });

  test('the backlog is answered by looking, not by editing the number', () {
    // A file that shrank is good news and still fails, deliberately: the
    // number here has to be corrected by somebody who has opened the file and
    // confirmed the remaining ones are really gone. That check IS the point,
    // and it is the discipline that took _appliedButFileMissing to zero.
    final found = scan();
    final stale = <String>[];
    for (final e in backlog.entries) {
      final now = found[e.key] ?? 0;
      if (now < e.value) stale.add('${e.key} ${e.value} -> $now');
    }
    expect(stale, isEmpty,
        reason: 'fixed some — record the new figure (or remove the entry): '
            '${stale.join('; ')}');
  });

  test('the pattern still recognises a violation, and still ignores a sentence', () {
    // A GUARD THAT CHECKS NOTHING READS EXACTLY LIKE ONE THAT PASSES, and with
    // the backlog at zero there are no real violations left to prove the
    // pattern still works. So it is tested against strings instead of against
    // the tree — which is stronger anyway: it keeps working the day somebody
    // reformats every file in lib/.
    expect(pattern.hasMatch('ManaText.raw(manaRupees(x))'), isTrue);
    expect(
      // A triple-quoted Dart string, so the line break is REAL and no escape
      // is needed. The escaped form has to survive every tool between the
      // editor and the file, and twice on 2026-09-16 it did not -- the second
      // time inside the comment explaining the first.
      pattern.hasMatch('''ManaText.raw(
    manaRupees(loan.balance),'''),
      isTrue,
      reason: 'the amount on the line after the paren is the case a shell '
          'grep missed when this backlog was first drafted',
    );
    expect(pattern.hasMatch(r"ManaText.raw('${manaRupees(x)}')"), isTrue);

    // And the two that must NOT match: an amount inside a sentence. Converting
    // either would be the guard demanding a wrong answer — splitting a
    // sentence is a judgement about the sentence, not a mechanical swap.
    expect(
      pattern.hasMatch(r"ManaText.raw('${manaRupees(x)} - ${other}')"),
      isFalse,
      reason: 'a sentence that merely BEGINS with the figure',
    );
    expect(
      pattern.hasMatch(r"ManaText.raw(ref.t('note').replaceAll('{a}', manaRupees(x)))"),
      isFalse,
      reason: 'an amount interpolated into a translated sentence',
    );
  });
}

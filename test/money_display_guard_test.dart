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
  /// Captured 2026-09-16, after ManaMoneyRow was converted — which removed 23
  /// call sites in one edit and is why 20 files carry 34 sites rather than
  /// closer to sixty.
  ///
  /// The first draft of this list came from a shell grep and was WRONG: it
  /// read one line at a time and missed every site where the amount sits on
  /// the line after `ManaText.raw(`. The guard reads whole files and found
  /// three more screens immediately, which is the guard earning its place
  /// before it had been committed.
  const backlog = <String, int>{
    'features/customer_workspace/screens/cw_004_my_loans.dart': 4,
    'features/investor_workspace/screens/iw_003_my_investments.dart': 3,
    'features/owner_workspace/screens/ow_013_account_review.dart': 3,
    'features/agent_workspace/screens/ag_001_agent_home_dashboard.dart': 2,
    'features/owner_workspace/screens/ow_003_investor_management.dart': 2,
    'features/owner_workspace/screens/ow_007_loan_details.dart': 2,
    'features/owner_workspace/screens/ow_009_daily_record_book.dart': 2,
    'features/owner_workspace/screens/ow_011_day_closure.dart': 2,
    'features/owner_workspace/screens/ow_015_group_loan_management.dart': 2,
    'features/owner_workspace/screens/ow_019_cheti_management.dart': 2,
    'features/admin/admin_panel_screen.dart': 1,
    'features/customer_workspace/screens/cw_003_request_new_loan.dart': 1,
    'features/owner_workspace/screens/loan_requests_screen.dart': 1,
    'features/owner_workspace/screens/ow_001_owner_home_dashboard.dart': 1,
    'features/owner_workspace/screens/ow_010_report_hub.dart': 1,
    'features/owner_workspace/screens/ow_pre_existing_loan_sheet.dart': 1,
    'features/owner_workspace/screens/ow_trash_screen.dart': 1,
    'features/owner_workspace/screens/withdrawal_requests_screen.dart': 1,
    'shared/customer_collections_tab.dart': 1,
    'shared/widgets/recent_deletes_screen.dart': 1,
  };

  /// `ManaText.raw(manaRupees(x))` and `ManaText.raw('${manaRupees(x)}')` —
  /// an amount as the ENTIRE content of a text widget. An amount inside a
  /// sentence is deliberately not matched: splitting those is a judgement
  /// about the sentence, not a mechanical swap, and a guard that demanded it
  /// would be demanding the wrong thing.
  final pattern = RegExp(
    r"""ManaText\.raw\(\s*(manaRupees\(|'\$\{manaRupees\()""",
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

  test('the scan is finding anything at all', () {
    // A guard that quietly checks nothing reads exactly like one that passes.
    // If the pattern stops matching, this says so rather than going green.
    final total = scan().values.fold<int>(0, (a, b) => a + b);
    expect(total, greaterThan(0),
        reason: 'the pattern has stopped matching — it is not that the backlog '
            'was cleared, it is that the guard went blind');
  });
}

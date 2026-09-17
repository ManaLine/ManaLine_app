import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every screen that adopted `ManaVillageSearchField` (Plan 4 Task 4) must
/// show exactly ONE PIN entry point.
///
/// `ManaVillageSearchField`'s PIN mode embeds `ManaVillagePickerField`, which
/// renders its own PIN `TextField` — that box IS the PIN entry now. Nine of
/// the ten adopting screens kept a screen-level PIN `TextField` alongside it
/// (the tenth, OW-012's Operating Areas tab, never used
/// `ManaVillageSearchField` for its own separate PIN+name search UI, so it
/// was never affected). Before Task 4 that screen-level field drove the
/// search via `onChanged`; after, that hook was removed, so the screen's box
/// went inert (only gated Save, then got overwritten by the picked village)
/// while a second, unlinked PIN box the person had never been shown before
/// did the actual narrowing. A box labelled "PIN Code" that does nothing,
/// sitting above an identical box that does everything, is worse than either
/// alternative — see task-4-review.md's Important finding.
///
/// This is a source-text guard, not a widget test: it proves no screen
/// DECLARES a PIN-controlled TextField in the same class that also calls
/// `ManaVillageSearchField`. It cannot prove the widget renders correctly at
/// runtime (`village_search_field_test.dart` covers that for the shared
/// widget itself) — it is a floor under regression, the same division of
/// labor `sql_enum_literal_guard_test.dart` and friends already use for
/// source-text checks in this repo.
void main() {
  // The ten screens Task 4 touched (task-4-review.md's Spec Compliance
  // section names them). Re-verified here by grepping `lib/` for
  // `ManaVillageSearchField(` rather than trusting that list — the census is
  // answered by looking, not by copying a count.
  const screens = [
    'lib/features/agent_workspace/screens/ag_004_customer_management.dart',
    'lib/features/customer_workspace/screens/cw_006_my_profile_memberships.dart',
    'lib/features/investor_workspace/screens/iw_005_my_profile_memberships.dart',
    'lib/features/login_registration/screens/lr_004_registration_form.dart',
    'lib/features/owner_workspace/screens/ow_000_first_business_setup.dart',
    'lib/features/owner_workspace/screens/ow_004_customer_management.dart',
    'lib/features/owner_workspace/screens/ow_012_business_management.dart',
    // ADDED 2026-09-17, after reading it rather than to make this pass.
    // OW-014's not-found step used to collect a village as FREE TEXT -- which
    // auth-register rejects outright (it validates address.village_id), so
    // that form had never once saved anybody. It uses the shared field now.
    //
    // Confirmed against this file's contract: the class declares no PIN
    // controller at all. _villagePin is a String set FROM the picked village,
    // not a TextEditingController driving a box, so there is exactly one PIN
    // entry point on the screen and it is the one inside the shared widget.
    //
    // Note the near-collision: this is ow_014_GLOBAL_WORKFLOW, a different
    // file from ow_014_profile_completion above it.
    'lib/features/owner_workspace/screens/ow_014_global_workflow.dart',
    'lib/features/owner_workspace/screens/ow_014_profile_completion.dart',
    'lib/features/owner_workspace/screens/ow_016_profile.dart',
    // OW-018 came OFF this list on 2026-09-14, with _MigrateLoanScreen.
    // That screen was the file's only village entry, it had been unreachable
    // since the Pre-Existing FAB was routed to the global search, and the
    // shared pre-existing loan sheet that replaced it takes an existing
    // customer and asks for no village at all. Removed after reading the
    // diff, not to make this list match.
  ];

  // A screen-level PIN box: a TextField/TextFormField whose controller name
  // itself says "pin code" (e.g. `_pinCode`, `pinCodeController`). This is
  // deliberately about the CONTROLLER, not the label text — ow_012's two
  // legacy PIN+name search panels use `pin_code_field` labels too, but they
  // are their own custom search UI (`operatingAreaSearchProvider`), not
  // `ManaVillageSearchField`, so they are excluded by never sharing a class
  // with a `ManaVillageSearchField(` call (checked below).
  final pinControllerTextField = RegExp(
    r'(?:TextField|TextFormField)\(\s*\n\s*controller:\s*\w*[Pp]in[Cc]ode\w*',
  );

  /// Splits a file into its top-level class bodies. Coarse (chunk boundaries
  /// are "next top-level `class` line", not a real brace parse) but enough
  /// for these files: no top-level class is nested inside another here, and
  /// the check only needs "does this stretch of source contain both X and Y".
  List<String> classChunks(String source) {
    final starts = <int>[];
    for (final m in RegExp(r'^class \w', multiLine: true).allMatches(source)) {
      starts.add(m.start);
    }
    if (starts.isEmpty) return [source];
    final chunks = <String>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : source.length;
      chunks.add(source.substring(starts[i], end));
    }
    return chunks;
  }

  test('every ManaVillageSearchField consumer is confirmed by looking', () {
    final found = <String>[];
    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final path = entry.path.replaceAll('\\', '/');
      if (path.endsWith('/village_search_field.dart')) continue;
      if (RegExp(r'ManaVillageSearchField\(').hasMatch(entry.readAsStringSync())) {
        found.add(path);
      }
    }
    expect(
      found.toSet(),
      screens.map((s) => s).toSet(),
      reason: 'A screen started or stopped using ManaVillageSearchField. '
          'Update the `screens` list above after confirming why by reading '
          'the diff, not by adjusting this list to match.',
    );
  });

  for (final path in screens) {
    test('$path has one PIN entry point, not two', () {
      final source = File(path).readAsStringSync();
      for (final chunk in classChunks(source)) {
        final hasVillageSearch = chunk.contains('ManaVillageSearchField(');
        final hasPinController = pinControllerTextField.hasMatch(chunk);
        expect(
          hasVillageSearch && hasPinController,
          isFalse,
          reason: 'This class calls ManaVillageSearchField AND declares its '
              'own PIN-controlled TextField. ManaVillageSearchField\'s PIN '
              'mode already renders one (via ManaVillagePickerField) — a '
              'second, unlinked box here is the exact duplication '
              'task-4-review.md flagged.',
        );
      }
    });
  }
}

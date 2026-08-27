import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_investor_entry_sheets.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_member_picker.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The three widgets in this file are the last in lib/features/*/screens with
/// no layout test: two money-entry sheets and the picker that chooses who the
/// money belongs to.
///
/// They are widgets rather than routed screens, so they are pumped directly --
/// which is also why nothing had ever laid them out: a screen sweep by route
/// or by screen ID does not see them.
void main() {
  const who = ManaMemberRef(
    mlid: 'MLIN0000012345',
    fullName: 'Nagabhushanam Venkata Subba Reddy',
    village: 'Srikalahasti — Uranduru Colony',
  );

  final members = [
    who,
    const ManaMemberRef(
      mlid: 'MLIN0000012346',
      fullName: 'Kandukuri Siva Rama Krishna',
      village: 'Puttur',
    ),
  ];

  final cases = <String, Widget Function()>{
    'Investment sheet': () => InvestmentSheet(who: who, cutoff: DateTime(2026, 4, 1)),
    'Shareholder sheet': () => ShareholderSheet(who: who),
    'Member picker': () => ManaMemberPicker(
          members: members,
          onPick: (_) {},
          emptyNote: 'Nobody left to choose.',
        ),
  };

  for (final entry in cases.entries) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('${entry.key} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            Scaffold(body: entry.value()),
            textScale: scale,
            language: lang,
          );
          await tester.pumpAndSettle();
          expectNoLayoutFault(tester, '${entry.key} at ${scale}x$tag');
        });
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/business_name_checker.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// One of the dialogs that took `scrollable: true` in a sweep with no test
/// opening it. This one can be pumped directly -- it is a public widget,
/// shared by OW-000's wizard and OW-012's Create Business dialog -- so there
/// is no excuse for it staying unproven.
///
/// The alternatives list is the part that grows: each is a ListTile with a
/// button beside it, and a business name is as long as somebody wants.
void main() {
  Widget host(List<String> alternatives) => Scaffold(
        body: Builder(
          builder: (context) => BusinessNameTakenDialog(
            name: 'Sri Satyanarayana Finance Corporation',
            alternatives: alternatives,
          ),
        ),
      );

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      testWidgets('name-taken dialog survives text scale ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          host(const [
            'Sri Satyanarayana Finance Corporation Srikalahasti',
            'Sri Satyanarayana Finance Corporation 2026',
          ]),
          textScale: scale,
          language: lang,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoLayoutFault(tester, 'name-taken dialog at ${scale}x$tag');
      });

      // The empty branch renders different content, so it is its own case.
      testWidgets('name-taken dialog with no alternatives survives ${scale}x$tag',
          (tester) async {
        await pumpManaScreen(
          tester,
          host(const []),
          textScale: scale,
          language: lang,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoLayoutFault(tester, 'name-taken dialog, no alternatives, ${scale}x$tag');
      });
    }
  }
}

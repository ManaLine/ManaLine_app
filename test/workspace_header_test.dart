import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_app_bar.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// The three actions every Owner and Agent header carries, and the screens
/// that must not carry them.
///
/// They are installed once by route prefix rather than added to 45 ManaAppBar
/// call sites, which is how this app came to have 79 hand-rolled bars. That
/// makes the route the contract, so these test the route.
///
/// The width is the real risk. Back arrow, title, and three 48dp actions on a
/// 360px bar is the shape this codebase has shipped an overflow in four times,
/// and the labels are translated, so their width is data.
Widget _screen(String title) => Scaffold(
      appBar: ManaAppBar(title: title, homeRoute: '/ow-001'),
      body: const SizedBox.shrink(),
    );

void main() {
  group('who gets the standard actions', () {
    testWidgets('an Owner screen carries notifications, add expense, search',
        (tester) async {
      await pumpManaScreen(tester, _screen('Customer Management'),
          location: '/ow-004');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('an Agent screen carries the same three', (tester) async {
      await pumpManaScreen(tester, _screen('Collection Mode'),
          location: '/ag-002');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('login and registration carry none of them', (tester) async {
      // No session yet, so there is no business to record an expense against
      // and nothing to search. A header action that cannot act is not one.
      await pumpManaScreen(tester, _screen('Enter PIN'), location: '/lr-009');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    });

    testWidgets('the customer workspace carries none of them', (tester) async {
      await pumpManaScreen(tester, _screen('My Loans'), location: '/cw-004');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsNothing);
    });
  });

  // A long title beside all three actions, at every scale, in both languages.
  // Telugu is not decoration here: "Customer Management" is one word wider
  // translated, and the bar has 168px left for it once the arrow and three
  // actions have taken theirs.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('the header survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          _screen('Nagabhushanam Venkata Subba Reddy'),
          location: '/ow-004',
          textScale: scale,
          language: lang,
        );
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'workspace header at ${scale}x$tag');
      });
    }
  }
}

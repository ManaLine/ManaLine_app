import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_017_statement_screen.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-017's Statement screen had no layout test. It takes no provider on
/// first build -- the ledger service is only touched on download -- so the
/// screen itself is pumped directly.
void main() {
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-017 Statement survives text scale ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const StatementScreen(
            businessId: 'b1',
            // A real business name -- long, and it sits in the app bar.
            businessName: 'Sri Satyanarayana Finance Corporation',
          ),
          textScale: scale,
          language: lang,
        );
        await tester.pumpAndSettle();
        expectNoLayoutFault(tester, 'OW-017 Statement at ${scale}x$tag');
      });
    }
  }
}

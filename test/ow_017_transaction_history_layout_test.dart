import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_017_transaction_history.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-017 loads straight from Supabase in `_load()` rather than through a
/// provider, so there is nothing to seed — the screen lands in its error
/// branch, which still exercises the AppBar title this pass wired.
const _telugu = <String, Map<String, String>>{
  'history': {'English': 'History', 'Telugu': 'చరిత్ర'},
  'net_change_this_view': {'English': 'Net Change (This View)', 'Telugu': 'నికర మార్పు (ఈ వీక్షణ)'},
  'no_transactions_yet': {'English': 'No transactions yet.', 'Telugu': 'ఇంకా లావాదేవీలు లేవు.'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('OW-017 transaction history survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, const TransactionHistoryScreen(businessId: 'b1'), textScale: scale);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-017 at ${scale}x');
    });

    testWidgets('OW-017 transaction history survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(tester, const TransactionHistoryScreen(businessId: 'b1'),
          textScale: scale, language: ManaLanguage.telugu, translations: _telugu);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-017 at ${scale}x in Telugu');
    });
  }
}

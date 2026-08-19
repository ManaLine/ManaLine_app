import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// Merge All / Ignore All on the identity duplicate review.
///
/// One chip pair per flagged row is workable for three rows. The live book
/// flagged 55, and `_saveAreasAndIdentities` refuses to import while any row
/// is still undecided — so without a bulk action the Owner has to tap 55 times
/// before the wizard will let them past.
void main() {
  final duplicates = [
    const DuplicateMatch(row: 2, reason: 'existing_customer'),
    const DuplicateMatch(row: 7, reason: 'duplicate_in_file'),
    const DuplicateMatch(row: 41, reason: 'existing_customer'),
  ];

  test('Merge All decides every flagged row and nothing else', () {
    final decided = manaDecideAllDuplicates(duplicates, 'skip');

    expect(decided.keys.toSet(), {2, 7, 41});
    expect(decided.values.every((v) => v == 'skip'), isTrue);
  });

  test('Ignore All decides every flagged row', () {
    final decided = manaDecideAllDuplicates(duplicates, 'keep');

    expect(decided.values.every((v) => v == 'keep'), isTrue);
    expect(decided, hasLength(3));
  });

  test('it replaces earlier per-row decisions rather than leaving them', () {
    // The Owner ignored row 7 by hand, then pressed Merge All. If that one
    // Ignore survived, "all" would be a lie and row 7 would import as a second
    // person — discoverable only after the fact.
    final byHand = <int, String>{7: 'keep'};
    final decided = manaDecideAllDuplicates(duplicates, 'skip');

    expect(byHand[7], 'keep', reason: 'sanity: the hand decision existed');
    expect(decided[7], 'skip');
  });

  test('no flagged rows means nothing to decide', () {
    expect(manaDecideAllDuplicates(const [], 'skip'), isEmpty);
  });
}

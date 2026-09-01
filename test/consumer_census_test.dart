import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How many files depend on each shared thing, written down.
///
/// THE FAILURE THIS EXISTS FOR, which no other guard addresses: every other
/// test in this repo fires only once you already suspect something. This one
/// fires when you DON'T.
///
/// Both of the worst regressions here were failures of recognition rather than
/// of care. Moving the photo columns from signed URLs to storage paths, I
/// thought "the uploader and three display sites" — there were sixteen, and
/// thirteen silently drew nothing. Making account periods open-ended, I
/// thought "the settlement window" — a second consumer took the same function
/// to mean "has this customer paid yet" and blocked every weekly collection
/// for fifteen days. In both cases the change was right and the census was
/// wrong, and nothing on earth was going to tell me.
///
/// So: a committed count per shared symbol. Change the count and the test
/// fails, which is the prompt to go and look at what now uses it.
///
/// HOW TO ANSWER A FAILURE. Never by editing the number first.
///   * count went UP — a new consumer exists. Open it. Does it honour the
///     contract? A file that draws `ManaStoredImage` correctly is fine; one
///     that reached for the raw column is the bug. Then update the number.
///   * count went DOWN — a consumer was removed or migrated away. Make sure
///     it was deliberate and not a site you meant to keep. Then update it.
///
/// FILES, not references. Moving three call sites around inside one file is
/// not a change in coupling; a fourth file taking a dependency is. Comments
/// mentioning the symbol count too, and that is deliberate — a doc comment
/// pointing at a contract is a place that will mislead somebody if the
/// contract moves.
///
/// This is a tripwire, not a metric. It is allowed to be noisy. It is not
/// allowed to be ignored.
const _census = <String, int>{
  // The stored-file contract. These columns hold object paths, not URLs, and
  // a consumer that forgets draws an empty box. Sixteen sites, three updated.
  'ManaStoredFile': 11,
  'ManaStoredImage': 10,
  'ManaBusinessLogo': 5,

  // The PIN directory pickers. State narrows district narrows mandal, and a
  // screen that half-adopts it silently offers free text again.
  'ManaReferenceField': 3,
  'manaReferenceOptions': 3,

  // Two ledgers, one provider family. Keyed on business alone, the Owner's
  // feed and an Agent's were one object and whichever loaded last won.
  'ledgerHistoryProvider': 2,
  'LedgerScope': 2,

  // Adding a kind means updating every exhaustive switch over it. The
  // analyzer catches the switches; this catches the screens that filter by
  // kind and would quietly omit the new one.
  'InboxActionKind': 3,

  // The add-customer sheet, opened from several places with different
  // arguments.
  'ManaAddCustomerSheet': 2,

  // Where "my profile" resolves to when no workspace has been chosen.
  'manaLastUsedProfileRoute': 3,

  // IST, everywhere. A new file that reaches for DateTime.now() instead of
  // these is the timestamp bug class, and it will show up here as these
  // counts failing to grow alongside the codebase.
  'manaBusinessDate': 17,
  'manaTimestamp': 9,

  // GPS never blocks anything, and every caller depends on that contract.
  'ManaLocation': 7,
};

int _filesReferencing(String symbol) {
  final pattern = RegExp(r'\b' + RegExp.escape(symbol) + r'\b');
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => pattern.hasMatch(f.readAsStringSync()))
      .length;
}

void main() {
  test('the census counts files, not mentions within one file', () {
    // A symbol nothing uses must read zero, or the counter is measuring
    // something other than coupling.
    expect(_filesReferencing('ManaDefinitelyNotARealSymbol'), 0);
    // And a real one must be found at all.
    expect(_filesReferencing('ManaStoredFile'), greaterThan(0));
  });

  test('nothing has quietly gained or lost a consumer', () {
    final drifted = <String>[];
    _census.forEach((symbol, expected) {
      final actual = _filesReferencing(symbol);
      if (actual == expected) return;
      drifted.add('$symbol: recorded $expected, found $actual '
          '(${actual > expected ? '+' : ''}${actual - expected})');
    });

    expect(
      drifted,
      isEmpty,
      reason: 'The number of files depending on a shared contract changed.\n'
          'This is not a failure to fix by editing the number. Open the new '
          'or missing consumer first and check it honours the contract — that '
          'check is the entire point of this test — then update the count.\n\n'
          '  ${drifted.join('\n  ')}',
    );
  });
}

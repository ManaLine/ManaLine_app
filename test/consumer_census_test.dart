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
  // 11 -> 13 on 2026-09-18: payment_details_sheet.dart and
  // payment_details_editor.dart, the QR display and its editor. Both were
  // opened and checked against the contract before this number moved, which
  // is what this test is for: the column stores a storage PATH
  // (`businesses.upi_qr_path`), and each display site calls
  // ManaStoredFile.signedUrl at render time. Neither writes a signed URL into
  // the database, which is the failure this contract exists to prevent.
  'ManaStoredFile': 13,
  'ManaStoredImage': 10,
  'ManaBusinessLogo': 5,

  // The PIN + village picker, as a WIDGET. The service was consolidated first;
  // this is the widget half, added so the two Create Business forms did not
  // become copies eleven and twelve of a pattern that had already drifted ten
  // ways. A new dependant here is a screen that should probably be using it
  // rather than growing another.
  //
  // Went 4 -> 9 when Plan 4 Task 4 swapped all ten remaining consumers from
  // ManaVillagePickerField to ManaVillageSearchField. Checked all seven new
  // mentions: they are doc comments on the replacement code in CW-006,
  // IW-005, LR-004, OW-000, OW-004, OW-014 and OW-016, explaining the
  // contract ("does not write anything", resolve on pick) the way the old
  // inline code used to explain it inline. AG-004, OW-012 and OW-018's swaps
  // added no such comment. None of the ten instantiates
  // ManaVillagePickerField directly any more — the two real uses are its own
  // file and ManaVillageSearchField's PIN-mode embed, unchanged from before.
  //
  // Went 9 -> 11 fixing task-4-review.md's Important finding (nine of the
  // ten screens kept a duplicate, unlinked screen-level PIN TextField beside
  // ManaVillageSearchField). AG-004 and OW-018 gained their first mention: a
  // doc comment on the new `_villagePinCode`/`selectedVillagePinCode` field
  // explaining that ManaVillageSearchField's PIN mode embeds
  // ManaVillagePickerField, which renders the actual PIN box now, so the
  // submitted pin_code has to come from the picked village rather than a
  // screen-typed one. Checked: both are doc comments only, same as the seven
  // above — still nothing instantiates ManaVillagePickerField directly.
  //
  // Went 11 -> 10 when _MigrateLoanScreen was deleted from OW-018. Checked
  // before recording: OW-018's only mention was that screen's own
  // `_villagePinCode` doc comment, and the screen was the file's only village
  // entry point at all. It had gone unreachable when the Pre-Existing FAB was
  // routed to the global search, and its job now belongs to the shared
  // pre-existing loan sheet, which takes an EXISTING customer and therefore
  // asks for no village. So OW-018 has no village control left, which is
  // correct: it is a summary of a book, and people reach it through the
  // search. A count that goes DOWN still gets opened -- a consumer lost
  // silently is the same failure as one gained silently.
  'ManaVillagePickerField': 10,
  'manaComposeAddress': 3,

  // Adding a village the LGD directory has never recorded. Went 8 -> 1 in
  // the same swap: LR-004 and OW-004 (the two Create Business forms this
  // sheet says it exists for) moved to ManaVillageSearchField too, whose PIN
  // mode has its own inline add-panel rather than opening this sheet, and
  // the address editors (CW-006, IW-005, OW-014, OW-016) followed the same
  // path.
  // Back to 2: ManaVillageSearchField's cascade branch (state -> district ->
  // name) now calls this sheet too, once the stale-response race in
  // village_search_field.dart was fixed. Checked: the new call passes
  // cascadeState/cascadeDistrict (locked from the cascade selection) and
  // initialName (the already-typed query), asks for mandal and a PIN — the
  // cascade collects neither — and treats the returned village exactly like
  // a tapped search result, emitting it through onPicked. PIN mode is
  // unchanged and still does not call this sheet.
  'manaShowAddVillageSheet': 2,

  // The PIN directory pickers. State narrows district narrows mandal, and a
  // screen that half-adopts it silently offers free text again.
  //
  // Went 3 -> 1 in the same swap: LR-004 and OW-004 each carried a comment
  // naming ManaReferenceField as what their old manual village form was
  // replaced by ("... rather than four" / "... through ManaReferenceField
  // rather than as free"). Both comments were themselves rewritten when
  // those two screens moved on to ManaVillageSearchField, so the mentions
  // went with them. Checked: ManaReferenceField's own file is the only one
  // left, and manaReferenceOptions still has its one caller inside it — the
  // widget itself is untouched by this task and its retirement is still the
  // Owner's call, same as before.
  'ManaReferenceField': 1,
  'manaReferenceOptions': 1,

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
  //
  // 2 -> 3 on 2026-09-18. The third is ow_village_customers.dart, which adds
  // somebody from inside the village they live in ("inside village - enable
  // to add a customer"). CHECKED, not just counted: it opens the same sheet
  // with businessId and migrationEntry rather than rolling a form of its own,
  // which is the contract that matters here -- the sheet owns every rule
  // about what a customer needs, and a private copy would be the second place
  // to fix any of them.
  'ManaAddCustomerSheet': 3,

  // Where "my profile" resolves to when no workspace has been chosen.
  //
  // Went 3 -> 4 when /profile was added. The fourth is router.dart, and it is a
  // COMMENT, not a call — the one explaining why /profile exists. Counted
  // anyway, deliberately: a comment describing a contract is a place that
  // misleads somebody if the contract moves, which is the whole reason this
  // census counts mentions rather than call sites. Opened and checked: it
  // describes the resolver accurately, including that it no longer returns
  // null.
  'manaLastUsedProfileRoute': 4,

  // IST, everywhere. A new file that reaches for DateTime.now() instead of
  // these is the timestamp bug class, and it will show up here as these
  // counts failing to grow alongside the codebase.
  'manaBusinessDate': 17,
  // 10 since local_auth_store.recordBusinessOpened, checked by opening it:
  // it stamps when this device last opened a business, for the workspace
  // list's tie-break. Honours the contract -- manaTimestamp(), not a bare
  // DateTime.now() -- and its values are only ever compared against others
  // written by the same call, so consistency is the whole requirement.
  // Went 10 -> 11 with lib/shared/outbox/mana_outbox_entry.dart. Answered by
  // OPENING it, as this test requires: both call sites -- ManaOutboxEntry
  // .create and .editedTo -- stamp createdAt with manaTimestamp(), and there
  // is no bare DateTime.now() anywhere in lib/shared/outbox/. That matters
  // more here than in most places: an outbox entry's createdAt is what orders
  // the queue and what a "stuck since" message would read from, and the
  // handset clock is exactly what manaTimestamp exists to avoid trusting.
  'manaTimestamp': 11,

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

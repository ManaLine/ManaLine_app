import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The customer search shows what it found; it does not choose.
///
/// REPORTED 2026-09-16: searching a customer was "showing what is found ... and
/// auto selecting it". With exactly one match the sheet set `_foundIdentity`
/// itself, so a filled tick and an enabled "Add & Issue Loan" appeared for a
/// person the Owner had not yet looked at. The screen had made the decision and
/// was showing the confirmation.
///
/// WHY THAT MATTERS MORE HERE THAN IT WOULD ELSEWHERE. This sheet links a
/// person to a business. In a village where several people share a name, the
/// single row a query returns is not necessarily the right person — it is the
/// only person who matched the letters typed. The card carries the father's or
/// husband's name and the village precisely because those are what tell two
/// people apart, and a pre-selected row is a card nobody has to read.
///
/// The second gap: recognising nobody on the list left only "Search Again",
/// which searches for the person just decided against. A genuinely new
/// customer needed a door that was two screens away.
///
/// SOURCE-LEVEL, and that is a deliberate limitation. Driving the real sheet
/// needs a seeded identity search and the whole harness; what actually broke
/// was two lines of decision-making, and these pin those two lines. A widget
/// test would be better and is worth writing when this sheet next gets one.
void main() {
  final source = File(
          'lib/features/owner_workspace/screens/ow_004_customer_management.dart')
      .readAsStringSync();

  test('a search selects nobody', () {
    expect(
      source,
      isNot(contains('_foundIdentity = matches.length == 1 ? matches.first : null')),
      reason: 'a lone match must be shown, not chosen — linking the wrong '
          'person to a business is not a mistake that announces itself',
    );
    expect(source, contains('_foundIdentity = null;'),
        reason: 'the search path must clear the selection');
  });

  test('the duplicate warning keeps its own selection', () {
    // NOT the same question, and the reason this test exists next to the one
    // above. There the screen asks "which of these people do you mean"; here it
    // asks "are you about to make a second record of somebody already on the
    // book", and pointing at who it means is the entire content of the warning.
    // Removing it to look consistent would take the subject out of the warning.
    expect(
      source,
      contains('_foundIdentity = likely.length == 1 ? likely.first : null'),
      reason: 'the duplicate guard should still name the person it is warning '
          'about',
    );
  });

  test('a list of matches offers a way to create somebody new', () {
    expect(source, contains('_stage = _AddCustomerStage.createNew'),
        reason: 'recognising nobody on the list must not leave only '
            '"Search Again", which searches for the person just ruled out');
  });

  test('both empty Loans tabs offer a loan', () {
    // A customer with no loan is the most likely person to be about to get
    // one. Both screens said so and stopped — the Owner's offered nothing at
    // all, the Agent's hid Create Loan in the overflow menu behind a glyph.
    for (final path in [
      'lib/features/owner_workspace/screens/ow_004_customer_management.dart',
      'lib/features/agent_workspace/screens/ag_004_customer_management.dart',
    ]) {
      final tab = File(path).readAsStringSync();
      expect(tab, contains('no_loans_yet'),
          reason: '$path should still say when there are none');
      expect(
        tab.contains("ref.t('new_loan')") || tab.contains("ref.t('create_loan')"),
        isTrue,
        reason: '$path must offer a way forward from an empty Loans tab',
      );
    }
  });
}

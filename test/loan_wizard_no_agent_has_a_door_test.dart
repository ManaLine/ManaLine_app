import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hitting "no active agents" mid-loan must not be the end of the sentence.
///
/// A loan cannot be assigned without a collection agent, so OW-005 stopped the
/// Owner halfway through creating one with a snackbar and nothing else: leave
/// the wizard, find Workforce, add an agent, come back, and start the loan
/// again from the customer.
///
/// The same first-domino shape OW-012's Account Periods tab was fixed for —
/// its own comment records it as "true, but useless, because nothing on screen
/// said where an Account Period comes from". An agent is where a collection
/// agent comes from, and that door is now one tap.
///
/// FOUND BY AUDIT, NOT BY REPORT. 114 places in lib/ render a "nothing here
/// yet" string; 44 have an action beside them and 70 do not. Nearly all of the
/// 70 are correctly actionless — a filtered view whose fix is the filter
/// already on screen, a read-only day-book section, a field that says "not on
/// file", an empty queue that is good news, and one case in OW-015 that is
/// deliberately actionless with the reason written into it. This was the one
/// that was genuinely a wall.
///
/// SOURCE-LEVEL, and that is a limitation rather than a preference: driving
/// this needs the whole wizard plus a seeded, empty workforce. What broke was
/// a missing action on a snackbar, and this pins that it is there.
void main() {
  final source =
      File('lib/features/owner_workspace/screens/ow_005_new_loan_workflow.dart')
          .readAsStringSync();

  test('the no-agent snackbar carries a way to add one', () {
    expect(source, contains('no_active_agents_note'),
        reason: 'it should still say what is wrong');
    expect(source, contains('SnackBarAction'),
        reason: 'saying "no active agents" and stopping leaves the Owner to '
            'leave the wizard, add an agent elsewhere, and restart the loan '
            'from the customer');
    expect(source, contains("/ow-search?role=agent"),
        reason: 'the action must lead to adding an agent, not to a general '
            'screen the Owner then has to navigate themselves');
  });

  // A SECOND TEST WAS WRITTEN HERE AND DELETED, which is worth recording.
  //
  // It asserted that the explanation appears BEFORE the offer in the source,
  // to stop a door replacing the statement of what the wall is. It failed
  // immediately — on the comment above the snackbar, which contains the word
  // SnackBarAction and sits earlier in the file than the message does.
  //
  // A test that a COMMENT can flip is not measuring the code. Tightening the
  // pattern until it passed would have kept a check that proves nothing and
  // breaks on prose. The rule it was trying to hold — say what is wrong, then
  // offer the way out — is a review question, not an assertion, and it is
  // written down here instead of faked above.
}

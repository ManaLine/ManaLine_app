import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mana_line/features/owner_workspace/state/global_workflow_state.dart';

/// Adding somebody the app has just said does not exist must not search again.
///
/// THE FLOW THIS FIXES, reported 2026-09-16 as "that's a blunder":
///
///   1. Enter One by One → Add Investor
///   2. → universal search, type a name, "No identity found."
///   3. → tap "Add Investor"
///   4. → "Search Existing MLID — Type: Investor". Mobile number, or MLID.
///
/// Step 4 asks for the person step 2 has already finished failing to find.
/// Searching twice for somebody the app has already answered about is not a
/// safeguard; it is the app disbelieving its own answer, and it is a dead end
/// for the common case — a person being entered from a paper book has no MLID
/// yet, which is the whole reason they are being registered.
///
/// The registration form was never missing. WizardStage.notFound has always
/// BEEN it, reachable only by performing the search that had already been
/// performed.
void main() {
  test('startAtRegistration opens the form, not the search', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(globalWorkflowProvider.notifier)
        .initWithType(MemberType.investor, startAtRegistration: true);

    final state = container.read(globalWorkflowProvider);
    expect(state.stage, WizardStage.notFound,
        reason: 'the caller already searched; this must be the form');
    expect(state.memberType, MemberType.investor);
    expect(state.searchedNotFound, isTrue,
        reason: 'the form should read as the answer to a search that ran, not '
            'as a step somebody wandered into');
  });

  test('without the flag the search step is still the entry', () {
    // The flag is for callers that HAVE searched. A caller that has not —
    // a header action, a deep link — must still be offered the search, because
    // attaching an existing person is the other half of this screen's job and
    // creating a duplicate identity is the expensive mistake.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(globalWorkflowProvider.notifier)
        .initWithType(MemberType.agent);

    final state = container.read(globalWorkflowProvider);
    expect(state.stage, WizardStage.searchMlid);
    expect(state.searchedNotFound, isFalse);
  });

  test('the not-found button carries new=1, or the fix is not wired', () {
    // The notifier above can be correct while nothing asks for it — the exact
    // shape of the SP-001 gate that sat uncalled for weeks. This checks the
    // one caller that has already searched actually says so.
    final source = File(
            'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart')
        .readAsStringSync();
    expect(source, contains("&new=1"),
        reason: 'the "No identity found" button must open OW-014 on the '
            'registration form; without new=1 it reopens the MLID search and '
            'asks for the person it has just failed to find');
  });
}

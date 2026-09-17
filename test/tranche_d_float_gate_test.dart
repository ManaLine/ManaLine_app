import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// The float gate: asked early, and answered according to who is asking.
///
/// THREE FINDINGS FROM ONE HANDSET SESSION, all on the Stf book:
///
///   "why letting user to fill all the details and then showing error"
///   "owner tried to issue loan with BF 0, app asked to send request --
///    it's a blunder, according to role app should behave"
///   "it's not an error it's a requirement that's not met"
///
/// One cause. app.create_loan_with_bf_check was the only thing that knew the
/// float and it is a WRITE that takes a live photo URL, so the answer could
/// only be learned at the end; the single remedy ever written was the
/// Agent's; and the refusal was thrown as an exception, so the generic
/// handler spoke over the card that was already explaining it.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  final wizard = lib('features/owner_workspace/state/loan_wizard_state.dart');
  final gate = lib('shared/float_gate_card.dart');

  group('the question is asked before the photo', () {
    test('the read-only position RPC exists and has one overload', () {
      // A plpgsql body is not type-checked at CREATE time, so the snapshot is
      // what says this name is real. A second overload is PGRST203 and the
      // screen would only say it could not load.
      expect(manaAppFunctions, contains('loan_float_position'));
      expect(manaAppFunctionOverloads,
          isNot(contains('loan_float_position')));
    });

    test('step 3 is the gate, because it is where both facts first exist', () {
      // The amount and the collecting agent are both decided on step 3. Any
      // earlier and the question has no answer; any later and a guarantor and
      // a live photo have already been collected -- and the photo, by rule,
      // cannot be re-used.
      final setter = wizard.substring(
          wizard.indexOf('Future<bool> setLoanDetails('),
          wizard.indexOf('/// The Owner\'s remedy'));
      expect(setter, contains('floatPosition('),
          reason: 'step 3 must ask about the float before it advances');
      expect(setter, contains('LoanWizardStep.guarantor'),
          reason: 'and it must still advance when the float is fine');
      // The refusal path returns false WITHOUT setting the next step.
      final refusal = setter.substring(setter.indexOf('if (position != null'));
      expect(refusal.substring(0, refusal.indexOf('return false;')),
          isNot(contains('step:')),
          reason: 'a refused loan must not walk on to the guarantor step');
    });

    test('a failure to ASK is not a refusal', () {
      // This app works at doorsteps. Blocking a loan because a phone could not
      // reach the server would turn a network blip into a refused customer,
      // and the binding check still runs at the end.
      final setter = wizard.substring(
          wizard.indexOf('Future<bool> setLoanDetails('),
          wizard.indexOf('/// The Owner\'s remedy'));
      expect(setter, contains('} catch (_) {'),
          reason: 'an unreachable server must let the wizard continue');
      expect(setter, contains('position != null &&'),
          reason: 'the block is conditional on having actually got an answer');
    });

    test('the server is still the authority', () {
      // The early gate is a warning, not a replacement. Money moves between
      // the two -- another loan off the same float, a collection landing --
      // and only create_loan_with_bf_check holds the row lock.
      expect(wizard, contains('create_loan_with_bf_check'),
          reason: 'the binding check must not have been deleted in favour of '
              'the advisory one');
    });
  });

  group('the remedy depends on who is asking', () {
    test('an Owner is offered a top-up, never a request to themselves', () {
      final owner = gate.substring(gate.indexOf('final canTopUp'));
      expect(owner, contains("ref.t('top_up_agent_bf')"));
      expect(owner.contains('ManaBfRequestCard'), isFalse,
          reason: 'the Owner branch must never reach the Agent card -- an '
              'Owner who is also the collecting agent would be asked to send '
              'themselves a request, which is the finding');
    });

    test('an Agent still gets the card written for them', () {
      final agent = gate.substring(gate.indexOf('if (!widget.position.viewerIsOwner)'));
      expect(agent.substring(0, agent.indexOf('final canTopUp')),
          contains('ManaBfRequestCard'),
          reason: 'the Agent remedy was correct and is reused, not rebuilt');
    });

    test('an empty business offers no button at all', () {
      // app.grant_agent_bf raises when the business is short, so a Top Up
      // button there would be a control that cannot work -- which is how the
      // request-to-yourself shipped in the first place.
      final empty = gate.substring(gate.indexOf('] else ...['));
      expect(empty, contains("ref.t('business_bf_empty_headline')"));
      expect(empty.contains('FilledButton'), isFalse,
          reason: 'no button when the server would refuse it');
    });

    test('never set up reads differently from spent', () {
      // Both are live on the Stf book -- one agent of each -- which is why
      // the RPC returns has_assignment separately from a zero float.
      expect(gate, contains('!widget.position.hasAssignment'));
      expect(gate, contains("'agent_not_set_up_note'"));
    });

    test('the top-up reads the number back rather than assuming', () {
      final topUp = wizard.substring(wizard.indexOf('Future<bool> topUpAgentBf('));
      expect(topUp, contains('return setLoanDetails('),
          reason: 'CLAUDE.md is explicit: on a money path, read the number '
              'back. A grant that silently did nothing would let the wizard '
              'walk on to a photo it is about to waste');
    });
  });

  group('a requirement that is not met is not an error', () {
    test('a float refusal is no longer thrown', () {
      final ow005 =
          lib('features/owner_workspace/screens/ow_005_new_loan_workflow.dart');
      final confirm = ow005.substring(ow005.indexOf('Future<void> _confirm('));
      final body = confirm.substring(0, confirm.indexOf('@override'));
      expect(body, contains('if (ref.read(loanWizardProvider).blockedOnBf) return null;'),
          reason: 'throwing made NetworkErrorHandler print "Something went '
              'wrong. Please try again." over the card that was already '
              'explaining the shortfall');
      expect(body, contains('throw Exception('),
          reason: 'anything that is NOT a float refusal is still a failure '
              'and must still be reported');
    });

    test('the gate wears the warn tone, not the bad one', () {
      expect(gate, contains('ManaColors.statusWarnFaint'));
      expect(gate.contains('statusBad'), isFalse,
          reason: 'nothing here is wrong; the till is empty');
    });
  });

  group('a draft nobody can reach is a loan quietly deleted', () {
    test('the Owner home links to drafts', () {
      final home =
          lib('features/owner_workspace/screens/ow_001_owner_home_dashboard.dart');
      expect(home, contains("context.push('/ag-005'"),
          reason: 'the refusal promises "Saved as a draft. Nothing you '
              'entered is lost" and nothing on this side could open it');
      expect(home, contains('ManaSession.instance.lastAgentMembershipId != null'),
          reason: 'AG-005 is keyed by an agent membership; an Owner without '
              'one would get an empty screen that reads as a bug');
    });
  });
}

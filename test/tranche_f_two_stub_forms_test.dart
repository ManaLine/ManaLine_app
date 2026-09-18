import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// Two forms that asked a person for something no person has.
///
/// ITEM 15: "Add an Agent" opened a form headed "Minimum Information" whose
/// required village was a free-text box. auth-register validates
/// `address.village_id` and a six-digit `pin_code`; the method behind the
/// button sent neither, so every Save was a 400 -- and had been since it was
/// written.
///
/// ITEM 17: "Send BF Cash" asked for a "To Agent ID". That is an
/// agents.agent_id, a uuid. Nobody carries one and nothing in the app
/// displays one, so the form could not be completed at all. The controller
/// said so itself: "stub picker".
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  group('item 15 - registering a person who is not on file', () {
    final ow014 =
        lib('features/owner_workspace/screens/ow_014_global_workflow.dart');
    final service =
        lib('features/owner_workspace/state/global_workflow_state.dart');

    test('the free-text village box is gone', () {
      expect(ow014.contains("ref.t('minimum_information')"), isFalse,
          reason: 'the heading went with the form');
      expect(ow014.contains("ref.t('village_required_field')"), isFalse,
          reason: 'that key labelled the typed village box; a village is '
              'picked now, and a pick carries an id, a PIN, a mandal, a '
              'district and a state');
      expect(ow014, contains('ManaVillageSearchField'));
    });

    test('the register call sends what the Edge Function validates', () {
      // Checked against the function itself, not from memory: it is in this
      // repo and it is the thing that was rejecting every save.
      final fn = File('supabase/functions/auth-register/index.ts')
          .readAsStringSync();
      expect(fn, contains('address.village_id is required'),
          reason: 'if this requirement moved, the Dart below should move '
              'with it rather than drift back into a 400');

      final register = service
          .substring(service.indexOf('Future<String> registerPreExistingPerson('));
      final body = register.substring(0, register.indexOf('return result.personId;'));
      expect(body, contains("'village_id': villageId"));
      expect(body, contains("'pin_code': pinCode"));
      expect(body, contains('genderDigit: genderDigit'),
          reason: "it hardcoded '0' against a NOT NULL column, with its own "
              'FLAGGED note saying it had never collected one');
      expect(body.contains("'village': village"), isFalse,
          reason: 'the key the Edge Function ignores');
    });

    test('gender offers all three values, and the three the column allows', () {
      // gender_digit has had three since Others was added a month before this
      // form was touched; a picker offering two makes somebody choose wrong.
      //
      // THE DIGITS, NOT JUST THE COUNT. This test asked for 1 / 2 / 3, which
      // is what the form offered and what nothing else in the app uses:
      //
      //   persons_gender_digit_check: CHECK (gender_digit = ANY ('{0,1,2}'))
      //
      // So '3' was not merely inconsistent -- every Others registration
      // through this screen was rejected by the database, while a woman
      // registered here was stored as '2', Others, with the MLID minted from
      // that digit. Found from the profile screen, which is the first thing
      // that has to turn a stored digit back into a word.
      //
      // Counting the options was the right instinct and it passed on wrong
      // values, so the values are named here.
      final picker = ow014.substring(ow014.indexOf("ref.t('gender_field')"));
      final items = picker.substring(0, picker.indexOf('onChanged:'));
      expect(items, contains("value: '1'"), reason: 'Male');
      expect(items, contains("value: '0'"), reason: 'Female');
      expect(items, contains("value: '2'"), reason: 'Others');
      expect(items, isNot(contains("value: '3'")),
          reason: 'the CHECK constraint refuses it');
    });

    test('Save is pressable and names what is missing', () {
      // The same rule Add Customer settled on this pass: a disabled button at
      // a doorstep is indistinguishable from a broken one.
      final save = ow014.substring(ow014.indexOf('Future<void> _save() async {'));
      expect(save.substring(0, save.indexOf('final ok =')),
          contains('_whatIsMissing()'));
      expect(ow014, contains('onPressed: state.loading ? null : _save'),
          reason: 'only a request in flight may disable it');
    });

    test('an Agent or Investor must be reachable', () {
      // They are being granted reach into somebody else's book and accept
      // through respond_to_invitation. A person the app cannot reach cannot
      // accept -- unlike a migrated customer, for whom neither is optional
      // by design.
      final missing = ow014.substring(ow014.indexOf('String? _whatIsMissing()'));
      expect(missing.substring(0, missing.indexOf('Future<void> _save()')),
          contains('customer_needs_phone_or_aadhaar'));
    });
  });

  group('item 17 - sending cash to somebody who exists', () {
    final ag007 =
        lib('features/agent_workspace/screens/ag_007_loan_distribution.dart');
    final state =
        lib('features/agent_workspace/state/loan_distribution_state.dart');

    test('the typed Agent ID box is gone', () {
      expect(ag007.contains('_toAgentId'), isFalse,
          reason: 'an agents.agent_id is a uuid; nobody carries one');
      expect(ag007.contains("ref.t('to_agent_id_field')"), isFalse);
      // NOT a search for "stub picker": the phrase survives, in the doc
      // comment that records what was removed and why. What must not survive
      // is a second controller -- the form holds exactly one now, for the
      // amount, and the target is an object rather than typed text.
      final card = ag007.substring(ag007.indexOf('class _SendBfCashCardState'),
          ag007.indexOf('class _TransferList'));
      expect(RegExp(r'TextEditingController\(\)').allMatches(card).length, 1,
          reason: 'a second text controller on this form means somebody is '
              'being asked to type an identifier again');
    });

    test('the name is picked from a list, not typed', () {
      expect(ag007, contains('DropdownButtonFormField<ManaTransferTarget>'));
      expect(ag007, contains('_to!.agentId'),
          reason: 'the id now comes from the pick rather than from a box');
      expect(ag007, contains('isExpanded: true'),
          reason: 'a name plus a rupee figure is wider than a 360dp card, and '
              'an unbounded DropdownMenuItem is this project\'s recurring '
              'overflow');
    });

    test('the list RPC exists and has one overload', () {
      expect(manaAppFunctions, contains('transferable_agents'));
      expect(manaAppFunctionOverloads, isNot(contains('transferable_agents')));
      expect(state, contains("rpc('transferable_agents')"));
    });

    test('an empty list says so instead of offering a dead control', () {
      expect(ag007, contains("ref.t('no_other_agents_note')"),
          reason: 'a one-agent business has nobody to hand cash to, which is '
              'a fact about the book rather than a fault');
    });

    test('the migration mirrors initiate_cash_transfer, and says it does', () {
      // If the picker resolved the caller's business any other way it could
      // offer somebody the transfer would then refuse.
      final m = File(
              'supabase/migrations/20260917132223_an_agent_can_see_the_other_agents_they_may_transfer_to.sql')
          .readAsStringSync();
      expect(m, contains("bm.role = 'Agent'"));
      expect(m, contains("bm.membership_status = 'Active'"));
      expect(m, contains('a.agent_id <> v_from_agent_id'),
          reason: 'initiate_cash_transfer raises 23514 on self, so offering '
              'self would be offering a refusal');
      expect(m, contains('LIMIT 1 is arbitrary'),
          reason: 'the inherited two-business ambiguity is recorded rather '
              'than silently carried');
    });
  });
}

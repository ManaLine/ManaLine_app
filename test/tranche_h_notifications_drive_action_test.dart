import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/inbox_service.dart';

/// Item 18: a notification that told an Owner somebody was stuck, and offered
/// two ways to dismiss it.
///
/// "Karri Manikanta has asked for BF of 9800. They cannot issue loans until
/// it is granted." reached the bell, and then stopped: app.my_inbox_actions
/// had four kinds and this was not one of them, so the dialog's only buttons
/// were Ignore and Close. An agent at zero float cannot issue a single loan,
/// and the one person who could unblock them was reading a sentence with two
/// dismiss buttons.
///
/// Reported as "add a react before ignore ... app should drive user
/// accordingly." The answer is not a button bolted onto a notice: the inbox
/// already has the shape for "somebody is waiting on your decision", and this
/// is that.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  final migration = File(
          'supabase/migrations/20260917141421_a_bf_request_reaches_the_bell_as_something_to_do.sql')
      .readAsStringSync();

  group('the server offers it as a decision', () {
    test('my_inbox_actions has a bf_request branch', () {
      expect(migration, contains("SELECT 'bf_request'::text"));
      expect(migration, contains('FROM agent_bf_requests r'));
      expect(migration, contains("r.status = 'Pending'"));
      expect(migration, contains('app.is_owner(r.business_id)'),
          reason: 'the other four branches all filter on who is asking, and '
              'without it the REQUESTER would see their own request as '
              'something to approve');
    });

    test('the four older kinds are all still there', () {
      // CREATE OR REPLACE of a five-branch UNION is exactly where one branch
      // gets lost.
      for (final kind in const [
        'approval',
        'invitation',
        'settlement',
        'withdrawal',
      ]) {
        expect(migration, contains("SELECT '$kind'::text"),
            reason: '$kind disappeared from the inbox');
      }
    });

    test('it is CREATE OR REPLACE, and says why that is allowed', () {
      // CLAUDE.md's rule is about PARAMETER lists. This function takes none
      // and its RETURNS TABLE is unchanged, so replace is correct -- but the
      // reasoning has to be written down, because the next person changing
      // this file may be changing a parameter.
      expect(migration, contains('CREATE OR REPLACE FUNCTION app.my_inbox_actions()'));
      expect(migration, contains('takes NO parameters'));
      expect(migration, contains('has % overloads'),
          reason: 'asserted anyway');
    });
  });

  group('the app knows the kind', () {
    test('bfRequest exists and its wire name matches the SQL', () {
      expect(InboxActionKind.bfRequest.wire, 'bf_request');
      expect(InboxActionKind.fromWire('bf_request'), InboxActionKind.bfRequest);
    });

    test('an unknown kind still throws, which is why this had to ship together',
        () {
      // The enum's own doc: "a row the app cannot act on is a row somebody is
      // waiting behind, and swallowing it would leave them waiting silently."
      // That means the migration and the Dart are one change -- a server that
      // returns bf_request to an app that has not learned it does not degrade,
      // it stops the inbox loading.
      expect(() => InboxActionKind.fromWire('something_new'),
          throwsA(isA<ArgumentError>()));
      expect(migration, contains('ship together'),
          reason: 'the coupling is worth writing down where somebody '
              'deploying half of it would look');
    });

    test('the decision reaches the RPC that already granted float', () {
      final svc = lib('shared/inbox_service.dart');
      final m = svc.substring(svc.indexOf('Future<bool> decideBfRequest('));
      final body = m.substring(0, m.indexOf('return true;'));
      expect(body, contains("rpc('decide_agent_bf_request'"),
          reason: 'nothing new decides anything; this only makes the existing '
              'decision reachable');
      expect(body, contains('approve ? amount : null'),
          reason: 'a refusal carries no amount');
    });

    test('the notifier handles it rather than falling through', () {
      final state = lib('shared/inbox_state.dart');
      final decide = state.substring(state.indexOf('Future<bool> decide('));
      expect(decide.substring(0, decide.indexOf('} catch')),
          contains('case InboxActionKind.bfRequest:'));
      expect(state, contains('List<InboxAction> get bfRequests'));
    });
  });

  group('the card', () {
    final screen = lib('shared/notifications_screen.dart');

    test('it offers both answers, unlike settlement and withdrawal', () {
      final section = screen.substring(screen.indexOf('state.bfRequests.isNotEmpty'));
      final body = section.substring(0, section.indexOf('state.invitations'));
      expect(body, contains("yesLabel: ref.t('grant')"));
      expect(body, contains("noLabel: ref.t('decline')"),
          reason: 'refusing costs the Agent nothing they already had, so it '
              'needs no reason screen to be an honest answer -- which is why '
              'the two cards above it pass noLabel: null and this one does '
              'not');
    });

    test('grant, not approve', () {
      // Approving a settlement accepts money that has already moved. Granting
      // float MOVES money, out of the till into somebody's hand. Two acts
      // should not share a verb on one screen.
      expect(screen, contains("yesLabel: ref.t('grant')"));
    });

    test('the detail line carries the consequence, not just the figure', () {
      expect(screen, contains("ref\n          .t('asked_for_float_note')"),
          reason: 'an Owner reading "asked for Rs 9,800" has to work out for '
              'themselves what happens if they do nothing');
    });

    test('it sits above invitations, with the other money decisions', () {
      expect(screen.indexOf('state.bfRequests.isNotEmpty'),
          lessThan(screen.indexOf('state.invitations.isNotEmpty')),
          reason: 'an Agent waiting for float is standing in a village unable '
              'to lend, which is a harder stop than an invitation');
    });
  });
}

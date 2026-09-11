import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Add an Agent is not working."
///
/// It was never a control. It was a bold grey LABEL, and the list under it
/// was the agents still assignable to this round. With every agent already on
/// the round that list is empty -- and `agents.isEmpty` is FALSE, because
/// agents do exist -- so neither the rows nor the "no active agents" note
/// rendered. The words sat over a blank gap, which is exactly what a broken
/// button looks like.
///
/// Two errands were wearing one label: adding a NEW agent to the business,
/// and assigning an EXISTING one to this round. The sheet only ever offered
/// the second while being named for the first.
void main() {
  final source =
      File('lib/features/owner_workspace/screens/ow_012_business_management.dart')
          .readAsStringSync();
  final sheet = source.substring(source.indexOf('class _AssignAgentSheet'));

  group('Add an Agent is a control', () {
    test('it is tappable, not a label', () {
      final label = sheet.substring(sheet.indexOf("ref.t('add_an_agent')"));
      final upTo = label.substring(0, label.indexOf('Divider'));
      expect(upTo, contains('onTap:'),
          reason: 'add_an_agent has gone back to being text with no gesture, '
              'which is the defect this fixes');
    });

    test('it goes to the one way into the business', () {
      expect(sheet, contains("context.push('/ow-search'"),
          reason: 'adding a member of any kind goes through Universal Search');
    });

    test('the sheet closes before the search opens', () {
      // Pushing a screen over a modal sheet leaves the sheet underneath to
      // come back to, which is not where somebody who has just gone looking
      // for a new agent wants to land.
      final tap = sheet.substring(sheet.indexOf("ref.t('add_an_agent')"));
      final body = tap.substring(0, tap.indexOf("context.push('/ow-search'"));
      expect(body, contains('Navigator.of(context).pop()'),
          reason: 'the sheet must be dismissed before navigating');
    });
  });

  group('no empty region, in either empty case', () {
    test('both ways of having nothing to assign say something', () {
      // The bug was the SECOND of these. Agents exist, so the
      // no-active-agents note is skipped; every one is already assigned, so
      // the list is empty. Nothing rendered at all.
      expect(sheet, contains('every_agent_already_on_this_round_note'),
          reason: 'agents exist but all are on the round -- the case that '
              'rendered a blank gap');
      expect(sheet, contains('no_active_agents_note'),
          reason: 'the business has no agents at all');
    });

    test('the two errands are separately labelled', () {
      // A list headed "Add an Agent" whose rows assign existing people is how
      // one label came to mean two things.
      expect(sheet, contains('assign_to_this_round'),
          reason: 'the assignable list needs its own heading now that '
              'add_an_agent is a control rather than the list header');
    });

    test('the assignable list is still filtered', () {
      // uq_area_assignment_live rejects assigning the same agent twice, so
      // offering somebody already on the round is offering a guaranteed error.
      expect(sheet, contains('area.assignedAgents.any'),
          reason: 'somebody already on this round must not be offered again');
    });
  });
}

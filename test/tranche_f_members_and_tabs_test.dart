import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/business_management_state.dart';

/// Four changes to how the Owner finds people and moves between sections.
void main() {
  final ow012 = File(
          'lib/features/owner_workspace/screens/ow_012_business_management.dart')
      .readAsStringSync();
  final home = File(
          'lib/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart')
      .readAsStringSync();

  group('no + on Home', () {
    test('Home offers the magnifier and no add button', () {
      // The + means "add a member of THIS SCREEN's kind". Home has no kind, so
      // a + there would have to ask which role -- which is what the magnifier
      // beside it already does. Two buttons, one job.
      final actions = home.substring(
          home.indexOf('return ManaAppShell('), home.indexOf('sections: ['));
      expect(actions, isNot(contains('Icons.add')),
          reason: 'the + is back on Home, where it can only duplicate the '
              'magnifier');
      expect(actions, contains('Icons.search'),
          reason: 'the magnifier is the way in on Home');
    });

    test('the add-then-lend flow is not lost with it', () {
      // /customer-new still ends with "add them, or add them and go straight
      // to a loan", and the + on every customer screen still routes there.
      final actions =
          File('lib/shared/widgets/workspace_actions.dart').readAsStringSync();
      expect(actions, contains("ManaMemberKind.customer => '/customer-new'"));
    });
  });

  group('the tab order is the enum order', () {
    test('BusinessDetailTab reads members first', () {
      // ow_012 maps index to enum positionally in BOTH directions, so the
      // declaration order IS the tab order. Reordering the TabBar without
      // this would silently record the wrong tab.
      expect(BusinessDetailTab.values.map((t) => t.name).toList(), [
        'members',
        'operatingAreas',
        'accountPeriods',
        'agreements',
        'lendingRules',
      ]);
    });

    test('the drawn order matches it', () {
      final labels = RegExp(r"ref\.t\('(members|operating_areas|account_periods|agreements|lending_rules)'\)")
          .allMatches(ow012.substring(ow012.indexOf('PreferredSize(')))
          .take(5)
          .map((m) => m.group(1))
          .toList();
      expect(labels, [
        'members',
        'operating_areas',
        'account_periods',
        'agreements',
        'lending_rules',
      ], reason: 'the heading order has drifted from BusinessDetailTab, and '
          'the index mapping is positional');
    });

    test('one heading at a time, with a way to see there are more', () {
      // isScrollable put later tabs off the right edge with nothing saying
      // they existed.
      expect(ow012, isNot(contains('isScrollable: true')),
          reason: 'the scrolling label strip is back');
      // The heading moved out of this file and into a shared widget when the
      // one-by-one migration door needed the same control. Asserting on
      // ow012's own source would now pass for the wrong reason -- it would go
      // green if the header were deleted entirely -- so this checks the two
      // halves that actually matter: this screen still uses it, and it still
      // draws an arrow on each side.
      expect(ow012, contains('ManaTabHeading('));
      final heading =
          File('lib/shared/widgets/mana_tab_heading.dart').readAsStringSync();
      expect(heading, contains('Icons.chevron_left'));
      expect(heading, contains('Icons.chevron_right'));
    });

    test('the migration door uses the same heading, not a copy of it', () {
      // Two copies of a paging header is how two screens end up disagreeing
      // about what an arrow means. The door dropped a SegmentedButton for
      // this precisely because three segments could not hold
      // "Customers & Loans" on a real handset.
      final door = File(
              'lib/features/owner_workspace/screens/ow_one_by_one_migration.dart')
          .readAsStringSync();
      expect(door, contains('ManaTabHeading('));
      expect(door, isNot(contains('SegmentedButton<ManaEntryStage>')),
          reason: 'the segmented stage picker is back');
    });
  });

  group('reopening a migration says why', () {
    final ow018 = File(
            'lib/features/owner_workspace/screens/ow_018_business_migration.dart')
        .readAsStringSync();

    test('the reasons are a list, not a blank box', () {
      // The reason is the only record of why a locked migration was unlocked.
      // A blank box in a hurry produces "correction", which audits to nothing.
      expect(ow018, contains('_reopenReasonKeys'));
      expect(ow018, contains('DropdownButtonFormField<String>'));
    });

    test('Other keeps the typed box, and needs it filled', () {
      // A list that cannot say "none of these" pushes people into the nearest
      // wrong answer.
      expect(ow018, contains('reopen_reason_other'));
      final gate = ow018.substring(ow018.indexOf('onPressed: chosenKey == null'));
      expect(gate.substring(0, gate.indexOf('child:')),
          contains('controller.text.trim().isEmpty'),
          reason: 'Other must not submit with an empty reason');
    });

    test('the audit gets the sentence, not the key', () {
      // A log row reading 'reopen_reason_agent' tells a person nothing.
      expect(ow012.isNotEmpty, isTrue);
      expect(ow018, contains("ref.t(chosenKey!)"),
          reason: 'the English reason is what is recorded');
    });
  });

  group('members, sortable', () {
    test('village is carried on the member', () {
      expect(ow012, contains('member.village'));
    });

    test('it is fetched in a second query, not a two-level embed', () {
      // business_members -> persons -> person_addresses -> locations is two
      // levels deep, and the first level is already ambiguous: two FKs to
      // persons, so the existing embed has to name one or PostgREST answers
      // PGRST201 on every call. Two plain queries cannot be ambiguous.
      final state =
          File('lib/features/owner_workspace/state/business_management_state.dart')
              .readAsStringSync();
      expect(state, contains("from('person_addresses')"),
          reason: 'the village lookup has become a nested embed');
      expect(state, contains('locations!fk_person_addresses_village'),
          reason: 'the locations embed must name its FK');
    });

    test('both sorts are offered', () {
      expect(ow012, contains('sort_by_name'));
      expect(ow012, contains('sort_by_village'));
    });

    test('a member with no village sorts last, not first', () {
      // Burying the addressed majority under the unaddressed few would make
      // the sort useless for the round it exists for.
      final sorter = ow012.substring(ow012.indexOf('List<MemberSummary> _sorted('));
      expect(sorter.substring(0, sorter.indexOf('return list;')),
          contains('av.isEmpty ? 1 : -1'),
          reason: 'an empty village must sort last');
    });

    test('both entry points reach the members roster', () {
      expect(home, contains("'/ow-012?tab=members'"),
          reason: 'the drawer entry is gone');
      expect(home, contains("'tab=members'"),
          reason: 'the quick action is gone');
    });
  });
}

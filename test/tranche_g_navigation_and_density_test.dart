import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Four findings about getting to things, and about how much screen the
/// getting costs.
///
/// ASSERT ON CODE, NOT ON PROSE. Three assertions here were first written to
/// search for a word -- `roleLetters`, `PageView` -- and each one then found
/// it in the COMMENT recording that the thing had been removed. The same
/// mistake cost a cycle in the tranche before this one, hunting "stub
/// picker". A source-text guard has to look for a declaration or a call,
/// because the explanation of a deletion necessarily names what was deleted.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  final ow001 =
      lib('features/owner_workspace/screens/ow_001_owner_home_dashboard.dart');
  final ow012 =
      lib('features/owner_workspace/screens/ow_012_business_management.dart');

  group('item 4 - a drawer row that opened a list of itself', () {
    test('Members is a destination, not a group of one', () {
      final members = ow001.substring(ow001.indexOf("labelKey: 'members',"));
      final section = members.substring(0, members.indexOf('),\n'));
      expect(section, contains('onTap:'),
          reason: 'ManaDrawerSection.onTap exists for exactly this and says '
              'so: "giving it a chevron that opens a list containing only '
              'itself would be two taps to do one thing"');
      expect(section.contains('actions:'), isFalse);
    });

    test('no section anywhere is one action wearing its own name', () {
      // The general shape, so this cannot come back on a different row. A
      // section whose single action repeats its label is a group of one.
      final sections = RegExp(
              r"ManaDrawerSection\(\s*icon:[^)]*?labelKey: '(\w+)',\s*actions: \[\s*ManaDrawerAction\(\s*labelKey: '(\w+)'",
              dotAll: true)
          .allMatches(ow001);
      final offenders = [
        for (final m in sections)
          if (m.group(1) == m.group(2)) m.group(1)!,
      ];
      expect(offenders, isEmpty,
          reason: 'these open a list whose only entry is themselves: '
              '${offenders.join(', ')}');
    });
  });

  group('item 1a - the members tab', () {
    test('Add a User moved to the header', () {
      final actions = ow012.substring(
          ow012.indexOf("tooltip: ref.t('add_a_user')"),
          ow012.indexOf("tooltip: ref.t('pre_existing_business')"));
      expect(actions, contains("context.push('/ow-search'"));
      // And it is FIRST, before the pre-existing-business icon, as asked.
      expect(ow012.indexOf("tooltip: ref.t('add_a_user')"),
          lessThan(ow012.indexOf("tooltip: ref.t('pre_existing_business')")));
    });

    test('the body carries a role filter where the button was', () {
      expect(ow012, contains('String? _roleFilter;'));
      expect(ow012, contains("_roleFilter == null || m.role == _roleFilter"),
          reason: 'a filter that does not narrow anything is a decoration');
    });

    test('All is still offered, and is the default', () {
      // The Owner named three options. Without a fourth the screen would lose
      // the only thing it could do before -- show the whole book at once --
      // and an Owner counting heads against a page counts everybody.
      expect(ow012, contains("DropdownMenuItem(\n                      value: null"),
          reason: 'no All option');
      final field = ow012.substring(ow012.indexOf('String? _roleFilter;'));
      expect(field.substring(0, field.indexOf('\n')), isNot(contains('=')),
          reason: '_roleFilter must start null, which is All');
    });

    test('the C / A / I letters are gone, and so is the getter', () {
      expect(ow012.contains('String get roleLetters'), isFalse,
          reason: 'the letters left the rows one build after arriving, '
              'because the role moved into a filter that says the same thing '
              'in words -- and the getter had exactly one reader, this. '
              'Keeping a getter nothing calls because it was written '
              'yesterday is how dead code gets a sentimental defence');
    });
  });

  group('item 14 - six counts over a book of three people', () {
    test('the workforce summary strip is gone', () {
      final ow002 =
          lib('features/owner_workspace/screens/ow_002_workforce_management.dart');
      expect(ow002.contains('_DashboardStrip'), isFalse,
          reason: 'the widget went with its usage, not just the call');
      expect(ow002.contains('ManaStatStrip'), isFalse);
      // The capability it claimed is still there, and better: the filter
      // below narrows by status and every row carries its own.
      expect(ow002, contains('onStatusChanged:'));
    });
  });

  group('item 16 - the quick actions', () {
    test('a horizontal drag switches group', () {
      expect(ow001, contains('onHorizontalDragEnd:'));
      expect(ow001, contains('AnimatedSwitcher'));
      expect(ow001, contains('key: ValueKey(index)'),
          reason: 'without a key AnimatedSwitcher sees one _QuickActionGroup '
              'and rebuilds it in place with no transition at all');
    });

    test('it is a drag and NOT a PageView', () {
      // A PageView needs a bounded height, and these groups do not share one
      // -- Customers has four actions, Investors six. Worse, ManaActionGrid
      // picks its own column count by device, so any height computed here
      // would be a second copy of that rule, wrong on a tablet and wrong
      // again at 2.0x. The first draft did exactly that.
      expect(ow001.contains('PageView('), isFalse,
          reason: 'a bounded height here is a duplicate of ManaActionGrid\'s '
              'own column logic');
    });

    test('the chips stay, because a swipe needs something to say it exists',
        () {
      expect(ow001, contains('ChoiceChip'));
    });

    test('the drag clamps rather than wrapping', () {
      final drag = ow001.substring(ow001.indexOf('onHorizontalDragEnd:'));
      expect(drag.substring(0, drag.indexOf('child:')),
          contains('.clamp(0, groups.length - 1)'),
          reason: 'somebody swiping past the end of three should find the '
              'end, not the beginning');
    });

    test('Workforce is called Agents', () {
      expect(ow001.contains("ref.t('workforce')"), isFalse);
      expect(ow001.contains("labelKey: 'workforce'"), isFalse);
      // The screen TITLE moved too, by changing the string rather than the
      // key: a key is not user-visible, and renaming it would mean editing
      // every call site and every migration that inserted it to change
      // nothing anybody reads.
      final m = File(
              'supabase/migrations/20260917135625_the_word_workforce_becomes_agents.sql')
          .readAsStringSync();
      expect(m, contains("SET english = 'Agent Management'"));
      expect(m, contains("WHERE translation_key = 'workforce_management'"));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the mistake that has broken production three times in three days.
///
/// PostgREST refuses an embed it cannot resolve to ONE foreign key, answering
/// HTTP 300 (PGRST201). It is invisible to `flutter analyze`, invisible to
/// every widget test, and only fails against the real database — so it ships,
/// and the screen says "couldn't load" with the reason discarded.
///
/// What it cost: the Owner dashboard would not load at all, and the bulk
/// customer import failed after the Owner had already picked their file.
///
/// The pairs below are every (child, parent) in this schema with more than one
/// foreign key between them. Regenerate with:
///
///   select c.conrelid::regclass, c.confrelid::regclass, count(*)
///     from pg_constraint c
///    where c.contype='f' and c.connamespace='public'::regnamespace
///    group by 1,2 having count(*) > 1;
///
/// CLAUDE.md lists three of these from memory; the database says eleven.
const _ambiguous = <List<String>>[
  ['agent_access_days', 'business_members'],
  ['agent_bf_grants', 'business_members'],
  ['business_members', 'persons'],
  ['business_transfers', 'persons'],
  ['cash_transfers', 'agents'],
  ['cheti_payments', 'business_members'],
  ['collections', 'business_members'],
  ['duplicate_suspects', 'persons'],
  ['expenses', 'business_members'],
  ['loans', 'business_members'],
  ['membership_requests', 'persons'],
];

/// `!inner` and `!left` are join MODIFIERS, not foreign-key names — writing
/// `persons!inner(...)` under `business_members` is still ambiguous. That
/// exact confusion is what broke the customer import.
const _modifiers = {'inner', 'left', ''};

/// One embed found in a select: who it hangs off, what it pulls in, and
/// whatever followed the `!`.
class _Embed {
  final String parent;
  final String child;
  final String qualifier;
  _Embed(this.parent, this.child, this.qualifier);

  bool get namesForeignKey =>
      qualifier.split('!').any((q) => !_modifiers.contains(q));
}

/// Walks a PostgREST select body, tracking which embed each one is nested in.
/// Co-occurrence is not enough: `persons!inner(...)` is perfectly fine hanging
/// off `customers`, which has one FK to persons, and only wrong under
/// `business_members`, which has two.
List<_Embed> _embedsOf(String body, String root) {
  final found = <_Embed>[];
  final stack = <String>[root];
  var token = StringBuffer();

  for (final ch in body.split('')) {
    switch (ch) {
      case '(':
        var name = token.toString().split(',').last.trim();
        var qualifier = '';
        if (name.contains('!')) {
          final bits = name.split('!');
          name = bits.first;
          qualifier = bits.skip(1).join('!');
        }
        if (name.isNotEmpty) {
          found.add(_Embed(stack.last, name, qualifier));
          stack.add(name);
        } else {
          stack.add(stack.last);
        }
        token = StringBuffer();
      case ')':
        if (stack.length > 1) stack.removeLast();
        token = StringBuffer();
      case ',':
        token = StringBuffer();
      default:
        token.write(ch);
    }
  }
  return found;
}

final _selectPattern = RegExp(
  r"""\.from\(\s*'([a-z_]+)'\s*\)\s*\.select\(\s*('''|')(.*?)\2\s*\)""",
  dotAll: true,
);

void main() {
  test('the guard itself catches a known-bad embed', () {
    // A scanner that finds nothing proves nothing unless it can catch the
    // real failure. This is verbatim what broke the customer import.
    final bad = _embedsOf(
        'customer_id, business_members!inner(business_id, persons!inner(mlid))',
        'customers');
    final flagged = bad.where((e) =>
        e.parent == 'business_members' &&
        e.child == 'persons' &&
        !e.namesForeignKey);
    expect(flagged, isNotEmpty);

    // And that it does NOT flag the same table pulled through a parent that
    // has only one foreign key to it.
    final good = _embedsOf(
        'customer_id, business_members!customers_membership_id_fkey!inner(business_id), '
        'persons!inner(full_name)',
        'customers');
    expect(good.where((e) => !e.namesForeignKey && e.parent == 'business_members'),
        isEmpty);
  });

  test('no query in lib/ embeds an ambiguous relationship unqualified', () {
    final pairs = {for (final p in _ambiguous) '${p[0]}|${p[1]}'};
    final violations = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in _selectPattern.allMatches(source)) {
        final root = match.group(1)!;
        // Adjacent Dart string literals concatenate; join them first.
        final body = match.group(3)!.replaceAll(RegExp(r"'\s*'"), '');

        for (final embed in _embedsOf(body, root)) {
          final ambiguous = pairs.contains('${embed.parent}|${embed.child}') ||
              pairs.contains('${embed.child}|${embed.parent}');
          if (!ambiguous || embed.namesForeignKey) continue;

          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('${file.path}:$line  '
              '${embed.parent} -> ${embed.child} needs its foreign key named');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'PostgREST answers 300 for these and the screen just says it '
            'could not load:\n${violations.join('\n')}');
  });
}

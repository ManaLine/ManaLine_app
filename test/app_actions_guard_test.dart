import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/app_actions.dart';

import 'support/mana_translations_fixture.dart';

/// Every option the search offers goes somewhere, and is called something.
///
/// The catalogue in `app_actions.dart` is written by hand, on purpose -- 88
/// routes is not a useful search and most of them cannot be opened cold. The
/// cost of writing it by hand is that it can drift from the router in two
/// silent ways, and both end at the same place: an Owner types three letters,
/// taps the answer, and lands on a blank screen or a raw translation key.
///
///   a route is renamed          the tile navigates to nothing
///   a label key is a typo       the tile is titled `add_a_custmer`
///
/// Neither is visible to `flutter analyze` -- both are strings.
void main() {
  final routerSource = File('lib/app/router.dart').readAsStringSync();

  /// Every path the handset router declares, read from the file rather than
  /// from a list kept here, so a rename is caught instead of mirrored.
  final declared = RegExp(r"path: '(/[a-z0-9-]+)'")
      .allMatches(routerSource)
      .map((m) => m.group(1)!)
      .toSet();

  test('the route scan found the router, not an empty file', () {
    // A guard that quietly checks nothing reads exactly like one that passes.
    // If the regex stops matching -- the file reformats, the quotes change --
    // every assertion below succeeds against an empty set.
    expect(declared.length, greaterThan(50),
        reason: 'expected the router to declare dozens of paths, found '
            '${declared.length}. The scan is broken, not the routes.');
    expect(declared, contains('/ow-004'));
  });

  test('every action goes to a route the router declares', () {
    final missing = [
      for (final a in manaOwnerActions)
        if (!declared.contains(a.route)) '${a.labelKey} -> ${a.route}',
    ];
    expect(missing, isEmpty,
        reason: 'These actions point at routes that do not exist:\n  '
            '${missing.join('\n  ')}');
  });

  test('every action has a label that exists', () {
    // Against the vendored table rather than the database, so this passes
    // offline -- the same reason the layout tests carry it.
    final missing = [
      for (final a in manaOwnerActions)
        if (!manaTranslationsFixture.containsKey(a.labelKey)) a.labelKey,
    ];
    expect(missing, isEmpty,
        reason: 'These action labels have no translation row, so the tile '
            'would be titled with the key itself:\n  ${missing.join('\n  ')}');
  });

  test('a query shorter than three characters matches nothing', () {
    // The Owner's number. At two letters nearly everything matches and a list
    // of twenty-five is not an answer to a question.
    for (final q in ['', 'a', 'ad', '  ', ' a ']) {
      expect(manaSearchActions(q, (k) => k), isEmpty, reason: 'query "$q"');
    }
    expect(manaActionSearchMinimum, 3);
  });

  test('three characters find the thing they name', () {
    String label(String k) => manaTranslationsFixture[k]?['English'] ?? k;

    // The two the Owner named.
    expect(manaSearchActions('add', label).map((a) => a.labelKey),
        contains('add_a_customer'));
    expect(manaSearchActions('age', label).map((a) => a.labelKey),
        contains('add_an_agent'));
  });

  test('a word people actually use finds it, not just the screen title', () {
    String label(String k) => manaTranslationsFixture[k]?['English'] ?? k;

    // Nothing in this app is titled "vasool", and it is what an agent calls
    // the round. The keyword list is the whole reason this works.
    expect(manaSearchActions('vasool', label).map((a) => a.labelKey),
        contains('collection_mode'));
    // "Cheeti" is spelled two ways in this codebase and both must find it.
    expect(manaSearchActions('chet', label).map((a) => a.labelKey),
        contains('cheti'));
    expect(manaSearchActions('chee', label).map((a) => a.labelKey),
        contains('cheti'));
  });

  test('Telugu words find their action while the app is in English', () {
    // A person who thinks in Telugu types Telugu regardless of which language
    // the app is set to, and the label they would be matched against is the
    // English one.
    String english(String k) => manaTranslationsFixture[k]?['English'] ?? k;
    expect(manaSearchActions('వసూలు', english).map((a) => a.labelKey),
        contains('collection_mode'));
    expect(manaSearchActions('రుణం', english).map((a) => a.labelKey),
        contains('new_loan'));
  });

  test('a label match outranks a keyword match', () {
    String label(String k) => manaTranslationsFixture[k]?['English'] ?? k;
    // "Agents" is the title of /ow-002; "agent" is only a keyword on Add an
    // Agent. Typing the word that IS a title should land on that screen.
    final hits = manaSearchActions('agents', label);
    expect(hits.first.labelKey, 'agents');
  });

  test('no two actions share a label and a destination', () {
    // Two tiles reading the same thing is a search that looks broken.
    final seen = <String>{};
    final dupes = <String>[];
    for (final a in manaOwnerActions) {
      if (!seen.add('${a.labelKey}|${a.path}')) dupes.add(a.labelKey);
    }
    expect(dupes, isEmpty);
  });

  test('a query nobody could mean finds nothing rather than everything', () {
    String label(String k) => manaTranslationsFixture[k]?['English'] ?? k;
    expect(manaSearchActions('zzzqqq', label), isEmpty);
  });
}

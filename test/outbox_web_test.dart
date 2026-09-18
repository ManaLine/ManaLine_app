import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/outbox/mana_outbox_sqflite_store.dart';

/// The outbox must be silent where it cannot run.
///
/// THE BUG. `manaOpenOutbox` declines on the web on purpose — sqflite has no
/// web implementation — but `ManaOutboxWatcher` was mounted by main.dart's
/// builder on BOTH builds, above every screen. Its startup flush and then its
/// sixty-second timer each reached a store that had never been opened:
///
///     Bad state: The outbox database is not open. Call open() first.
///
/// `unawaited` with no catch made that an uncaught error at the top of the
/// zone, so it landed in the browser console on every single load of the
/// deployed site — and again once a minute for as long as a tab stayed open.
/// Nothing renders from a flush, so nothing looked broken and it read as
/// noise for days.
///
/// Two independent faults, so two independent fixes and two sets of tests:
/// the watcher should not run where the outbox cannot, AND a closed outbox
/// should not throw at a reader.
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('a closed store is empty, not broken', () {
    test('all() returns nothing rather than throwing', () async {
      // "Closed" is a NORMAL state: the web declines to open, and a handset
      // that fails to open swallows it rather than refusing to start. A
      // reader that treats either as an exception turns a designed fallback
      // into a crash.
      final store = ManaOutboxSqfliteStore();
      expect(store.isOpen, isFalse);
      expect(await store.all(), isEmpty);
    });
  });

  group('the watcher does not run where the outbox cannot', () {
    final watcher = _code('lib/shared/outbox/mana_outbox_watcher.dart');

    test('it returns early on the web', () {
      expect(watcher, contains('kIsWeb'),
          reason: 'the web build has no collection screen to queue anything, '
              'so there is nothing to drain — and no reason to wake a '
              'browser tab every sixty seconds forever');
    });

    test('and its background work is caught, not left to the zone', () {
      // unawaited() on a Future that rejects IS the uncaught error. Background
      // work failing quietly is the intent; failing loudly in somebody's
      // console is not.
      expect(watcher, contains('catchError'));
      expect(watcher, contains('manaReportError'),
          reason: 'swallowed silently would be the other way to get this '
              'wrong — a queue that stops draining must still be reportable');
    });
  });

  group('the open path still declines deliberately', () {
    test('manaOpenOutbox returns false on the web rather than throwing', () {
      // This half was always right, and is the reason the watcher was the
      // thing to change. Pinned so a later "fix" does not make opening throw.
      final provider = _code('lib/shared/outbox/mana_outbox_provider.dart');
      expect(provider, contains('if (kIsWeb) return false;'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/outbox/mana_outbox.dart';
import 'package:mana_line/shared/outbox/mana_outbox_sqflite_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The queue survives the app being closed.
///
/// This is the whole reason the outbox is on disk rather than in memory. An
/// agent records four collections in a village with no signal, the phone runs
/// out of battery or Android kills the app to reclaim memory, and those four
/// must still be there. An in-memory queue would lose them silently, which is
/// the one outcome this feature exists to prevent.
///
/// RUN AGAINST REAL SQLITE, via the FFI build, rather than against a fake.
/// The adapter's whole job is the schema and the round trip, and a fake would
/// test neither. This also runs on CI, where there is no handset.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ManaOutboxSqfliteStore store;

  setUp(() async {
    // inMemoryDatabasePath is still real SQLite -- same engine, same SQL, same
    // type affinities. Only the file is absent.
    store = ManaOutboxSqfliteStore();
    await store.open(path: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  ManaOutboxEntry anEntry({int amount = 5000, String name = 'Karri Priyanka'}) =>
      ManaOutboxEntry.create(
        businessId: 'b1',
        loanId: 'l1',
        customerId: 'c1',
        customerName: name,
        collectedAmount: amount,
        businessDate: '2026-09-15',
        payload: {
          'p_collected_amount': amount,
          'p_splits': [
            {'kind': 'Cash', 'amount': amount}
          ],
        },
      );

  test('an entry written is an entry read back, field for field', () async {
    final original = anEntry().markSending().markQueuedAgain('no connection');
    await store.put(original);

    final back = (await store.all()).single;
    expect(back.id, original.id);
    expect(back.idempotencyKey, original.idempotencyKey);
    expect(back.state, ManaOutboxState.queued);
    expect(back.attempts, 1);
    expect(back.collectedAmount, 5000);
    expect(back.customerName, 'Karri Priyanka');
    expect(back.businessDate, '2026-09-15');
    expect(back.lastError, 'no connection');
    expect(back.createdAt, original.createdAt);
  });

  test('the payload survives, nested lists and all', () async {
    // The payload is what actually reaches app.record_collection. A split
    // silently flattened on the way to disk is a collection recorded as the
    // wrong kind of money.
    await store.put(anEntry(amount: 700));
    final back = (await store.all()).single;

    expect(back.payload['p_collected_amount'], 700);
    expect(back.payload['p_splits'], isA<List<dynamic>>());
    expect((back.payload['p_splits'] as List).single, {
      'kind': 'Cash',
      'amount': 700,
    });
  });

  test('putting the same id twice updates rather than duplicating', () async {
    // The sender writes an entry three times in one pass: sending, then the
    // outcome. Three rows for one collection would show the agent a queue of
    // phantoms.
    final e = anEntry();
    await store.put(e);
    await store.put(e.markSending());
    await store.put(e.markRefused('Loan not found'));

    final all = await store.all();
    expect(all, hasLength(1));
    expect(all.single.state, ManaOutboxState.refused);
    expect(all.single.lastError, 'Loan not found');
  });

  test('removing takes exactly one entry', () async {
    final a = anEntry(name: 'first');
    final b = anEntry(name: 'second');
    await store.put(a);
    await store.put(b);

    await store.remove(a.id);

    final all = await store.all();
    expect(all, hasLength(1));
    expect(all.single.customerName, 'second');
  });

  test('entries come back oldest first', () async {
    // The order an agent recorded them in is the order they should be sent
    // and the order the queue should read. A village round is chronological.
    final first = anEntry(name: 'first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = anEntry(name: 'second');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final third = anEntry(name: 'third');

    // Deliberately inserted out of order.
    await store.put(third);
    await store.put(first);
    await store.put(second);

    expect((await store.all()).map((e) => e.customerName).toList(),
        ['first', 'second', 'third']);
  });

  test('a closed and reopened database still has the queue', () async {
    // The actual scenario: the app is killed with collections waiting.
    // in-memory sqflite cannot survive a close, so this uses a real file.
    final dir = await databaseFactory.getDatabasesPath();
    final path = '$dir/outbox_reopen_test.db';
    await databaseFactory.deleteDatabase(path);

    final first = ManaOutboxSqfliteStore();
    await first.open(path: path);
    await first.put(anEntry(name: 'survivor'));
    await first.close();

    final second = ManaOutboxSqfliteStore();
    await second.open(path: path);
    final all = await second.all();
    await second.close();
    await databaseFactory.deleteDatabase(path);

    expect(all, hasLength(1));
    expect(all.single.customerName, 'survivor');
  });

  test('the whole outbox works against real storage', () async {
    // The pieces are tested apart; this is the one place they run together.
    var sent = 0;
    final outbox = ManaOutbox(
      store: store,
      send: (_) async {
        sent++;
        return 'collection-1';
      },
    );

    await outbox.enqueue(anEntry(name: 'one'));
    await outbox.enqueue(anEntry(name: 'two'));
    expect(await outbox.pending(), hasLength(2));

    await outbox.flush();

    expect(sent, 2);
    expect(await outbox.pending(), isEmpty);
    expect(await store.all(), isEmpty);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/outbox/mana_outbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Walking the queue, and what each outcome does to an entry.
///
/// The store is in-memory here and the sender is a closure. Both are injected
/// for the same reason: the decisions this class makes are about money, and
/// they should be testable without a database or a signal.
class _MemoryStore implements ManaOutboxStore {
  final List<ManaOutboxEntry> rows = [];

  @override
  Future<List<ManaOutboxEntry>> all() async => List.of(rows);

  @override
  Future<void> put(ManaOutboxEntry e) async {
    final i = rows.indexWhere((r) => r.id == e.id);
    if (i >= 0) {
      rows[i] = e;
    } else {
      rows.add(e);
    }
  }

  @override
  Future<void> remove(String id) async => rows.removeWhere((r) => r.id == id);
}

ManaOutboxEntry anEntry({int amount = 5000, String name = 'Karri Priyanka'}) =>
    ManaOutboxEntry.create(
      businessId: 'b1',
      loanId: 'l1',
      customerId: 'c1',
      customerName: name,
      collectedAmount: amount,
      businessDate: '2026-09-15',
      payload: {'p_collected_amount': amount},
    );

void main() {
  late _MemoryStore store;
  setUp(() => store = _MemoryStore());

  test('a successful send leaves nothing behind in the queue', () {
    // ONCE IT IS ON THE SERVER, THE SERVER IS THE RECORD. Keeping a "sent"
    // row would make the outbox a second ledger that has to be kept in step
    // with `collections`, and two records of one payment is how they
    // disagree. The collection appears in the round list, which is what
    // "arrived" means.
    final outbox = ManaOutbox(
      store: store,
      send: (_) async => 'collection-1',
    );

    return outbox.enqueue(anEntry()).then((_) async {
      expect(store.rows, hasLength(1));
      await outbox.flush();
      expect(store.rows, isEmpty);
    });
  });

  test('a refusal stays, carrying the server\'s sentence, and is not retried',
      () async {
    var attempts = 0;
    final outbox = ManaOutbox(
      store: store,
      send: (_) async {
        attempts++;
        throw const PostgrestException(
            message: 'That receipt is from a different collection window',
            code: '23514');
      },
    );

    await outbox.enqueue(anEntry());
    await outbox.flush();
    await outbox.flush();

    expect(attempts, 1,
        reason: 'a refusal is a fact about the world; retrying reproduces it '
            'at a time nobody is watching');
    expect(store.rows.single.state, ManaOutboxState.refused);
    expect(store.rows.single.lastError,
        'That receipt is from a different collection window');
  });

  test('a dropped connection goes back in the queue and IS retried', () async {
    var attempts = 0;
    final outbox = ManaOutbox(
      store: store,
      send: (_) async {
        attempts++;
        throw TimeoutException('no answer');
      },
    );

    await outbox.enqueue(anEntry());
    await outbox.flush();
    await outbox.flush();

    expect(attempts, 2);
    expect(store.rows.single.state, ManaOutboxState.queued);
    expect(store.rows.single.attempts, 2);
  });

  test('the same key is used on every retry of one entry', () async {
    // The whole reason a retry is safe. A fresh key per attempt would record
    // a second collection every time the connection wobbled.
    final keys = <String>[];
    final outbox = ManaOutbox(
      store: store,
      send: (e) async {
        keys.add(e.idempotencyKey);
        throw TimeoutException('no answer');
      },
    );

    await outbox.enqueue(anEntry());
    await outbox.flush();
    await outbox.flush();
    await outbox.flush();

    expect(keys.toSet(), hasLength(1));
  });

  test('one bad entry does not block the ones behind it', () async {
    // A refusal on the second of five must not strand the other four. An
    // agent who collected from a village should not lose nineteen because the
    // twentieth was wrong.
    final outbox = ManaOutbox(
      store: store,
      send: (e) async {
        if (e.customerName == 'bad') {
          throw const PostgrestException(message: 'Loan not found', code: 'P0002');
        }
        return 'ok';
      },
    );

    await outbox.enqueue(anEntry(name: 'first'));
    await outbox.enqueue(anEntry(name: 'bad'));
    await outbox.enqueue(anEntry(name: 'third'));
    await outbox.flush();

    expect(store.rows, hasLength(1));
    expect(store.rows.single.customerName, 'bad');
    expect(store.rows.single.state, ManaOutboxState.refused);
  });

  test('two flushes at once do not send the same entry twice', () async {
    // Idempotency would cover it, but a second in-flight copy of the same
    // write is a round trip spent to be told what the first one already knew.
    var sends = 0;
    final gate = Completer<void>();
    final outbox = ManaOutbox(
      store: store,
      send: (_) async {
        sends++;
        await gate.future;
        return 'ok';
      },
    );

    await outbox.enqueue(anEntry());
    final a = outbox.flush();
    final b = outbox.flush();
    gate.complete();
    await Future.wait([a, b]);

    expect(sends, 1);
  });

  group('what the agent can change', () {
    test('a queued entry can be edited, and the edit gets a new key',
        () async {
      final outbox = ManaOutbox(store: store, send: (_) async => 'ok');
      final original = anEntry(amount: 5000);
      await outbox.enqueue(original);

      await outbox.edit(original.id,
          collectedAmount: 4500, payload: {'p_collected_amount': 4500});

      expect(store.rows, hasLength(1), reason: 'the old entry is replaced');
      expect(store.rows.single.collectedAmount, 4500);
      expect(store.rows.single.idempotencyKey, isNot(original.idempotencyKey));
    });

    test('a queued entry can be deleted', () async {
      final outbox = ManaOutbox(store: store, send: (_) async => 'ok');
      final e = anEntry();
      await outbox.enqueue(e);
      await outbox.remove(e.id);
      expect(store.rows, isEmpty);
    });

    test('an entry mid-flight refuses to be edited', () async {
      // The window where "never arrived" and "arrived, reply lost" cannot be
      // told apart. Editing here could send a changed amount under a key the
      // server has already answered.
      final gate = Completer<void>();
      final outbox = ManaOutbox(
        store: store,
        send: (_) async {
          await gate.future;
          return 'ok';
        },
      );
      final e = anEntry();
      await outbox.enqueue(e);
      final flushing = outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(
        () => outbox.edit(e.id,
            collectedAmount: 1, payload: {'p_collected_amount': 1}),
        throwsA(isA<StateError>()),
      );

      gate.complete();
      await flushing;
    });
  });
}

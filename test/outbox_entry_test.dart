import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/outbox/mana_outbox_entry.dart';

/// The outbox: a collection recorded with no signal, queued until there is one.
///
/// THE SHAPE THE OWNER ASKED FOR: "offline doesn't mean complete no signal for
/// hours, just a few minutes or less. What I want is just queue it until live,
/// like WhatsApp messages. Meanwhile user can delete, rewrite those queued
/// entries."
///
/// So this is an OUTBOX, not an offline mode. The whole design is in
/// docs/decisions/2026-09-15-offline.md. What is tested here is the state
/// machine and the one rule that can destroy money.
ManaOutboxEntry anEntry({
  ManaOutboxState state = ManaOutboxState.queued,
  int amount = 5000,
}) =>
    ManaOutboxEntry.create(
      businessId: 'b1',
      loanId: 'l1',
      customerId: 'c1',
      customerName: 'Karri Priyanka',
      collectedAmount: amount,
      businessDate: '2026-09-15',
      payload: {'p_collected_amount': amount},
    ).copyWith(state: state);

void main() {
  group('the rule that protects the money', () {
    test('an edited entry gets a NEW idempotency key', () {
      // THE TRAP THIS EXISTS FOR, and the only genuinely hard part of the
      // outbox.
      //
      // idempotency_keys stores the RESPONSE, not just the key. That is what
      // makes a retry safe: replaying returns the original answer instead of
      // writing twice. It is also what makes an EDIT dangerous. If an entry
      // was already sent and only the reply was lost, re-sending an edited
      // amount under the SAME key returns the ORIGINAL response. The server
      // reports success, the app shows success, and the edit never happened.
      //
      // A 500 correction to a 5,000 entry, ticked on screen, never written --
      // which is exactly the "confidently wrong number on a collection screen"
      // CLAUDE.md calls worse than a crash.
      final original = anEntry(amount: 5000);
      final edited = original.editedTo(
        collectedAmount: 4500,
        payload: {'p_collected_amount': 4500},
      );

      expect(edited.idempotencyKey, isNot(original.idempotencyKey),
          reason: 'an edit re-sent under the old key replays the old answer');
      expect(edited.collectedAmount, 4500);
      expect(original.collectedAmount, 5000,
          reason: 'editing must not mutate the entry already queued');
    });

    test('a plain retry keeps the SAME key', () {
      // The mirror of the rule above. A retry of an unchanged entry must
      // replay, not write a second collection.
      final entry = anEntry();
      final retried = entry.markSending().markQueuedAgain('no connection');

      expect(retried.idempotencyKey, entry.idempotencyKey,
          reason: 'a fresh key on every retry is the same as having none');
      expect(retried.attempts, 1);
    });
  });

  group('what the agent may do, and when', () {
    test('a queued entry can be edited and deleted', () {
      // Nothing has left the phone. It is a local draft.
      final e = anEntry(state: ManaOutboxState.queued);
      expect(e.canEdit, isTrue);
      expect(e.canDelete, isTrue);
    });

    test('a SENDING entry can be neither', () {
      // Not tidiness. In this window nobody can tell "never arrived" from
      // "arrived, reply lost", and those two need opposite handling: one wants
      // a retry under the same key, the other must not be written at all.
      final e = anEntry(state: ManaOutboxState.sending);
      expect(e.canEdit, isFalse);
      expect(e.canDelete, isFalse);
    });

    test('a SENT entry is out of the outbox\'s hands', () {
      // It exists on the server now. app.amend_collection and the
      // correct-until-handed-over rule govern it, not this queue.
      final e = anEntry(state: ManaOutboxState.sent);
      expect(e.canEdit, isFalse);
      expect(e.canDelete, isFalse);
    });

    test('a REFUSED entry can be edited or discarded', () {
      // The server said no and said why. At minute-scale the agent is usually
      // still standing in front of the customer.
      final e = anEntry(state: ManaOutboxState.refused);
      expect(e.canEdit, isTrue);
      expect(e.canDelete, isTrue);
    });

    test('editing a refused entry re-queues it with a new key', () {
      final refused = anEntry(state: ManaOutboxState.refused)
          .markRefused('That receipt is from a different collection window');
      final edited = refused.editedTo(
        collectedAmount: 400,
        payload: {'p_collected_amount': 400},
      );

      expect(edited.state, ManaOutboxState.queued);
      expect(edited.idempotencyKey, isNot(refused.idempotencyKey));
      expect(edited.attempts, 0, reason: 'a new entry starts its own count');
      expect(edited.lastError, isNull,
          reason: 'the old refusal is not this entry\'s refusal');
    });
  });

  group('the states move in one direction only', () {
    test('queued -> sending -> sent', () {
      final sent = anEntry().markSending().markSent('collection-123');
      expect(sent.state, ManaOutboxState.sent);
      expect(sent.serverCollectionId, 'collection-123');
    });

    test('a refusal carries the server\'s own sentence', () {
      // app.record_collection raises sixteen distinct refusals and every one is
      // written to be read by a person. Replacing them with "Could not save"
      // throws away the only thing that tells the agent what to do next.
      const refusal = 'No BF assignment for this agent';
      final e = anEntry().markSending().markRefused(refusal);
      expect(e.state, ManaOutboxState.refused);
      expect(e.lastError, refusal);
    });

    test('a transport failure goes back to queued, not refused', () {
      // A refusal is a fact about the world. A dropped connection is not, and
      // conflating them either retries something the server has rejected or
      // abandons something it never saw.
      final e = anEntry().markSending().markQueuedAgain('connection closed');
      expect(e.state, ManaOutboxState.queued);
    });
  });

  group('stuck is said out loud', () {
    test('a fresh entry is not stuck', () {
      expect(anEntry().isStuck(attemptsAllowed: 3), isFalse);
    });

    test('an entry that keeps failing is stuck', () {
      // No time cap -- it queues until live, as asked. But silence about an
      // entry that has been retrying for minutes would be the app hiding a
      // problem rather than a connection.
      var e = anEntry();
      for (var i = 0; i < 3; i++) {
        e = e.markSending().markQueuedAgain('no connection');
      }
      expect(e.attempts, 3);
      expect(e.isStuck(attemptsAllowed: 3), isTrue);
    });

    test('a sent entry is never stuck, whatever it took to get there', () {
      var e = anEntry();
      for (var i = 0; i < 5; i++) {
        e = e.markSending().markQueuedAgain('no connection');
      }
      expect(e.markSending().markSent('x').isStuck(attemptsAllowed: 3), isFalse);
    });
  });

  test('an entry survives a round trip through storage', () {
    // sqflite holds these as rows; the app rebuilds them on launch. A field
    // lost in that trip is a collection the sender cannot replay.
    final original = anEntry().markSending().markQueuedAgain('flaky');
    final restored = ManaOutboxEntry.fromRow(original.toRow());

    expect(restored.id, original.id);
    expect(restored.idempotencyKey, original.idempotencyKey);
    expect(restored.state, original.state);
    expect(restored.attempts, original.attempts);
    expect(restored.collectedAmount, original.collectedAmount);
    expect(restored.customerName, original.customerName);
    expect(restored.payload, original.payload);
    expect(restored.lastError, original.lastError);
  });
}

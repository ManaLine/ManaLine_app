import 'dart:async';

import 'mana_outbox_entry.dart';
import 'mana_outbox_failure.dart';

export 'mana_outbox_entry.dart';

/// Where entries live between attempts. Deliberately tiny, so the sqflite
/// adapter has no decisions in it and the decisions have no sqflite in them.
abstract class ManaOutboxStore {
  Future<List<ManaOutboxEntry>> all();
  Future<void> put(ManaOutboxEntry entry);
  Future<void> remove(String id);
}

/// One attempt at one entry. Returns the server's collection id on success.
typedef ManaOutboxSend = Future<String> Function(ManaOutboxEntry entry);

/// The queue between recording a collection and it being saved.
///
/// Built for the shape the Owner described: gaps of minutes, not hours, and
/// "just queue it until live, like WhatsApp messages. Meanwhile user can
/// delete, rewrite those queued entries." Full reasoning in
/// docs/decisions/2026-09-15-offline.md.
class ManaOutbox {
  final ManaOutboxStore store;
  final ManaOutboxSend send;

  /// How many failed attempts before the agent is told it is stuck. No time
  /// cap -- it queues until live, as asked -- but silence about an entry that
  /// has been retrying for minutes would be the app hiding a problem rather
  /// than a connection.
  final int attemptsBeforeStuck;

  bool _flushing = false;

  ManaOutbox({
    required this.store,
    required this.send,
    this.attemptsBeforeStuck = 3,
  });

  Future<void> enqueue(ManaOutboxEntry entry) => store.put(entry);

  Future<List<ManaOutboxEntry>> pending() async {
    final all = await store.all();
    return all.where((e) => e.state != ManaOutboxState.sent).toList();
  }

  /// Replace a queued or refused entry with corrected figures.
  ///
  /// Throws if the entry is mid-flight. That is not defensiveness: during an
  /// attempt nobody can tell "never arrived" from "arrived, reply lost", and
  /// sending a CHANGED amount under a key the server has already answered
  /// would return the ORIGINAL response -- success on screen, edit never
  /// written.
  Future<void> edit(
    String id, {
    required int collectedAmount,
    required Map<String, dynamic> payload,
  }) async {
    final all = await store.all();
    final entry = all.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StateError('No queued entry $id'),
    );
    if (!entry.canEdit) {
      throw StateError(
          'This entry is being sent. Wait for it to finish before changing it.');
    }
    // A new entry with a new key, and the old row removed. Not an update:
    // the identity of a write is its key, and this is a different write.
    final edited =
        entry.editedTo(collectedAmount: collectedAmount, payload: payload);
    await store.remove(entry.id);
    await store.put(edited);
  }

  Future<void> remove(String id) async {
    final all = await store.all();
    final entry = all.where((e) => e.id == id).firstOrNull;
    if (entry != null && !entry.canDelete) {
      throw StateError(
          'This entry is being sent. Wait for it to finish before deleting it.');
    }
    await store.remove(id);
  }

  /// Try everything that is waiting.
  ///
  /// Only `queued` entries are attempted. A `refused` one is NOT retried --
  /// that is a fact about the world, and retrying reproduces it at a time
  /// nobody is watching.
  Future<void> flush() async {
    // One at a time. Idempotency would cover a double send, but a second
    // in-flight copy of the same write spends a round trip to be told what the
    // first one already knew -- on a connection that is, by definition, poor.
    if (_flushing) return;
    _flushing = true;
    try {
      final waiting = (await store.all())
          .where((e) => e.state == ManaOutboxState.queued)
          .toList();

      for (final entry in waiting) {
        await store.put(entry.markSending());
        try {
          final collectionId = await send(entry);
          // Gone from the queue rather than kept as `sent`. Once it is on the
          // server, the server is the record -- keeping a copy here would make
          // the outbox a second ledger to be held in step with `collections`,
          // and two records of one payment is how they come to disagree.
          await store.remove(entry.id);
          assert(collectionId.isNotEmpty);
        } catch (error) {
          // One bad entry must not strand the ones behind it. An agent who
          // worked a village should not lose nineteen collections because the
          // twentieth was wrong.
          final next = switch (manaClassifyOutboxFailure(error)) {
            ManaOutboxFailure.refusal =>
              entry.markRefused(manaOutboxFailureMessage(error)),
            ManaOutboxFailure.transport =>
              entry.markQueuedAgain(manaOutboxFailureMessage(error)),
          };
          await store.put(next);
        }
      }
    } finally {
      _flushing = false;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/owner_workspace/state/collection_mode_state.dart';
import 'mana_outbox.dart';
import 'mana_outbox_failure.dart';
import 'mana_outbox_sqflite_store.dart';

/// The app's one outbox.
///
/// THE COLLECTION PATH IS NOT REROUTED THROUGH THIS. A collection is still
/// attempted directly, exactly as before, and only falls in here when the
/// attempt reaches no verdict.
///
/// That is deliberate, and it is the conservative reading of "queue it until
/// live". Routing every collection through a queue would cost three things
/// that exist today and are worth keeping:
///
///   * the RECEIPT, which comes back from the server and cannot be invented;
///   * the BALANCE the screen shows straight after;
///   * `alreadyRecorded`, the one-entry-per-window duplicate answer, which
///     only the server can give.
///
/// Gaps are minutes, so the overwhelming majority of collections still get all
/// three immediately. The queue exists for the ones that do not.
///
/// THE CONSEQUENCE, stated rather than buried: a queued collection has not
/// been duplicate-checked. If it turns out to be a second entry for that loan
/// in that window, the server refuses it on sync and the entry goes to
/// `refused` carrying that sentence -- which is the design working, not
/// failing.
final manaOutboxStoreProvider = Provider<ManaOutboxSqfliteStore>((ref) {
  final store = ManaOutboxSqfliteStore();
  ref.onDispose(store.close);
  return store;
});

final manaOutboxProvider = Provider<ManaOutbox>((ref) {
  final store = ref.read(manaOutboxStoreProvider);
  return ManaOutbox(
    store: store,
    send: (entry) async {
      // The SAME service the screen calls directly. Not a second path to
      // app.record_collection -- two of those would have to be kept in step
      // by hand, and a money write is the last place to accept that.
      //
      // The entry's own key is reused on every attempt, which is what makes a
      // replay return the original answer instead of writing twice.
      final outcome =
          await ref.read(collectionApiServiceProvider).recordCollection(
                loanId: entry.loanId,
                customerId: entry.customerId,
                collectedAmount: entry.collectedAmount,
                payerType: entry.payload['payer_type'] as String? ?? 'Customer',
                payerName: entry.payload['payer_name'] as String?,
                paymentSplits: manaSplitsFromPayload(entry.payload),
                businessDate: entry.businessDate,
                businessId: entry.businessId,
                excessDisposition:
                    entry.payload['excess_disposition'] as String?,
                idempotencyKey: entry.idempotencyKey,
                parentCollectionId:
                    entry.payload['parent_collection_id'] as String?,
              );

      // An `alreadyRecorded` answer is the server declining to write a second
      // entry for this loan in this window. It is a refusal, not a success,
      // and it must not be swallowed as one -- otherwise the entry vanishes
      // from the queue and the agent believes it landed.
      final existing = outcome.alreadyRecorded;
      if (existing != null) {
        throw const _OutboxDuplicateRefusal();
      }
      return outcome.saved?.collectionId ?? '';
    },
  );
});

/// Rebuild the splits a collection was recorded with.
///
/// Held in the payload as plain maps because that is what survives a trip
/// through sqflite as JSON. A split lost on the way to disk is a collection
/// recorded as the wrong kind of money -- Cash arriving as UPI reconciles
/// against the wrong total at day close.
///
/// Paired with [manaSplitsToPayload] so the two halves cannot drift.
List<PaymentSplit> manaSplitsFromPayload(Map<String, dynamic> payload) {
  final raw = payload['splits'];
  if (raw is! List) return const [];
  return [
    for (final s in raw)
      if (s is Map)
        PaymentSplit(
          paymentMode: s['payment_mode'] as String,
          amount: (s['amount'] as num).toInt(),
        ),
  ];
}

/// The payload shape [manaSplitsFromPayload] reads back.
List<Map<String, dynamic>> manaSplitsToPayload(List<PaymentSplit> splits) => [
      for (final s in splits)
        {'payment_mode': s.paymentMode, 'amount': s.amount},
    ];

/// Read as a refusal rather than something to retry forever.
///
/// It implements ManaOutboxRefusalError rather than plain Exception, and that
/// is the load-bearing word. The classifier defaults the unrecognised to
/// `transport`, so without the marker this would be retried against a server
/// that will go on saying the same thing until the day closes.
class _OutboxDuplicateRefusal implements ManaOutboxRefusalError {
  const _OutboxDuplicateRefusal();

  @override
  String get refusalMessage =>
      'This loan already has an entry for this collection window.';

  @override
  String toString() => refusalMessage;
}

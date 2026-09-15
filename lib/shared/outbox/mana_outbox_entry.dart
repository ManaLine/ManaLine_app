import 'dart:convert';

import '../idempotency.dart';
import '../mana_time.dart';

/// Where a collection sits between being recorded and being saved.
///
/// THE SHAPE THE OWNER ASKED FOR: gaps of minutes, not hours. "Just queue it
/// until live, like WhatsApp messages. Meanwhile user can delete, rewrite
/// those queued entries." So this is an OUTBOX, not an offline mode, and the
/// full reasoning is in docs/decisions/2026-09-15-offline.md.
///
/// This file is deliberately PURE. No sqflite, no network, no Riverpod -- the
/// state machine and the key rule are the parts that can lose money, and they
/// are worth being able to test without a device attached. Storage is a dumb
/// adapter around [toRow] and [fromRow].
enum ManaOutboxState {
  /// Never attempted. Nothing has left the phone, so it is a local draft.
  queued,

  /// An attempt is in flight, or its outcome is unknown.
  sending,

  /// The server took it. It is a real collection now.
  sent,

  /// The server refused it, and said why.
  refused,
}

class ManaOutboxEntry {
  /// Local row id. Not the server's collection id -- see [serverCollectionId].
  final String id;

  /// THE KEY THAT MAKES A RETRY SAFE, and an edit dangerous.
  ///
  /// `idempotency_keys` stores the RESPONSE, not just the key, so replaying
  /// returns the original answer rather than writing twice. Which is exactly
  /// why [editedTo] mints a new one: re-sending a CHANGED amount under the old
  /// key would return the old answer, and the edit would silently not happen.
  final String idempotencyKey;

  final ManaOutboxState state;
  final String businessId;
  final String loanId;
  final String customerId;

  /// Carried so the queue can be drawn without a network read. An outbox that
  /// cannot say whose collection is waiting is a list of amounts.
  final String customerName;

  final int collectedAmount;
  final String businessDate;

  /// Everything `app.record_collection` needs, as it will be sent. Held whole
  /// rather than as fields so that adding a parameter to that RPC does not
  /// silently drop it from every queued entry.
  final Map<String, dynamic> payload;

  final int attempts;

  /// The server's own sentence when it refused, or the transport's when it
  /// failed. `record_collection` raises sixteen distinct refusals and each is
  /// written to be read by a person; replacing them with "Could not save"
  /// throws away the only thing that tells the agent what to do next.
  final String? lastError;

  final String createdAt;
  final String? serverCollectionId;

  const ManaOutboxEntry({
    required this.id,
    required this.idempotencyKey,
    required this.state,
    required this.businessId,
    required this.loanId,
    required this.customerId,
    required this.customerName,
    required this.collectedAmount,
    required this.businessDate,
    required this.payload,
    required this.attempts,
    required this.createdAt,
    this.lastError,
    this.serverCollectionId,
  });

  factory ManaOutboxEntry.create({
    required String businessId,
    required String loanId,
    required String customerId,
    required String customerName,
    required int collectedAmount,
    required String businessDate,
    required Map<String, dynamic> payload,
  }) {
    // Minted ONCE, here, at the moment the agent commits -- not inside the
    // send closure. A key minted per attempt is the same as having none; see
    // shared/idempotency.dart.
    final key = manaIdempotencyKey();
    return ManaOutboxEntry(
      // The key doubles as the row id. It is already unique, already minted at
      // the right moment, and one identifier is one thing to keep in step.
      id: key,
      idempotencyKey: key,
      state: ManaOutboxState.queued,
      businessId: businessId,
      loanId: loanId,
      customerId: customerId,
      customerName: customerName,
      collectedAmount: collectedAmount,
      businessDate: businessDate,
      payload: payload,
      attempts: 0,
      createdAt: manaTimestamp(),
    );
  }

  /// Whether the agent may change this entry.
  ///
  /// `sending` is excluded and that is the load-bearing part: during an
  /// attempt nobody can tell "never arrived" from "arrived, reply lost", and
  /// those need opposite handling. `sent` is excluded because it is a real
  /// collection now, governed by app.amend_collection and the
  /// correct-until-handed-over rule rather than by this queue.
  bool get canEdit =>
      state == ManaOutboxState.queued || state == ManaOutboxState.refused;

  bool get canDelete => canEdit;

  /// A new entry carrying the corrected figures, with a NEW key.
  ///
  /// Returns a fresh entry rather than mutating: the queued one may still be
  /// mid-flight in another isolate's view of the world, and an edit must never
  /// reach the server under an identifier the server has already answered.
  ManaOutboxEntry editedTo({
    required int collectedAmount,
    required Map<String, dynamic> payload,
  }) {
    final key = manaIdempotencyKey();
    return ManaOutboxEntry(
      id: key,
      idempotencyKey: key,
      state: ManaOutboxState.queued,
      businessId: businessId,
      loanId: loanId,
      customerId: customerId,
      customerName: customerName,
      collectedAmount: collectedAmount,
      businessDate: businessDate,
      payload: payload,
      // Its own count. The previous entry's failures say nothing about this
      // one, which carries different figures.
      attempts: 0,
      createdAt: manaTimestamp(),
    );
  }

  ManaOutboxEntry markSending() => copyWith(state: ManaOutboxState.sending);

  ManaOutboxEntry markSent(String collectionId) => copyWith(
        state: ManaOutboxState.sent,
        serverCollectionId: collectionId,
        clearError: true,
      );

  /// The server refused it. A fact about the world, not a transient failure --
  /// so it is NOT retried automatically. Retrying produces the same refusal at
  /// a time nobody is watching.
  ManaOutboxEntry markRefused(String reason) =>
      copyWith(state: ManaOutboxState.refused, lastError: reason);

  /// The attempt did not reach a verdict -- no connection, a dropped socket, a
  /// timeout. Back to the queue, under the SAME key, with the count advanced.
  ManaOutboxEntry markQueuedAgain(String reason) => copyWith(
        state: ManaOutboxState.queued,
        attempts: attempts + 1,
        lastError: reason,
      );

  /// Worth telling the agent about.
  ///
  /// There is no time cap -- it queues until live, as asked. But an entry that
  /// has been retrying for minutes is telling them something, and saying
  /// nothing would be the app hiding a problem rather than a connection.
  bool isStuck({required int attemptsAllowed}) =>
      state != ManaOutboxState.sent && attempts >= attemptsAllowed;

  ManaOutboxEntry copyWith({
    ManaOutboxState? state,
    int? attempts,
    String? lastError,
    String? serverCollectionId,
    bool clearError = false,
  }) =>
      ManaOutboxEntry(
        id: id,
        idempotencyKey: idempotencyKey,
        state: state ?? this.state,
        businessId: businessId,
        loanId: loanId,
        customerId: customerId,
        customerName: customerName,
        collectedAmount: collectedAmount,
        businessDate: businessDate,
        payload: payload,
        attempts: attempts ?? this.attempts,
        createdAt: createdAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        serverCollectionId: serverCollectionId ?? this.serverCollectionId,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'idempotency_key': idempotencyKey,
        'state': state.name,
        'business_id': businessId,
        'loan_id': loanId,
        'customer_id': customerId,
        'customer_name': customerName,
        'collected_amount': collectedAmount,
        'business_date': businessDate,
        'payload': jsonEncode(payload),
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt,
        'server_collection_id': serverCollectionId,
      };

  factory ManaOutboxEntry.fromRow(Map<String, Object?> row) => ManaOutboxEntry(
        id: row['id'] as String,
        idempotencyKey: row['idempotency_key'] as String,
        state: ManaOutboxState.values.firstWhere(
          (s) => s.name == row['state'],
          // An unreadable state is treated as queued rather than discarded. A
          // row that cannot be parsed is still somebody's money; losing it
          // quietly is the one outcome this queue exists to prevent.
          orElse: () => ManaOutboxState.queued,
        ),
        businessId: row['business_id'] as String,
        loanId: row['loan_id'] as String,
        customerId: row['customer_id'] as String,
        customerName: row['customer_name'] as String,
        collectedAmount: (row['collected_amount'] as num).toInt(),
        businessDate: row['business_date'] as String,
        payload: Map<String, dynamic>.from(
            jsonDecode(row['payload'] as String) as Map),
        attempts: (row['attempts'] as num).toInt(),
        lastError: row['last_error'] as String?,
        createdAt: row['created_at'] as String,
        serverCollectionId: row['server_collection_id'] as String?,
      );
}

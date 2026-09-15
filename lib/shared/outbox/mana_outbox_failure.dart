import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Did the server say no, or did the attempt never get an answer?
///
/// The two look alike from the outside and need opposite handling. A refusal
/// is a fact about the world: retrying reproduces it at a time nobody is
/// watching, so it goes to the agent with the server's own sentence. A dropped
/// connection says nothing at all, so it goes back in the queue under the same
/// key.
enum ManaOutboxFailure {
  /// The server considered this write and rejected it.
  refusal,

  /// The attempt reached no verdict. Try again.
  transport,
}

/// SQLSTATEs are five characters: five digits, or a letter and four
/// alphanumerics (`P0002`, `23514`, `42501`). An HTTP status is three digits.
/// That is enough to tell a plpgsql `RAISE EXCEPTION` from a gateway.
final _sqlState = RegExp(r'^[0-9A-Z][0-9A-Z]{4}$');

/// Classify a failed send.
///
/// THE DEFAULT IS RETRY, and it follows from the schema rather than from
/// caution. `idempotency_keys` stores the RESPONSE, so replaying a key the
/// server has already answered returns that same answer instead of writing
/// twice. An unrecognised failure therefore costs one wasted round trip if the
/// server did decide, and saves a real collection if it did not. Defaulting to
/// `refusal` has the opposite payoff: it strands somebody's money on a
/// handset.
ManaOutboxFailure manaClassifyOutboxFailure(Object error) {
  if (error is TimeoutException) return ManaOutboxFailure.transport;
  // NO `dart:io` HERE, so no `error is SocketException`. dart:io is a stub on
  // web that throws on use, and this app has a web build -- importing it
  // reaches every screen that can reach the outbox. web_plugin_fallback_test
  // caught exactly that.
  //
  // Nothing is lost: a SocketException falls through to the default below,
  // which is already `transport`. That default is the safe direction because
  // idempotency_keys stores the RESPONSE, so replaying a key the server has
  // answered returns that answer rather than writing twice.
  if (error is PostgrestException) {
    final code = error.code;
    if (code == null) return ManaOutboxFailure.transport;
    // A PostgrestException does NOT always mean plpgsql spoke. PostgREST and
    // whatever sits in front of it raise the same type for infrastructure
    // failures, and a 503 is the load balancer talking rather than a verdict
    // on this write.
    if (_sqlState.hasMatch(code)) return ManaOutboxFailure.refusal;
    return ManaOutboxFailure.transport;
  }
  return ManaOutboxFailure.transport;
}

/// What to show the agent.
///
/// `app.record_collection` raises sixteen distinct refusals and every one is
/// written to be read by a person -- "That receipt is from a different
/// collection window", "No BF assignment for this agent". Replacing them with
/// "Could not save" throws away the only thing that says what to do next.
String manaOutboxFailureMessage(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is TimeoutException) return 'No answer from the server';
  // SocketException is matched by NAME rather than by type, for the dart:io
  // reason above. A message is cosmetic -- getting it wrong costs a less
  // helpful sentence, not a lost collection -- so a string compare is the
  // right trade here where it would not be in the classifier.
  if (error.runtimeType.toString() == 'SocketException') return 'No connection';
  return error.toString();
}

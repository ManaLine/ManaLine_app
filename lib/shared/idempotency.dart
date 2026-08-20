import 'dart:math';

/// A key that makes one financial write safe to retry.
///
/// THE FIELD CASE this exists for: an Agent on 2G taps Save on a collection.
/// The request reaches the server, the reply never comes back, and the app
/// offers Retry. Without a key every retry records a SECOND collection — the
/// customer's balance drops twice, the agent's float rises twice, and nobody
/// notices until a settlement fails. With one, the server replays what the
/// first call returned: the same receipt number, the same balance.
///
/// HOW TO USE IT CORRECTLY, which is the whole point:
///
///   * Mint ONE key when the person commits to the action — the moment they
///     tap Save, not when the screen opens and not inside the retry closure.
///   * Reuse that same key for every retry of that same action.
///   * Throw it away once the write has succeeded, so the NEXT save is a new
///     action rather than a replay of the last one.
///
/// A key minted inside the closure that `NetworkErrorHandler` re-invokes would
/// be a fresh key on every retry, which is exactly the same as having none.
String manaIdempotencyKey() {
  // No uuid package: adding a dependency for one string is not worth another
  // build-compatibility risk on AGP 9 (same reasoning as appearance_state's
  // note on secure storage). Time plus 96 bits of randomness is far beyond
  // what one handset generating a few hundred keys a day needs, and the time
  // prefix makes a key legible in the idempotency_keys table when debugging.
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  final suffix = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

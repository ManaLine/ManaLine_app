import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/outbox/mana_outbox_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Did the server say no, or did the attempt never get an answer?
///
/// These need OPPOSITE handling and look alike from the outside. A refusal is
/// a fact about the world: retrying reproduces it at a time nobody is
/// watching, so it goes to the agent. A dropped connection says nothing at
/// all, so it goes back in the queue.
///
/// THE SAFE DEFAULT IS RETRY, and that is not a coin toss -- it follows from
/// idempotency_keys storing the RESPONSE. Replaying a key the server has
/// already answered returns that same answer rather than writing twice. So an
/// unrecognised failure costs one wasted round trip if the server did answer,
/// and saves a lost collection if it did not. Treating the unknown as a
/// refusal has the opposite payoff: it strands real money.
void main() {
  group('the server answered', () {
    test('a plpgsql refusal is a refusal', () {
      // app.record_collection raises sixteen of these, each with a SQLSTATE.
      for (final code in ['23514', '42501', 'P0002', '22023']) {
        final e = PostgrestException(
            message: 'Collected amount must be positive', code: code);
        expect(manaClassifyOutboxFailure(e), ManaOutboxFailure.refusal,
            reason: 'SQLSTATE $code is the server having decided');
      }
    });

    test('the refusal keeps the server\'s own words', () {
      const sentence =
          'No BF assignment for this agent — the Owner must grant BF before '
          'collections can be credited';
      expect(manaOutboxFailureMessage(
              const PostgrestException(message: sentence, code: 'P0002')),
          sentence,
          reason: 'these sentences are written to be read by a person, and '
              'they are the only thing telling the agent what to do next');
    });
  });

  group('the server never answered', () {
    test('a timeout is not a refusal', () {
      // NetworkErrorHandler puts a 20s deadline on every call precisely
      // because PostgREST has none. Hitting it says nothing about whether the
      // write landed.
      expect(manaClassifyOutboxFailure(TimeoutException('too slow')),
          ManaOutboxFailure.transport);
    });

    test('no route to the host is not a refusal', () {
      expect(
          manaClassifyOutboxFailure(
              const SocketException('Failed host lookup')),
          ManaOutboxFailure.transport);
    });

    test('a 5xx from the gateway is not a refusal', () {
      // A PostgrestException does NOT always mean plpgsql spoke. PostgREST and
      // whatever sits in front of it raise the same type for infrastructure
      // failures, and a 503 is the load balancer talking, not the database.
      for (final code in ['500', '502', '503', '504']) {
        expect(
            manaClassifyOutboxFailure(
                PostgrestException(message: 'Bad gateway', code: code)),
            ManaOutboxFailure.transport,
            reason: '$code is infrastructure, not a verdict on this write');
      }
    });

    test('a PostgrestException with no code at all is retried', () {
      // Unknown shape. Retry is safe because the key replays; calling it a
      // refusal would strand a real collection.
      expect(
          manaClassifyOutboxFailure(
              const PostgrestException(message: 'something')),
          ManaOutboxFailure.transport);
    });

    test('an error nobody anticipated is retried', () {
      expect(manaClassifyOutboxFailure(StateError('unexpected')),
          ManaOutboxFailure.transport,
          reason: 'the unknown must default to the direction that cannot lose '
              'money');
    });
  });
}

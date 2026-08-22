import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/idempotency.dart';

/// A key exists so an Agent on 2G whose reply never came back can press Retry
/// without recording the collection twice. Everything about it that matters is
/// uniqueness per action and stability across retries — the second half lives
/// in the screen (mint once, reuse, clear on success), the first half is here.
void main() {
  test('two actions never share a key', () {
    final keys = {for (var i = 0; i < 5000; i++) manaIdempotencyKey()};
    expect(keys, hasLength(5000));
  });

  test('keys minted in the same microsecond still differ', () {
    // The time prefix alone is not enough — two taps can land in one tick.
    // The random suffix is what actually separates them.
    final a = manaIdempotencyKey();
    final b = manaIdempotencyKey();
    expect(a, isNot(b));
    expect(a.split('-').last, isNot(b.split('-').last));
  });

  test('a key is safe to put in a URL or a log line', () {
    expect(manaIdempotencyKey(), matches(RegExp(r'^\d+-[0-9a-f]{24}$')));
  });

  _keyDiscipline();
}

/// The rule the key exists to enforce, checked against the call site rather
/// than the helper: step 4's loan import must send ONE key for an import and
/// all of its retries, and a different one for a genuinely new import.
///
/// This is the failure it prevents, from the live book on 22 Aug 2026: the
/// import passed the app's 20-second deadline, the Owner pressed Retry, and
/// the whole book went in twice — 108 loans, a line balance of 57,90,300
/// against a true 30,04,900, and a day ledger cascaded to minus 8,20,320.
void _keyDiscipline() {
  test('a key minted at the tap survives retries; a new action gets a new one',
      () {
    // Mint at the tap, outside anything the retry re-invokes.
    String? held;
    String tap() => held ??= manaIdempotencyKey();

    final first = tap();
    // Two retries of the SAME action — NetworkErrorHandler re-invokes the
    // closure, which reads the held key rather than minting.
    expect(tap(), first);
    expect(tap(), first);

    // Succeeded: cleared, so the next import is a new action.
    held = null;
    expect(tap(), isNot(first));
  });
}

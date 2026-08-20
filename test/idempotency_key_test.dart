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
}

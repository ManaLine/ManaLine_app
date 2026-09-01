import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The client does not move money. It asks the server to.
///
/// THE BUG THIS EXISTS FOR: approveWithdrawalRequest paid out an investor
/// with three separate client-side writes — insert the withdrawal row with
/// whatever split had been typed into a dialog, subtract the principal
/// portion, mark the request paid. Nothing checked that the interest being
/// paid had been earned, nothing checked the request had not already been
/// paid, and because they were three statements rather than one transaction,
/// a failure between them pays somebody and leaves their principal untouched.
///
/// A withdrawal of Rs 2,00,000 against Rs 70,950 of interest would have been
/// recorded as fact.
///
/// THE RULE: no `.insert`/`.update`/`.upsert` from `lib/` may carry a money
/// AMOUNT in its payload. Money amounts move through `.schema('app').rpc(...)`,
/// where the checks, the ordering and the transaction live.
///
/// Scoped to amounts rather than to tables on purpose. Banning every write to
/// `loans` or `day_ledger` would flag the remarks edit and the agent
/// reassignment — neither of which moves a rupee — and a guard that forces a
/// long allowlist stops being read. This flags the payloads that carry value.
///
/// WHAT IS ON THE LIST: balances the SERVER derives, and the portions of a
/// movement. A client write to one of these corrupts an invariant somebody
/// else recomputes — `principal_amount` is maintained against a compounding
/// schedule, `agent_bf_current` against a stream of events, `remaining_balance`
/// against a loan's payments.
///
/// WHAT IS NOT: figures a person DECLARES when recording something —
/// `face_value`, `instalment_amount`, `availed_amount` on a cheti. Those are
/// user-entered facts about an asset, not balances, and a wrong one is a data
/// error rather than a broken invariant. `availed_amount` was on this list for
/// its first run and flagged the cheti creation form; it came off because the
/// rule is about derived balances, not because the test was inconvenient. The
/// distinction is the whole point of the list being hand-written.
///
/// KNOWN LIMIT, stated rather than hidden: this reads literal map payloads.
/// `update(patch)` where `patch` is built elsewhere is invisible to it. The
/// one such call in the codebase today (loan_details_state.dart) carries an
/// agent id and a note, checked by hand. A guard that catches the common
/// shape is worth having; pretending it catches every shape is not.
const _moneyColumns = <String>[
  'principal_amount',
  'original_principal_amount',
  'principal_portion',
  'interest_portion',
  'interest_amount',
  'collected_amount',
  'remaining_balance',
  'agent_bf_current',
  'opening_bf',
  'owner_bf_balance',
  'net_paid',
  'opening_balance',
  'closing_balance',
];

/// `.insert({...})` / `.update({...})` / `.upsert({...})` and their payload.
final _writePattern = RegExp(
  r'\.(insert|update|upsert)\s*\(\s*\{(.*?)\}\s*\)',
  dotAll: true,
);

Iterable<({String op, String payload})> _writesIn(String source) sync* {
  for (final m in _writePattern.allMatches(source)) {
    yield (op: m.group(1)!, payload: m.group(2)!);
  }
}

void main() {
  test('the guard catches the payout it was written for', () {
    // Verbatim the shape of approveWithdrawalRequest.
    const bad = '''
      await _db.from('investment_withdrawals').insert({
        'investment_id': investmentId,
        'amount': amount,
        'principal_portion': principalPortion,
        'interest_portion': interestPortion,
      });
    ''';
    final flagged = _writesIn(bad)
        .where((w) => _moneyColumns.any(w.payload.contains));
    expect(flagged, isNotEmpty);

    // And that it leaves an ordinary metadata write alone.
    const good = '''
      await _db.from('day_ledger').update({'remarks': remarks}).eq('id', id);
    ''';
    expect(
        _writesIn(good).where((w) => _moneyColumns.any(w.payload.contains)),
        isEmpty);
  });

  test('no client write carries a money amount', () {
    final violations = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final m in _writePattern.allMatches(source)) {
        final payload = m.group(2)!;
        final hit = _moneyColumns.where(payload.contains).toList();
        if (hit.isEmpty) continue;
        final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
        violations.add('${file.path}:$line writes ${hit.join(', ')}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'A money amount is being written straight from the client. Put '
          'it behind an app-schema RPC, where the affordability check, the '
          'ordering and the transaction can live together. Offenders:\n  '
          '${violations.join('\n  ')}',
    );
  });
}

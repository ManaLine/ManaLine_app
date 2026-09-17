import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/payment_modes.dart';

import 'support/schema_snapshot.dart';

/// The payment-mode vocabulary, which had drifted before anyone looked.
///
/// On 2026-09-17 `payment_mode_enum` gained GPay, PhonePe and Paytm. The
/// vocabulary was written out twice in `lib/` at the time -- a list and a key
/// map in OW-006's collection form, and four hardcoded `byMode('...')` calls
/// in the agent dashboard -- and only the first was found by grepping for the
/// obvious name.
///
/// The second copy is what made this worth a guard rather than a comment.
/// `byMode(mode)` sums the splits matching one mode and `todaysCollectionsTotal`
/// adds the buckets up, so a payment in a mode nobody asks for lands in NO
/// bucket and disappears from the figure an agent reads as their day's
/// takings. Not a wrong label -- missing money, on the screen an agent settles
/// against.
///
/// CLAUDE.md: "Before changing anything shared, list its consumers... If the
/// list is longer than one, every entry gets checked or gets said out loud."
void main() {
  test('every mode the database has, the app has a word for', () {
    final inDb = manaDbEnums['payment_mode_enum'] ?? const <String>[];
    expect(inDb, isNotEmpty,
        reason: 'the snapshot has no payment_mode_enum, so this test is '
            'checking nothing -- regenerate it');

    expect(manaPaymentModes.toSet(), inDb.toSet(),
        reason: 'lib/shared/payment_modes.dart and payment_mode_enum disagree. '
            'A mode the database has and the app does not is money that lands '
            'in no bucket on the agent dashboard.');

    for (final mode in manaPaymentModes) {
      expect(manaPaymentModeKey(mode), isNot(mode),
          reason: '$mode falls through to the default branch, so it would '
              'render its own raw name instead of a translated word');
    }
  });

  test('the offered modes are a subset, and Cash is first', () {
    expect(manaPaymentModes.toSet().containsAll(manaOfferedPaymentModes), isTrue,
        reason: 'a form cannot offer a mode the database would reject');
    expect(manaOfferedPaymentModes.first, 'Cash',
        reason: '349 of 355 live splits are Cash; it is most of every day');
    // UPI is deliberately not offered -- see payment_modes.dart. If it ever is,
    // that is a decision, not a typo, and this line should be the thing that
    // makes somebody say so.
    expect(manaOfferedPaymentModes, isNot(contains('UPI')));
  });

  test('online means online, and a cheque is not', () {
    expect(manaPaymentModes.toSet().containsAll(manaOnlinePaymentModes), isTrue);
    expect(manaOnlinePaymentModes, isNot(contains('Cash')));
    expect(manaOnlinePaymentModes, isNot(contains('Cheque')),
        reason: 'a cheque is not an online payment and has its own line');
    expect(manaOnlinePaymentModes, isNot(contains('Bank Transfer')),
        reason: 'money moved at a branch is not an online payment');
    expect(manaOnlinePaymentModes, contains('UPI'),
        reason: 'the six historical rows are online payments and must keep '
            'counting as such');
  });

  test('nothing in lib/ writes its own copy of the mode list', () {
    // The exact shape that caused this: a mode literal inside a byMode-style
    // call, or a second const list of modes. Scoped to a hardcoded 'UPI'
    // string, which is the one value that existed in both old copies.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.replaceAll(r'\', '/').endsWith('shared/payment_modes.dart')) {
        continue;
      }
      final text = entity.readAsStringSync();
      // A comment may name UPI freely; a line of code may not.
      for (final line in text.split('\n')) {
        final code = line.trim();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (code.contains("'UPI'")) {
          offenders.add(entity.path.split(RegExp(r'[\/]')).last);
          break;
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these name a payment mode directly instead of going through '
            'lib/shared/payment_modes.dart, which is how the agent dashboard '
            'came to have buckets that could not hold a GPay payment: '
            '$offenders');
  });
}

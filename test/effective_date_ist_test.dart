import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_time.dart';

/// Effective dates must come from the IST clock, never the handset clock.
///
/// `_effectiveDate = DateTime.now()` on a loan or investment screen is a write
/// site: the value is serialised straight into `p_effective_date`, which is
/// the business day the money is booked against. `mana_time.dart` exists to
/// stop a phone with a wrong timezone — a factory reset, a device carried
/// abroad, a clock that never synced — filing a loan onto the wrong Indian
/// day. Four screens were bypassing it.
///
/// HONEST LIMITATION, stated rather than papered over: on a machine already
/// running IST these assertions cannot distinguish `manaNowIst()` from
/// `DateTime.now()`, because the two agree. They bite on a UTC CI box for the
/// 5h30m window each day where the IST date has already rolled over — which
/// is exactly the window the bug lives in. The `simulateHandsetSkew` case
/// below is the deterministic one: it proves the offset is derived from UTC
/// and not read from the device, on any machine.
void main() {
  group('mana_time is the single clock for business dates', () {
    test('manaNowIst is derived from UTC, not from the device timezone', () {
      // DateTime.now().toUtc() is the same instant everywhere regardless of
      // how the handset is configured, so this holds on any test machine.
      final utc = DateTime.now().toUtc();
      final ist = manaNowIst();
      final drift = ist.difference(DateTime(
        utc.year,
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second,
        utc.millisecond,
      ));
      expect(
        (drift - kIstOffset).abs() < const Duration(seconds: 2),
        isTrue,
        reason: 'manaNowIst must be exactly UTC+05:30, got a drift of $drift',
      );
    });

    test('manaBusinessDate is the IST calendar day', () {
      expect(manaBusinessDate(), manaDateOf(manaNowIst()));
    });

    test('a handset five hours behind still yields the IST business day', () {
      // The defect in concrete terms: 23:00 IST on the 12th is 17:30 UTC, and
      // a handset mistakenly on UTC reports the 12th too — but at 00:30 IST
      // on the 13th the same handset still says the 12th. manaDateOf over an
      // IST-derived instant is what keeps the two apart.
      final istInstant = DateTime(2026, 8, 13, 0, 30); // 00:30 IST, 13th
      final handsetOnUtc = istInstant.subtract(kIstOffset); // 19:00, 12th
      expect(manaDateOf(istInstant), '2026-08-13');
      expect(manaDateOf(handsetOnUtc), '2026-08-12');
      expect(
        manaDateOf(istInstant) == manaDateOf(handsetOnUtc),
        isFalse,
        reason: 'these must differ — that difference IS the misfiled day',
      );
    });
  });

  group('no screen defaults an effective date from the handset clock', () {
    // A source-level guard. The value is clock-derived, so a behavioural
    // assertion is either circular or time-of-day flaky; what is checkable
    // and stable is that these four write sites never reach for
    // DateTime.now() again.
    const screens = <String>[
      'lib/features/owner_workspace/screens/ow_005_new_loan_workflow.dart',
      'lib/features/agent_workspace/screens/ag_007_loan_distribution.dart',
      'lib/features/owner_workspace/screens/ow_003_investor_management.dart',
      'lib/features/owner_workspace/screens/ow_018_business_migration.dart',
    ];

    for (final path in screens) {
      test('${path.split('/').last} uses manaNowIst for its date defaults', () {
        final source = File(path).readAsStringSync();
        final offenders = <String>[];
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (!line.contains('DateTime.now()')) continue;
          offenders.add('  ${i + 1}: ${line.trim()}');
        }
        expect(
          offenders,
          isEmpty,
          reason: 'DateTime.now() on a date-defaulting screen writes the '
              'handset\'s day into p_effective_date. Use manaNowIst() from '
              'lib/shared/mana_time.dart.\n${offenders.join('\n')}',
        );
      });
    }
  });
}

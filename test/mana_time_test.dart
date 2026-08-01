import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_time.dart';

/// Guards the single clock the whole app writes with.
///
/// Every timestamp column in `public` is `timestamp without time zone` — a
/// naive wall clock. Such a column is only coherent if every writer agrees
/// which wall clock it means, and this app had two that did not: the database
/// default `now()` (UTC) and the client's `DateTime.now()` (IST on an Indian
/// phone). An audit row was observed stamped 5h21m in the future as a result.
void main() {
  group('manaNowIst', () {
    test('is UTC plus exactly 5:30', () {
      final utc = DateTime.now().toUtc();
      final ist = manaNowIst();

      // Compare as naive wall clocks. A tolerance absorbs the microseconds
      // between the two calls; anything larger means the offset is wrong.
      final naiveUtc =
          DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
      final delta = ist.difference(naiveUtc);

      expect((delta - kIstOffset).abs(), lessThan(const Duration(seconds: 5)));
    });

    test('is not flagged as UTC, so it serialises without a Z suffix', () {
      // A DateTime carrying IST components but marked isUtc would emit a
      // trailing "Z", claiming the IST wall clock is a UTC instant — the
      // value would then be read back 5.5 hours off.
      expect(manaNowIst().isUtc, isFalse);
      expect(manaTimestamp(), isNot(endsWith('Z')));
      expect(manaTimestamp(), isNot(contains('+')));
    });

    test('India has no DST, so the offset is a constant', () {
      // Documents why a fixed offset is legitimate here and would be a bug
      // almost anywhere else.
      expect(kIstOffset, const Duration(hours: 5, minutes: 30));
    });
  });

  group('manaTimestamp', () {
    test('round-trips through DateTime.parse unchanged', () {
      // PostgREST sends this string straight into a naive column, and the app
      // parses it back with DateTime.parse. Both directions must agree.
      final s = manaTimestamp();
      final parsed = DateTime.parse(s);

      expect(parsed.isUtc, isFalse);
      expect(parsed.toIso8601String(), s);
    });

    test('does not depend on the device clock being set to IST', () {
      // THE POINT OF THE HELPER. The offset is derived from UTC, never read
      // from the handset, so a phone with a wrong timezone cannot shift the
      // value it writes. DateTime.now().toUtc() is correct on any correctly
      // *timed* device regardless of which zone it believes it is in.
      final fromUtc = DateTime.now().toUtc().add(kIstOffset);
      final ist = manaNowIst();

      expect(
        ist.difference(DateTime(fromUtc.year, fromUtc.month, fromUtc.day,
                fromUtc.hour, fromUtc.minute, fromUtc.second))
            .abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });
  });

  group('manaTimestampPlus', () {
    test('adds the requested duration to the IST clock', () {
      final base = DateTime.parse(manaTimestamp());
      final later = DateTime.parse(manaTimestampPlus(const Duration(hours: 24)));
      final delta = later.difference(base);

      // The 24h lending cooldown. Written with the old UTC/IST mix this guard
      // actually ran about 29.5 hours.
      expect((delta - const Duration(hours: 24)).abs(),
          lessThan(const Duration(seconds: 5)));
    });

    test('stays naive so it compares correctly against a stored value', () {
      expect(DateTime.parse(manaTimestampPlus(const Duration(hours: 24))).isUtc,
          isFalse);
    });
  });

  group('manaBusinessDate', () {
    test('is the IST calendar day, not the UTC one', () {
      expect(manaBusinessDate(), manaDateOf(manaNowIst()));
      expect(manaBusinessDate(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('agrees with the date half of manaTimestamp', () {
      // business_date and the timestamps must never disagree about which day
      // it is, or money files against one day's ledger with another day's
      // audit trail.
      expect(manaTimestamp().split('T').first, manaBusinessDate());
    });

    test('a late-evening IST instant stays on the Indian day', () {
      // The failure this prevents: 00:30 IST on 2 Aug is still 19:00 UTC on
      // 1 Aug. Deriving business_date from UTC would file that collection
      // against the previous business day.
      final lateIst = DateTime(2026, 8, 2, 0, 30);
      expect(manaDateOf(lateIst), '2026-08-02');

      final asUtc = lateIst.subtract(kIstOffset);
      expect(manaDateOf(asUtc), '2026-08-01',
          reason: 'demonstrates the bug that using UTC here would reintroduce');
    });

    test('pads single-digit months and days', () {
      expect(manaDateOf(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });
}

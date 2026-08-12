/// One clock for the whole app: IST.
///
/// WHY THIS EXISTS: every timestamp column in `public` is
/// `timestamp without time zone` - a naive wall clock with no offset stored.
/// A naive column is only coherent if every writer agrees on which wall clock
/// it means, and this app had two writers that did not:
///
///   * the database default `now()`, which under a UTC session stored a UTC
///     wall clock;
///   * the Flutter client, which called `DateTime.now()` and serialised it
///     with `toIso8601String()`. On an Indian handset that emits an IST wall
///     clock with no offset suffix at all.
///
/// Nothing errored. `agent_permissions.updated_at` was observed reading
/// 2026-08-01 04:51 while the database clock read 2026-07-31 23:29 UTC - an
/// audit row stamped five and a half hours into the future.
///
/// The database side is fixed in migration
/// 20260731233608_store_all_timestamps_in_ist.sql, which sets the database
/// TimeZone to Asia/Kolkata so every `now()` default stores IST.
///
/// This file fixes the client side. Note that on a correctly-configured Indian
/// phone the old code ALREADY produced IST, so this is not what repairs the
/// observed bug - it is what stops a handset with a wrong timezone (a factory
/// reset, a phone carried abroad, a device whose clock never synced) from
/// silently writing money rows onto the wrong business day. The offset is
/// computed from UTC rather than read from the device, so the handset's own
/// timezone setting cannot influence the result.
///
/// India is UTC+05:30 year-round with no daylight saving, which is what makes
/// a fixed offset correct here and would make it wrong almost anywhere else.
library;

/// India Standard Time. Fixed - India has never observed DST.
const Duration kIstOffset = Duration(hours: 5, minutes: 30);

/// The current IST wall clock, as a timezone-naive [DateTime].
///
/// Returned deliberately as a NON-utc DateTime carrying IST components, so
/// [DateTime.toIso8601String] emits no `Z` suffix and no offset - matching the
/// `timestamp without time zone` columns it is written into.
DateTime manaNowIst() {
  final ist = DateTime.now().toUtc().add(kIstOffset);
  return DateTime(
    ist.year,
    ist.month,
    ist.day,
    ist.hour,
    ist.minute,
    ist.second,
    ist.millisecond,
  );
}

/// The value to write into any `timestamp without time zone` column. This is
/// the replacement for serialising a bare `DateTime.now()` at a write site.
String manaTimestamp() => manaNowIst().toIso8601String();

/// [manaTimestamp] shifted by [d] - for deadlines such as
/// `loan_requests.cooldown_until`, which is a 24h lending guard. Written with
/// the old UTC/IST mix that guard actually ran about 29.5 hours.
String manaTimestampPlus(Duration d) => manaNowIst().add(d).toIso8601String();

/// Today's business date in IST, as `yyyy-MM-dd`.
///
/// This is the Indian calendar day, and that is deliberate: a collection taken
/// at 00:30 IST belongs to that Indian business day, not to the previous UTC
/// day. Deriving `business_date` from UTC would file money against the wrong
/// day's ledger - which is why the date columns were already correct while the
/// timestamps were not, and why they must NOT be "fixed" to match UTC.
String manaBusinessDate() => manaDateOf(manaNowIst());

/// The `yyyy-MM-dd` form of [when], for a date already in IST.
String manaDateOf(DateTime when) {
  final y = when.year.toString().padLeft(4, '0');
  final m = when.month.toString().padLeft(2, '0');
  final d = when.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Today in IST as `dd-mm-yyyy` — the form the app header shows.
///
/// Deliberately separate from [manaBusinessDate]: that one is `yyyy-MM-dd`
/// because it is written into `date` columns, and this one is for reading on
/// a screen. Never send this to the database.
String manaDisplayDate([DateTime? when]) {
  final t = when ?? manaNowIst();
  final d = t.day.toString().padLeft(2, '0');
  final m = t.month.toString().padLeft(2, '0');
  return '$d-$m-${t.year.toString().padLeft(4, '0')}';
}

/// Short IST weekday — `Sun`, `Mon`, …
///
/// Hand-built from [DateTime.weekday] rather than taken from `DateFormat`,
/// for the same reason as everything else in this file: it has to describe
/// the IST day, and DateFormat would describe the handset's.
const _manaWeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String manaWeekday([DateTime? when]) =>
    _manaWeekdayNames[(when ?? manaNowIst()).weekday - 1];

/// `Sun, 09-08-2026` — the weekday in front of the date.
String manaDisplayDateWithWeekday([DateTime? when]) {
  final t = when ?? manaNowIst();
  return '${manaWeekday(t)}, ${manaDisplayDate(t)}';
}

/// The IST wall clock as 12-hour `h:mm AM/PM`, for display only.
///
/// Built from [manaNowIst] rather than `TimeOfDay.format` or `DateTime.now`,
/// so a handset on the wrong timezone shows the same time as the one the
/// database is stamping rows with. A header clock that disagrees with the
/// business day would be read as the app being wrong about the day.
String manaClock12([DateTime? when]) {
  final t = when ?? manaNowIst();
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  // 00:xx is 12 AM and 12:xx is 12 PM — a bare `hour % 12` renders both as 0.
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h12:${t.minute.toString().padLeft(2, '0')} $suffix';
}

/// The same clock with seconds — `h:mm:ss AM/PM`.
///
/// Only for the drawer, which ticks once a second while it is open. Every
/// other clock in the app deliberately stops at minutes: a seconds field
/// that does not move looks broken, and one that does move costs a rebuild
/// per second on a screen nobody is reading the seconds off.
String manaClock12WithSeconds([DateTime? when]) {
  final t = when ?? manaNowIst();
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  final ss = t.second.toString().padLeft(2, '0');
  return '$h12:$mm:$ss $suffix';
}

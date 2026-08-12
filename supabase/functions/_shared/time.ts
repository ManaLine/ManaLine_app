// MANA LINE — shared IST (India Standard Time) helpers for Edge Functions.
//
// WHY THIS EXISTS: every timestamp column in the database is
// `timestamp without time zone` and MEANS IST (the database TimeZone is
// set to Asia/Kolkata). But `new Date().toISOString()` emits UTC — a naive
// IST timestamp stored via an ISO string is silently stored as UTC,
// creating a 5.5-hour skew against every `now()` default in the same
// schema. This caused audit-row skew on first-login timestamps and a 5.5 h
// inflation of OTP expiry windows.
//
// India has no DST. A fixed +05:30 offset is correct forever. These helpers
// mirror the Dart side's `lib/shared/mana_time.dart` (same logic, same
// constant) so both layers agree.

export const IST_OFFSET_MS = 5.5 * 3600 * 1000;

/** IST wall-clock as a naive string ("YYYY-MM-DD HH:MM:SS"), no zone suffix. */
export function istNow(): string {
  return new Date(Date.now() + IST_OFFSET_MS)
    .toISOString()
    .slice(0, 19)
    .replace("T", " ");
}

/** IST date only ("YYYY-MM-DD"). */
export function istDate(): string {
  return istNow().slice(0, 10);
}

/** Parse a naive IST timestamp string into a real JS Date (epoch). */
export function parseIst(naive: string): Date {
  return new Date(naive.replace(" ", "T") + "+05:30");
}

/**
 * The IST wall clock [ms] milliseconds ago, in the same naive form as
 * [istNow] — the correct cutoff for any comparison against a naive IST
 * timestamp column.
 *
 * WHY THIS EXISTS: `new Date(Date.now() - ms).toISOString()` looks like a
 * cutoff and is not. It emits UTC, and Postgres casting it to `timestamp
 * without time zone` DISCARDS the trailing `Z` — so a UTC wall clock gets
 * compared as though it were IST, 5h30m adrift. Against auth_rate_limits
 * (bucket_ts defaults to now() under an Asia/Kolkata database, i.e. IST)
 * that inflated every rate-limit window by 5h30m: the 5-minute login
 * throttle held for 5h35m, the 15-minute BR-201 lockout cooldown for 5h45m,
 * and the pruning half of the same comparison never deleted anything, so the
 * table only grew. Nothing errored — every layer did exactly what it said.
 */
export function istAgo(ms: number): string {
  return new Date(Date.now() + IST_OFFSET_MS - ms)
    .toISOString()
    .slice(0, 19)
    .replace("T", " ");
}

// MANA LINE — input validators shared between Edge Functions and their tests.
//
// WHY THIS FILE EXISTS: validators living inside an `index.ts` cannot be unit
// tested, because importing that module executes its `Deno.serve` call. Any
// validator worth asserting on belongs here.

import { istDate } from "./time.ts";

/**
 * A `YYYY-MM-DD` date that is real, in the past, and not absurd.
 *
 * Deliberately NO minimum-age rule. Nobody has stated one for this app, and
 * inventing an 18+ gate here would silently reject registrations the business
 * may well intend to accept. Add one only when that rule actually exists.
 *
 * "Today" is the IST business day (istDate), matching lib/shared/mana_time.dart.
 * Reckoned in UTC instead, a birth date entered as "today" in India would read
 * as a future date for five and a half hours out of every day and be rejected.
 */
export function isValidDob(v: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return false;
  const d = new Date(v + "T00:00:00Z");
  if (Number.isNaN(d.getTime())) return false;
  // Round-trip guards against real-looking but invalid dates: JS rolls
  // 2026-02-31 forward to 2026-03-03 rather than rejecting it.
  if (d.toISOString().slice(0, 10) !== v) return false;
  const istToday = istDate();
  if (v > istToday) return false;
  const year = Number(v.slice(0, 4));
  return year >= Number(istToday.slice(0, 4)) - 120;
}

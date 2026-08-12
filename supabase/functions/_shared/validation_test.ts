// Unit tests for the registration validators.
//
// DOB is mandatory at registration but persons.dob is still a nullable column
// (every pre-existing row has a null dob, so NOT NULL would need a backfill
// nobody can supply). That makes this function the actual enforcement point,
// which is worth pinning.
//
// Dependency-free, like _shared/time_test.ts, so the suite runs offline.

import { isValidDob } from "./validation.ts";
import { istDate } from "./time.ts";

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

Deno.test("accepts an ordinary past date", () => {
  assert(isValidDob("1990-04-17"), "1990-04-17 should be valid");
  assert(isValidDob("1948-01-01"), "1948-01-01 should be valid");
});

Deno.test("accepts today in IST", () => {
  // A birth date of today is odd but not invalid, and must not be rejected
  // just because UTC has not reached the same calendar day yet.
  assert(isValidDob(istDate()), `today (${istDate()}) should be valid`);
});

Deno.test("rejects a future date", () => {
  const nextYear = String(Number(istDate().slice(0, 4)) + 1) + istDate().slice(4);
  assert(!isValidDob(nextYear), `${nextYear} is in the future and must be rejected`);
});

Deno.test("rejects a date that looks real but is not", () => {
  // JS rolls this forward to 2026-03-03 rather than failing; the round-trip
  // check is what catches it.
  assert(!isValidDob("2026-02-31"), "2026-02-31 does not exist");
  assert(!isValidDob("1990-13-01"), "month 13 does not exist");
  assert(!isValidDob("1990-00-10"), "month 00 does not exist");
});

Deno.test("rejects anything that is not YYYY-MM-DD", () => {
  for (const bad of ["", "  ", "17-04-1990", "1990/04/17", "1990-4-7", "not a date", "1990-04-17T00:00:00Z"]) {
    assert(!isValidDob(bad), `"${bad}" should be rejected`);
  }
});

Deno.test("rejects an implausibly old date", () => {
  const tooOld = String(Number(istDate().slice(0, 4)) - 121) + "-01-01";
  assert(!isValidDob(tooOld), `${tooOld} is over 120 years ago`);
  const justInside = String(Number(istDate().slice(0, 4)) - 119) + "-01-01";
  assert(isValidDob(justInside), `${justInside} is within 120 years and should pass`);
});

Deno.test("no minimum-age rule is enforced", () => {
  // Documents the deliberate absence rather than leaving it to be rediscovered:
  // a 5-year-old passes validation today. If an 18+ rule is ever introduced,
  // this test should fail and be replaced.
  const fiveYearsAgo = String(Number(istDate().slice(0, 4)) - 5) + "-06-15";
  assert(isValidDob(fiveYearsAgo), "no age gate exists, so this must pass");
});

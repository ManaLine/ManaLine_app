// Unit tests for the IST helpers.
//
// WHY THESE EXIST: the auth rate limiter shipped a cutoff built with
// `new Date(Date.now() - windowMs).toISOString()`. That is a UTC wall clock,
// and `auth_rate_limits.bucket_ts` is a naive timestamp defaulted from now()
// under an Asia/Kolkata database — i.e. IST. Postgres casting the string to
// `timestamp without time zone` DISCARDS the trailing `Z`, so the two were
// compared as if both were IST and every rate-limit window silently ran
// 5h30m long. Nothing threw; the types matched; the code read correctly.
//
// The invariant worth pinning is therefore not "istAgo returns a string" but
// "a cutoff, parsed back the way the database reads it, lands on the instant
// we meant". `roundTrips` below is the test the old code would have failed.
//
// Deliberately dependency-free — no jsr:/npm: imports — so the suite runs
// offline and adds no supply chain to a repo whose other Deno code is
// deployed straight to prod.

import { IST_OFFSET_MS, istAgo, istDate, istNow, parseIst } from "./time.ts";

const NAIVE = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertNear(actualMs: number, expectedMs: number, toleranceMs: number, msg: string): void {
  const drift = Math.abs(actualMs - expectedMs);
  if (drift > toleranceMs) {
    throw new Error(`${msg}: off by ${drift}ms (tolerance ${toleranceMs}ms)`);
  }
}

Deno.test("istNow emits a naive timestamp with no zone marker", () => {
  const s = istNow();
  assert(NAIVE.test(s), `istNow() must match "YYYY-MM-DD HH:MM:SS", got "${s}"`);
  assert(!s.includes("Z") && !s.includes("T"), `istNow() must carry no zone suffix, got "${s}"`);
});

Deno.test("istAgo emits the same naive shape as istNow", () => {
  const s = istAgo(5 * 60 * 1000);
  assert(NAIVE.test(s), `istAgo() must match "YYYY-MM-DD HH:MM:SS", got "${s}"`);
  assert(!s.includes("Z") && !s.includes("T"), `istAgo() must carry no zone suffix, got "${s}"`);
});

Deno.test("istAgo(0) is istNow", () => {
  assertNear(
    parseIst(istAgo(0)).getTime(),
    parseIst(istNow()).getTime(),
    1000,
    "istAgo(0) should equal istNow to the second",
  );
});

Deno.test("istAgo round-trips to the intended instant (the rate-limiter bug)", () => {
  for (const windowMs of [5 * 60 * 1000, 10 * 60 * 1000, 15 * 60 * 1000]) {
    const before = Date.now();
    const cutoff = parseIst(istAgo(windowMs)).getTime();
    // Read back the way the database reads it, the cutoff must be exactly
    // `windowMs` in the past — not windowMs + 5h30m.
    assertNear(cutoff, before - windowMs, 1500, `istAgo(${windowMs}) round-trip`);
  }
});

Deno.test("the old UTC cutoff is 5h30m adrift — regression guard", () => {
  const windowMs = 5 * 60 * 1000;
  // Exactly what the limiter used to compute.
  const legacy = new Date(Date.now() - windowMs).toISOString().slice(0, 19).replace("T", " ");
  const skewMs = parseIst(istAgo(windowMs)).getTime() - parseIst(legacy).getTime();
  // The legacy string is a UTC wall clock, but the database reads bucket_ts as
  // IST — so it resolves to an instant IST_OFFSET_MS EARLIER than intended,
  // reaching that much further back and sweeping in rows outside the window.
  // A positive skew here is the whole defect: 5h30m of extra reach.
  assertNear(skewMs, IST_OFFSET_MS, 1500, "legacy cutoff should reach 5h30m further back");
  assert(
    IST_OFFSET_MS === 5.5 * 3600 * 1000,
    "IST is UTC+05:30 year-round; changing this constant changes every auth window",
  );
});

Deno.test("istAgo stays consistent with istDate across a window", () => {
  // Same instant, so the date component cannot disagree.
  assert(
    istAgo(0).slice(0, 10) === istDate(),
    `istAgo(0) date "${istAgo(0).slice(0, 10)}" must equal istDate() "${istDate()}"`,
  );
});

Deno.test("a longer window moves the cutoff further back, monotonically", () => {
  const five = parseIst(istAgo(5 * 60 * 1000)).getTime();
  const fifteen = parseIst(istAgo(15 * 60 * 1000)).getTime();
  assert(fifteen < five, "a 15-minute window must reach further back than a 5-minute one");
  assertNear(five - fifteen, 10 * 60 * 1000, 1500, "the gap should be exactly 10 minutes");
});

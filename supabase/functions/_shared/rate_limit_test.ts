// Unit tests for the rate-limit helpers.
//
// WHY THESE EXIST: admin-login used rateLimit() as its lockout counter.
// rateLimit() checks AND records, and it ran before the password was ever
// compared — so successful logins filled the same bucket as failed ones. Five
// correct logins in fifteen minutes locked the only platform admin out of
// their own account, with an error that said "too many failed attempts" when
// none had failed. Nothing threw. The bucket key said "lockout" and the code
// read correctly.
//
// The invariant worth pinning is therefore not "rateLimit returns a boolean"
// but "checking does not record" — so a caller can count only the outcomes it
// means to count.
//
// Unlike time_test.ts these are NOT dependency-free: driving the real helpers
// means loading supabaseAdmin, which imports supabase-js from npm. They stub
// fetch rather than reaching the network, so the only requirement is a warm
// Deno module cache.

import { rateLimit, rateLimitCheck, rateLimitRecord } from "./rate_limit.ts";

Deno.env.set("SUPABASE_URL", "http://rate-limit-test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");

interface Call {
  method: string;
  url: string;
}

/// Runs `fn` with fetch stubbed, returning every PostgREST call it made.
/// `count` is what the stub reports as the current row count for the bucket.
async function record(count: number, fn: () => Promise<unknown>): Promise<Call[]> {
  const calls: Call[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : input.toString();
    const method = (input instanceof Request ? input.method : init?.method) ?? "GET";
    calls.push({ method, url });
    // PostgREST reports an exact count in Content-Range for head:true selects.
    return Promise.resolve(
      new Response(null, {
        status: 200,
        headers: { "content-range": `0-0/${count}` },
      }),
    );
  }) as typeof fetch;
  try {
    await fn();
  } finally {
    globalThis.fetch = realFetch;
  }
  return calls;
}

const inserts = (calls: Call[]) => calls.filter((c) => c.method === "POST");

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

Deno.test("rateLimitCheck does not record the call", async () => {
  const calls = await record(0, () => rateLimitCheck("bucket", 5, 60_000));
  assert(
    inserts(calls).length === 0,
    `checking must not write a row; saw ${inserts(calls).length} insert(s)`,
  );
});

Deno.test("rateLimit does record the call", async () => {
  const calls = await record(0, () => rateLimit("bucket", 5, 60_000));
  assert(inserts(calls).length === 1, "rateLimit must record the call it allowed");
});

Deno.test("rateLimit at the limit rejects and records nothing", async () => {
  const calls = await record(5, async () => {
    const allowed = await rateLimit("bucket", 5, 60_000);
    assert(allowed === false, "a full bucket must reject");
  });
  assert(inserts(calls).length === 0, "a rejected call must not extend the window");
});

Deno.test("rateLimitRecord writes exactly one row", async () => {
  const calls = await record(0, () => rateLimitRecord("bucket"));
  assert(inserts(calls).length === 1, "record must write one row");
  assert(calls.length === 1, "record must not also prune or count");
});

/// A fetch stub with memory: the count it reports is the number of rows the
/// caller has actually inserted. Needed for the regression test below —
/// against a fixed count, check-and-record and check-only look identical.
async function withStatefulStub(fn: () => Promise<void>): Promise<void> {
  let rows = 0;
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const method = (input instanceof Request ? input.method : init?.method) ?? "GET";
    if (method === "POST") rows++;
    return Promise.resolve(
      new Response(null, { status: 200, headers: { "content-range": `0-0/${rows}` } }),
    );
  }) as typeof fetch;
  try {
    await fn();
  } finally {
    globalThis.fetch = realFetch;
  }
}

// The regression itself, in the shape admin-login uses: a SUCCESSFUL login
// checks the lockout bucket and never records, so the sixth still gets
// through. Against the old code — which called rateLimit(), recording every
// attempt before the password was compared — login six is refused.
Deno.test("six successful logins in a row do not lock the account", async () => {
  await withStatefulStub(async () => {
    for (let i = 1; i <= 6; i++) {
      const allowed = await rateLimitCheck("admin-lockout:someone", 5, 900_000);
      assert(allowed === true, `login ${i} was locked out after ${i - 1} SUCCESSFUL logins`);
      // Success path: nothing recorded. Only genericFailure() calls
      // rateLimitRecord.
    }
  });
});

// The other half: failures do still accumulate to a lockout.
Deno.test("five failed logins do lock the account", async () => {
  await withStatefulStub(async () => {
    for (let i = 1; i <= 5; i++) {
      assert(
        await rateLimitCheck("admin-lockout:someone", 5, 900_000),
        `attempt ${i} should still be allowed through to the password compare`,
      );
      await rateLimitRecord("admin-lockout:someone"); // wrong password
    }
    assert(
      (await rateLimitCheck("admin-lockout:someone", 5, 900_000)) === false,
      "the sixth attempt after five failures must be locked out",
    );
  });
});

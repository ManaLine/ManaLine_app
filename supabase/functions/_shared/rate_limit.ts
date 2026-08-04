// MANA LINE — advisory rate-limit helper for Edge Functions.
//
// HOW IT WORKS:
//   1. Delete all rows in the bucket older than the window.
//   2. Count remaining rows — if at or above the limit, REJECT.
//   3. Otherwise insert one new row for this call.
//
// The table's PK is (bucket_key, bucket_ts) with BIGSERIAL, so concurrent
// inserts never collide. It is NOT atomic for the count+insert step — two
// simultaneous requests could both see count=4 when limit=5 and both insert,
// landing at 6. This is acceptable for auth rate limiting: the goal is
// "hard to brute-force at scale", not "zero overages". A hardened solution
// would use SELECT FOR UPDATE (expensive for advisory) or Redis (external
// infra). For now the row-count approach is sufficient and needs no new
// services.
//
// Cleanup: old rows are deleted on each call so the table stays small.

import { supabaseAdmin } from "./supabaseAdmin.ts";

export async function rateLimit(
  bucketKey: string,
  limit: number,
  windowMs: number = 5 * 60 * 1000
): Promise<boolean> {
  const admin = supabaseAdmin();
  const cutoff = new Date(Date.now() - windowMs).toISOString();

  // Prune stale rows for this bucket.
  await admin
    .from("auth_rate_limits")
    .delete()
    .eq("bucket_key", bucketKey)
    .lt("bucket_ts", cutoff);

  // Count remaining (within the window).
  const { count, error } = await admin
    .from("auth_rate_limits")
    .select("bucket_key", { count: "exact", head: true })
    .eq("bucket_key", bucketKey)
    .gt("bucket_ts", cutoff);

  if (error) {
    // If the table isn't deployed yet (e.g. migration not applied), fail open
    // — a misconfigured rate-limit table should not block all logins.
    console.error("rateLimit query failed (failing open)", error);
    return true;
  }
  if ((count ?? 0) >= limit) return false; // rate-limited

  // Record this call.
  await admin.from("auth_rate_limits").insert({ bucket_key: bucketKey });
  return true;
}

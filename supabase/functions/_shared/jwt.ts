// MANA LINE — custom JWT minting for the `persons`-based auth layer.
//
// WHY A CUSTOM JWT (not a GoTrue session): `persons` (not `auth.users`) is
// the sole identity source of truth (see auth_api_service.dart's
// architectural note #1/#3). 0012_rls_module0_identity.sql's
// app.current_person_id() resolves the caller via:
//
//   SELECT NULLIF(current_setting('request.jwt.claims', true)::json
//                 ->> 'person_id', '')::BIGINT;
//
// i.e. it reads a `person_id` claim straight out of the JWT that PostgREST/
// Realtime already decode on every request — it does NOT look up
// auth.uid(). So the only requirement on this token is:
//   1. Signed with the project's real JWT secret (PERSON_JWT_SIGNING_SECRET,
//      using the value from Project Settings → API → JWT Keys → Legacy JWT
//      Secret — NOT named SUPABASE_JWT_SECRET: the Supabase CLI reserves
//      the entire SUPABASE_ prefix for platform-injected secrets and
//      silently refuses to set anything under that prefix, confirmed via
//      `supabase secrets set SUPABASE_JWT_SECRET=...` → "Env name cannot
//      start with SUPABASE_, skipping". Renamed here to a non-reserved
//      name so it can actually be set.
//      so PostgREST's own verification (which happens independently of
///     this function) accepts it.
//   2. `role: "authenticated"` — PostgREST switches Postgres role based on
//      this claim; without it, requests fall back to `anon` and every RLS
//      policy in this project (all written against `authenticated`-role
//      access, gated further by app.current_person_id()) will not resolve
//      the caller at all.
//   3. A `person_id` claim carrying persons.person_id as a string (JSON
//      numbers over ~2^53 lose precision — person_id is BIGINT — so this
//      is passed as a string and cast with ::BIGINT on the Postgres side,
//      exactly as app.current_person_id() already does with NULLIF(...)::BIGINT).
//
// PERSON_JWT_SIGNING_SECRET is a project Edge Function secret — set it
// manually via `supabase secrets set PERSON_JWT_SIGNING_SECRET=<value>`,
// using the "Legacy JWT secret" value from Project Settings → API →
// JWT Keys → Legacy JWT Secret tab (NOT the newer ECC signing key — that
// value is still what PostgREST verifies anon/service_role-style JWTs
// against, per Supabase's own migration notice on that page).
import * as djwt from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const ACCESS_TOKEN_TTL_SECONDS = 60 * 60; // 1 hour. Not specified anywhere
// in the reference material — flagged as an assumption in END RESULT.
// Session refresh strategy (silent refresh vs re-login) is out of scope
// for this Edge Function batch.

let cachedKey: CryptoKey | null = null;

async function getSigningKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;
  const secret = Deno.env.get("PERSON_JWT_SIGNING_SECRET");
  if (!secret) {
    throw new Error("Missing PERSON_JWT_SIGNING_SECRET in function environment");
  }
  cachedKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  return cachedKey;
}

export async function mintPersonJwt(personId: number | string): Promise<string> {
  const key = await getSigningKey();
  const now = Math.floor(Date.now() / 1000);
  return await djwt.create(
    { alg: "HS256", typ: "JWT" },
    {
      role: "authenticated",
      aud: "authenticated",
      sub: String(personId),
      person_id: String(personId),
      iat: now,
      exp: now + ACCESS_TOKEN_TTL_SECONDS,
    },
    key,
  );
}

/** Verifies+decodes a bearer token issued by mintPersonJwt (used by
 * functions like auth-pin-create that require an already-authenticated
 * caller). Throws on invalid/expired tokens. */
export async function verifyPersonJwt(
  token: string,
): Promise<{ person_id: string }> {
  const key = await getSigningKey();
  const payload = await djwt.verify(token, key);
  if (!payload.person_id || typeof payload.person_id !== "string") {
    throw new Error("Token missing person_id claim");
  }
  return { person_id: payload.person_id };
}

export function extractBearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  return header.slice("Bearer ".length).trim();
}

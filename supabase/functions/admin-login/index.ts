// MANA LINE — POST /admin/login
//
// Platform Admin login. Completely separate from auth-login: validates
// username+password against admin_accounts (not persons), mints a JWT
// carrying an `admin_id` claim (not `person_id`) via mintAdminJwt, and
// never touches the persons/devices/single-device-policy machinery — an
// admin session is a different trust domain, not a business user's
// session.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret } from "../_shared/hashing.ts";
import { mintAdminJwt } from "../_shared/jwt.ts";
import { rateLimit } from "../_shared/rate_limit.ts";

const LOGIN_RATE_LIMIT = 10; // per (username, IP) per 5 min
const LOCKOUT_RATE_LIMIT = 5; // failed attempts per username per 15 min before lockout
const LOCKOUT_WINDOW_MS = 15 * 60 * 1000;

interface Body {
  username: string;
  password: string;
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  try {
    let body: Body;
    try {
      body = await req.json();
    } catch {
      return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
    }

    if (!body.username?.trim() || !body.password) {
      return errorResponse(400, "VALIDATION_ERROR", "username and password are required.");
    }

    const admin = supabaseAdmin();
    const username = body.username.trim();

    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
    if (!(await rateLimit(`admin-login:${username}:${clientIp}`, LOGIN_RATE_LIMIT, 5 * 60 * 1000))) {
      return errorResponse(429, "RATE_LIMITED", "Too many login attempts. Please try again later.");
    }

    // Lockout after too many recent wrong-password calls for this username,
    // same shape as auth-login's cooldown but keyed on a rolling count
    // rather than a separate attempts column (admin_accounts has none —
    // this is a low-volume, single-admin table, an extra column is not
    // worth it; the rate-limit bucket already gives the same protection).
    if (!(await rateLimit(`admin-lockout:${username}`, LOCKOUT_RATE_LIMIT, LOCKOUT_WINDOW_MS))) {
      return errorResponse(403, "ACCOUNT_LOCKED", "Too many failed attempts. Try again in a few minutes.");
    }

    const genericFailure = () =>
      jsonResponse({
        data: { success: false, token: null, admin_id: null },
        meta: {},
        errors: [{ code: "UNAUTHENTICATED", message: "Invalid username or password." }],
      });

    const { data: account, error: lookupError } = await admin
      .from("admin_accounts")
      .select("admin_id, password_hash")
      .eq("username", username)
      .maybeSingle();

    if (lookupError) {
      console.error("admin-login lookup failed", lookupError);
      return errorResponse(500, "INTERNAL_ERROR", "Login failed.");
    }
    if (!account) return genericFailure();

    const ok = await compareSecret(body.password, account.password_hash);
    if (!ok) return genericFailure();

    const token = await mintAdminJwt(account.admin_id);

    return jsonResponse({
      data: { success: true, token, admin_id: account.admin_id },
      meta: {},
      errors: [],
    });
  } catch (err) {
    console.error("admin-login unhandled error", err);
    return errorResponse(500, "INTERNAL_ERROR", "Login failed. Please try again.");
  }
});

// MANA LINE — POST /admin/password/reset-request
//
// Same identical-response-regardless-of-outcome contract as
// auth-password-reset-request (never confirm/deny whether a username
// exists), but looks up admin_accounts and sends the OTP to
// recovery_mobile_number, writing to admin_otp_verifications — the
// isolated admin OTP table (otp_verifications.person_id is NOT NULL, and
// an admin account has no person_id to put there).
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { generateOtpCode, hashSecret } from "../_shared/hashing.ts";
import { rateLimit } from "../_shared/rate_limit.ts";

interface Body {
  username: string;
}

const REQUEST_RATE_LIMIT = 5; // per username per 10 min — a reset flow, not a login, needs less headroom

async function sendSmsStub(mobileNumber: string, code: string): Promise<void> {
  console.log(`[STUB] Would send admin password-reset OTP ${code} to ${mobileNumber}`);
}

const DUMMY_OTP_ID = "00000000-0000-0000-0000-000000000000";

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
    if (!body.username?.trim()) {
      return errorResponse(400, "VALIDATION_ERROR", "username is required.");
    }

    const admin = supabaseAdmin();
    const username = body.username.trim();

    if (!(await rateLimit(`admin-reset-request:${username}`, REQUEST_RATE_LIMIT, 10 * 60 * 1000))) {
      return errorResponse(429, "RATE_LIMITED", "Too many reset attempts. Please try again later.");
    }

    const { data: account } = await admin
      .from("admin_accounts")
      .select("admin_id, recovery_mobile_number")
      .eq("username", username)
      .maybeSingle();

    // Same identical-response contract as auth-password-reset-request:
    // never reveal whether the username matched.
    if (!account) {
      return jsonResponse({ data: { otp_id: DUMMY_OTP_ID }, meta: {}, errors: [] });
    }

    const code = generateOtpCode();
    const codeHash = await hashSecret(code);
    const { data: otpRow, error: insertError } = await admin
      .from("admin_otp_verifications")
      .insert({
        admin_id: account.admin_id,
        purpose: "Password Reset",
        otp_code_hash: codeHash,
        status: "Sent",
      })
      .select("otp_id")
      .single();

    if (insertError || !otpRow) {
      console.error("admin-password-reset-request insert failed", insertError);
      return jsonResponse({ data: { otp_id: DUMMY_OTP_ID }, meta: {}, errors: [] });
    }

    try {
      await sendSmsStub(account.recovery_mobile_number, code);
    } catch (e) {
      console.error("admin-password-reset-request SMS stub failed", e);
    }

    return jsonResponse({ data: { otp_id: otpRow.otp_id }, meta: {}, errors: [] });
  } catch (err) {
    console.error("admin-password-reset-request unhandled error", err);
    return errorResponse(500, "INTERNAL_ERROR", "Could not start password reset.");
  }
});

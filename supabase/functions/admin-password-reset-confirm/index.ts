// MANA LINE — POST /admin/password/reset-confirm
//
// Verifies the OTP sent to admin_accounts.recovery_mobile_number, then
// sets a new password_hash. Deliberately MORE strict than the person-side
// auth-password-reset-confirm: no "123456 always works" testing bypass —
// an admin account can delete anything, so this path gets real expiry
// (10 min) and a real wrong-guess rate limit instead of the convenience
// shortcut the person-side flow still carries.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret, hashSecret } from "../_shared/hashing.ts";
import { istNow, parseIst } from "../_shared/time.ts";
import { rateLimit } from "../_shared/rate_limit.ts";

interface Body {
  otp_id: string;
  code: string;
  new_password: string;
}

const OTP_EXPIRY_MINUTES = 10; // matches auth-otp-verify's window
const WRONG_GUESS_LIMIT = 5; // per otp_id per 10 min, same as auth-otp-verify

function isStrongEnough(pw: string): boolean {
  return pw.length >= 8;
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
    if (!body.otp_id || !body.code || !body.new_password) {
      return errorResponse(400, "VALIDATION_ERROR", "otp_id, code, and new_password are required.");
    }
    if (!isStrongEnough(body.new_password)) {
      return errorResponse(400, "VALIDATION_ERROR", "new_password must be at least 8 characters.");
    }

    const admin = supabaseAdmin();
    const { data: otpRow, error: lookupError } = await admin
      .from("admin_otp_verifications")
      .select("otp_id, admin_id, purpose, otp_code_hash, status, sent_at")
      .eq("otp_id", body.otp_id)
      .maybeSingle();

    if (lookupError) {
      console.error("admin-password-reset-confirm lookup failed", lookupError);
      return errorResponse(500, "INTERNAL_ERROR", "Could not reset password.");
    }
    if (!otpRow || otpRow.purpose !== "Password Reset") {
      return errorResponse(400, "VALIDATION_ERROR", "Invalid or unrelated otp_id.");
    }

    const ageMinutes = (Date.now() - parseIst(otpRow.sent_at).getTime()) / 60000;
    if (otpRow.status === "Expired" || ageMinutes > OTP_EXPIRY_MINUTES) {
      if (otpRow.status !== "Expired") {
        await admin.from("admin_otp_verifications").update({ status: "Expired" }).eq("otp_id", otpRow.otp_id);
      }
      return errorResponse(400, "VALIDATION_ERROR", "OTP has expired. Request a new one.");
    }
    if (otpRow.status === "Verified") {
      return errorResponse(400, "VALIDATION_ERROR", "This OTP was already used.");
    }

    if (!(await rateLimit(`admin-otp-verify:${otpRow.otp_id}`, WRONG_GUESS_LIMIT, 10 * 60 * 1000))) {
      await admin.from("admin_otp_verifications").update({ status: "Expired" }).eq("otp_id", otpRow.otp_id);
      return errorResponse(400, "VALIDATION_ERROR", "Too many incorrect attempts. Request a new OTP.");
    }

    const codeOk = await compareSecret(body.code, otpRow.otp_code_hash);
    if (!codeOk) {
      return errorResponse(400, "VALIDATION_ERROR", "Incorrect code.");
    }

    const newHash = await hashSecret(body.new_password);
    const { error: updateError } = await admin
      .from("admin_accounts")
      .update({ password_hash: newHash, updated_at: istNow() })
      .eq("admin_id", otpRow.admin_id);

    if (updateError) {
      console.error("admin-password-reset-confirm update failed", updateError);
      return errorResponse(500, "INTERNAL_ERROR", "Could not reset password.");
    }

    await admin
      .from("admin_otp_verifications")
      .update({ status: "Verified", verified_at: istNow() })
      .eq("otp_id", otpRow.otp_id);

    return jsonResponse({ data: { success: true }, meta: {}, errors: [] });
  } catch (err) {
    console.error("admin-password-reset-confirm unhandled error", err);
    return errorResponse(500, "INTERNAL_ERROR", "Could not reset password.");
  }
});

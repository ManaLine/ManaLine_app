// MANA LINE — POST /auth/password/reset-confirm (§1.3, paired with
// reset-request via otp_id). Runs as `anon` — the whole point of a
// password reset flow is the caller doesn't have valid credentials yet.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret, hashSecret } from "../_shared/hashing.ts";

interface Body {
  otp_id: string;
  code: string;
  new_password: string;
}

function isStrongEnough(pw: string): boolean {
  // Minimum bar not specified anywhere in the attached reference
  // material — flagged assumption in END RESULT. Using a conservative
  // baseline (8+ chars) rather than inventing a full policy silently.
  return pw.length >= 8;
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

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
    .from("otp_verifications")
    .select("otp_id, person_id, purpose, otp_code_hash, status, sent_at")
    .eq("otp_id", body.otp_id)
    .maybeSingle();

  if (lookupError) {
    console.error("auth-password-reset-confirm lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not reset password.");
  }
  if (!otpRow || otpRow.purpose !== "Password Reset") {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid or unrelated otp_id.");
  }
  if (otpRow.status === "Expired") {
    return errorResponse(400, "VALIDATION_ERROR", "OTP has expired. Request a new one.");
  }

  const codeOk = await compareSecret(body.code, otpRow.otp_code_hash);
  if (!codeOk) {
    return errorResponse(400, "VALIDATION_ERROR", "Incorrect code.");
  }

  const newHash = await hashSecret(body.new_password);
  const { error: updateError } = await admin
    .from("persons")
    .update({ password_hash: newHash, failed_password_attempts: 0 })
    .eq("person_id", otpRow.person_id);

  if (updateError) {
    console.error("auth-password-reset-confirm update failed", updateError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not reset password.");
  }

  await admin
    .from("otp_verifications")
    .update({ status: "Verified", verified_at: new Date().toISOString() })
    .eq("otp_id", otpRow.otp_id);

  return jsonResponse({ data: { success: true }, meta: {}, errors: [] });
});

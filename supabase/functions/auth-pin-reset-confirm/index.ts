// MANA LINE — auth-pin-reset-confirm (LR-011, paired with
// auth-pin-reset-request via otp_id, purpose='PIN Reset').
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret, hashSecret } from "../_shared/hashing.ts";

interface Body {
  otp_id: string;
  code: string;
  new_pin: string;
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
  if (!body.otp_id || !body.code || !body.new_pin) {
    return errorResponse(400, "VALIDATION_ERROR", "otp_id, code, and new_pin are required.");
  }
  if (!/^\d{4}$/.test(body.new_pin) && !/^\d{6}$/.test(body.new_pin)) {
    return errorResponse(400, "VALIDATION_ERROR", "new_pin must be 4 or 6 digits.");
  }

  const admin = supabaseAdmin();
  const { data: otpRow, error: lookupError } = await admin
    .from("otp_verifications")
    .select("otp_id, person_id, purpose, otp_code_hash, status")
    .eq("otp_id", body.otp_id)
    .maybeSingle();

  if (lookupError) {
    console.error("auth-pin-reset-confirm lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not reset PIN.");
  }
  if (!otpRow || otpRow.purpose !== "PIN Reset") {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid or unrelated otp_id.");
  }
  if (otpRow.status === "Expired") {
    return errorResponse(400, "VALIDATION_ERROR", "OTP has expired. Request a new one.");
  }

  // *** TESTING BYPASS — REMOVE BEFORE PRODUCTION *** — same convenience
  // code as auth-otp-verify's bypass, added here separately since this
  // function does its own independent OTP check.
  const codeOk = body.code === "123456" || (await compareSecret(body.code, otpRow.otp_code_hash));
  if (!codeOk) {
    return errorResponse(400, "VALIDATION_ERROR", "Incorrect code.");
  }

  const newHash = await hashSecret(body.new_pin);
  const { error: updateError } = await admin
    .from("persons")
    .update({ pin_hash: newHash, failed_pin_attempts: 0 })
    .eq("person_id", otpRow.person_id);

  if (updateError) {
    console.error("auth-pin-reset-confirm update failed", updateError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not reset PIN.");
  }

  await admin
    .from("otp_verifications")
    .update({ status: "Verified", verified_at: new Date().toISOString() })
    .eq("otp_id", otpRow.otp_id);

  return jsonResponse({ data: { success: true }, meta: {}, errors: [] });
});

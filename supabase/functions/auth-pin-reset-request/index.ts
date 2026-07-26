// MANA LINE — auth-pin-reset-request (LR-011).
//
// CONTRACT SOURCE NOTE: 04_API_Specification_v1_Part1.md §1.3 only says
// "POST /auth/pin/reset-request (same pattern)" — i.e. `{identifier}` like
// password-reset-request. auth_api_service.dart's pinResetRequest() sends
// `{person_id, password}` instead — password-gated, per its own doc
// comment "(password-gated, LR-011)". Per prompt §3, the Dart file wins:
// this function requires the caller to already know their password (proof
// of identity) rather than an anonymous identifier lookup, then issues an
// OTP (purpose='PIN Reset') as a second factor before pin-reset-confirm.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret, generateOtpCode, hashSecret } from "../_shared/hashing.ts";

interface Body {
  person_id: string | number;
  password: string;
}

async function sendSmsStub(mobileNumber: string, code: string): Promise<void> {
  console.log(`[STUB] Would send PIN-reset OTP ${code} to ${mobileNumber}`);
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
  if (!body.person_id || !body.password) {
    return errorResponse(400, "VALIDATION_ERROR", "person_id and password are required.");
  }

  const admin = supabaseAdmin();
  const { data: person, error: lookupError } = await admin
    .from("persons")
    .select("person_id, mobile_number, password_hash, failed_password_attempts")
    .eq("person_id", body.person_id)
    .maybeSingle();

  if (lookupError) {
    console.error("auth-pin-reset-request lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not process request.");
  }
  if (!person) {
    return errorResponse(401, "UNAUTHENTICATED", "Invalid person_id or password.");
  }

  const passwordOk = await compareSecret(body.password, person.password_hash);
  if (!passwordOk) {
    await admin
      .from("persons")
      .update({ failed_password_attempts: person.failed_password_attempts + 1 })
      .eq("person_id", person.person_id);
    return errorResponse(401, "UNAUTHENTICATED", "Invalid person_id or password.");
  }
  if (!person.mobile_number) {
    return errorResponse(400, "VALIDATION_ERROR", "No mobile_number on file to send an OTP to.");
  }

  const code = generateOtpCode();
  const codeHash = await hashSecret(code);
  const { data: otpRow, error: insertError } = await admin
    .from("otp_verifications")
    .insert({
      person_id: person.person_id,
      purpose: "PIN Reset",
      otp_code_hash: codeHash,
      status: "Sent",
    })
    .select("otp_id")
    .single();

  if (insertError || !otpRow) {
    console.error("auth-pin-reset-request otp insert failed", insertError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not process request.");
  }

  try {
    await sendSmsStub(person.mobile_number, code);
  } catch (e) {
    console.error("auth-pin-reset-request SMS stub failed", e);
  }

  return jsonResponse({ data: { otp_id: otpRow.otp_id }, meta: {}, errors: [] });
});

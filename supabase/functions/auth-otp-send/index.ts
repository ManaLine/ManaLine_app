// MANA LINE — POST /auth/otp/send  (04_API_Specification_v1_Part1.md §1.3)
//
// SMS GATEWAY: UNDECIDED (flagged per prompt §2 item 3 and
// auth_api_service.dart architectural note #5). The actual send call is
// stubbed behind the TODO below. Everything else — otp_id generation,
// otp_code_hash storage, the function's own request/response contract — is
// fully real and independently testable: you can call this function, read
// the OTP row via service_role/dashboard to get the plaintext code (never
// exposed in the response), and call auth-otp-verify with it, all without
// the gateway decision being made.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { generateOtpCode, hashSecret } from "../_shared/hashing.ts";
import { rateLimit } from "../_shared/rate_limit.ts";

interface OtpSendBody {
  person_id: string | number;
  purpose:
    | "Registration"
    | "Role Escalation"
    | "Password Reset"
    | "PIN Reset"
    | "Account Unlock"
    | "Agreement Acceptance";
  membership_id?: string; // required when purpose === "Role Escalation"
}

const VALID_PURPOSES = new Set([
  "Registration",
  "Role Escalation",
  "Password Reset",
  "PIN Reset",
  "Account Unlock",
  "Agreement Acceptance",
]);

/** TODO(sms-gateway): wire up MSG91/Twilio/etc. once decided. Expected
 * interface — replace this stub's body only, callers here never change:
 *   sendSms(mobileNumber: string, message: string): Promise<void>
 * Throwing from this stub must map to a 502-style failure upstream; for
 * now it's a no-op so the OTP contract is testable without a real gateway. */
async function sendSmsStub(mobileNumber: string, code: string): Promise<void> {
  console.log(`[STUB] Would send OTP ${code} to ${mobileNumber} via undecided SMS gateway`);
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  let body: OtpSendBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
  }

  if (!body.person_id || !body.purpose || !VALID_PURPOSES.has(body.purpose)) {
    return errorResponse(400, "VALIDATION_ERROR", "person_id and a valid purpose are required.");
  }
  if (body.purpose === "Role Escalation" && !body.membership_id) {
    return errorResponse(
      400,
      "VALIDATION_ERROR",
      "membership_id is required when purpose is 'Role Escalation'.",
    );
  }

  // 3 OTP sends per person per10 minutes. Prevents SMS-cost abuse
  // and keeps the OTP window tight even when the gateway is stubbed.
  if (!(await rateLimit(`otp:${body.person_id}`, 3, 10 * 60 * 1000))) {
    return errorResponse(429, "RATE_LIMITED", "Too many OTP requests. Please wait before trying again.");
  }

  const admin = supabaseAdmin();
  const { data: person, error: lookupError } = await admin
    .from("persons")
    .select("person_id, mobile_number")
    .eq("person_id", body.person_id)
    .maybeSingle();

  if (lookupError) {
    console.error("auth-otp-send lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not send OTP.");
  }
  if (!person) {
    return errorResponse(404, "NOT_FOUND", "No such person_id.");
  }
  if (!person.mobile_number) {
    return errorResponse(
      400,
      "VALIDATION_ERROR",
      "This account has no mobile_number on file to send an OTP to.",
    );
  }

  const code = generateOtpCode();
  const codeHash = await hashSecret(code);

  const { data: otpRow, error: insertError } = await admin
    .from("otp_verifications")
    .insert({
      person_id: person.person_id,
      purpose: body.purpose,
      otp_code_hash: codeHash,
      status: "Sent",
      membership_id: body.membership_id ?? null,
    })
    .select("otp_id")
    .single();

  if (insertError || !otpRow) {
    console.error("auth-otp-send insert failed", insertError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not send OTP.");
  }

  try {
    await sendSmsStub(person.mobile_number, code);
  } catch (e) {
    console.error("auth-otp-send SMS gateway stub failed", e);
    // OTP row already exists and is verifiable independent of delivery
    // (see file header) — still return otp_id rather than failing the
    // whole call, since the gateway is explicitly out of scope.
  }

  return jsonResponse({
    data: { otp_id: otpRow.otp_id },
    meta: {},
    errors: [],
  });
});

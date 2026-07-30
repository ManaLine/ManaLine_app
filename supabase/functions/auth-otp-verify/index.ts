// MANA LINE — POST /auth/otp/verify  (04_API_Specification_v1_Part1.md §1.3)
//
// A wrong code is a normal business-logic result (200 + verified:false),
// never a thrown error — auth_api_service.dart's verifyOtp() expects to
// read `data.verified` inline, matching the pre-existing stub UI's
// "Incorrect code" flow.
//
// Side effects on successful verification (per spec):
//   purpose=Registration      -> persons.verification_ring = 'GREEN'
//   purpose=Role Escalation   -> business_members.verification_status = 'Verified'
// RESOLVED: otp_verifications now carries membership_id (0036), set by
// auth-otp-send when purpose='Role Escalation' — read back here to know
// exactly which business_members row to update.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret } from "../_shared/hashing.ts";

interface OtpVerifyBody {
  otp_id: string;
  code: string;
}

const OTP_EXPIRY_MINUTES = 10; // Not specified in reference material —
// flagged assumption in END RESULT.

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  let body: OtpVerifyBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
  }

  if (!body.otp_id || !body.code) {
    return errorResponse(400, "VALIDATION_ERROR", "otp_id and code are required.");
  }

  const admin = supabaseAdmin();
  const { data: otpRow, error: lookupError } = await admin
    .from("otp_verifications")
    .select("otp_id, person_id, purpose, otp_code_hash, sent_at, status, membership_id")
    .eq("otp_id", body.otp_id)
    .maybeSingle();

  if (lookupError) {
    console.error("auth-otp-verify lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not verify OTP.");
  }
  if (!otpRow) {
    return errorResponse(404, "NOT_FOUND", "No such otp_id.");
  }

  if (otpRow.status === "Verified") {
    return jsonResponse({ data: { verified: true }, meta: {}, errors: [] });
  }

  const ageMinutes = (Date.now() - new Date(otpRow.sent_at).getTime()) / 60000;
  if (otpRow.status === "Expired" || ageMinutes > OTP_EXPIRY_MINUTES) {
    if (otpRow.status !== "Expired") {
      await admin.from("otp_verifications").update({ status: "Expired" }).eq("otp_id", otpRow.otp_id);
    }
    return jsonResponse({ data: { verified: false }, meta: {}, errors: [] });
  }

  const codeOk =
    // ============================================================
    // *** TESTING BYPASS — REMOVE BEFORE PRODUCTION ***
    // No SMS gateway is wired yet (open decision, not this batch's
    // scope), so there's no way to actually see a generated OTP code
    // outside the database. '123456' always verifies successfully as
    // a temporary testing convenience. This is a real security hole
    // if it ships — delete this whole condition (keep only the
    // compareSecret line below) before any production deploy.
    // ============================================================
    body.code === "123456" || (await compareSecret(body.code, otpRow.otp_code_hash));
  if (!codeOk) {
    return jsonResponse({ data: { verified: false }, meta: {}, errors: [] });
  }

  await admin
    .from("otp_verifications")
    .update({ status: "Verified", verified_at: new Date().toISOString() })
    .eq("otp_id", otpRow.otp_id);

  if (otpRow.purpose === "Registration") {
    await admin
      .from("persons")
      .update({ verification_ring: "GREEN" })
      .eq("person_id", otpRow.person_id);
  } else if (otpRow.purpose === "Role Escalation") {
    if (!otpRow.membership_id) {
      // Defensive — auth-otp-send now requires membership_id for this
      // purpose, so this should be unreachable for any OTP created after
      // 0036. Log rather than silently no-op, in case an older
      // pre-migration row somehow reaches here.
      console.error(
        `auth-otp-verify: Role Escalation OTP ${otpRow.otp_id} has no membership_id — cannot update business_members.`,
      );
    } else {
      const { error: membershipUpdateError } = await admin
        .from("business_members")
        .update({ verification_status: "Verified" })
        .eq("membership_id", otpRow.membership_id);
      if (membershipUpdateError) {
        console.error("auth-otp-verify: failed to update business_members", membershipUpdateError);
      }
    }
  }

  return jsonResponse({ data: { verified: true }, meta: {}, errors: [] });
});

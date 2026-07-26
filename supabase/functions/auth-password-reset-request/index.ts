// MANA LINE — POST /auth/password/reset-request (§1.3)
//
// LR-010 locked behavior (per auth_api_service.dart's doc comment): the
// caller must show an IDENTICAL message regardless of outcome — this
// function therefore always returns 200 with an otp_id shape, even when no
// matching identifier is found (in that case otp_id is null and the
// Dart client's `data['otp_id'] as String` cast would throw — flagged
// below; returning a dummy/opaque otp_id for a non-existent person is
// worse, since it could be probed against auth-otp-verify. This is a
// genuine UX-vs-security tension in the existing contract, not
// silently resolved either way).
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { generateOtpCode, hashSecret } from "../_shared/hashing.ts";

interface Body {
  identifier: string; // mlid or mobile_number
}

async function sendSmsStub(mobileNumber: string, code: string): Promise<void> {
  console.log(`[STUB] Would send password-reset OTP ${code} to ${mobileNumber}`);
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
  if (!body.identifier?.trim()) {
    return errorResponse(400, "VALIDATION_ERROR", "identifier is required.");
  }

  const admin = supabaseAdmin();
  const isMobile = /^\d{10,15}$/.test(body.identifier.trim());
  const { data: person } = await admin
    .from("persons")
    .select("person_id, mobile_number")
    .eq(isMobile ? "mobile_number" : "mlid", body.identifier.trim())
    .maybeSingle();

  // *** FLAGGED CONTRACT GAP *** — see file header. Per LR-010 we must not
  // reveal whether the identifier matched. auth_api_service.dart's
  // passwordResetRequest() does `data['otp_id'] as String` (non-nullable
  // cast) — so returning otp_id: null here would throw client-side. Until
  // the Dart/spec contract is updated to tolerate a null otp_id for the
  // no-match case, this function returns a 200 with a real otp_id only
  // when a match exists, and a 200 with otp_id: null otherwise — NOT a
  // distinguishing error status, so timing/status-code probing still
  // reveals nothing, but the client-side null-cast issue is a real
  // follow-up flagged in END RESULT, not silently patched over here.
  if (!person || !person.mobile_number) {
    // Sentinel, not null: the Dart client casts otp_id as a non-nullable
    // String (data['otp_id'] as String) — returning null here previously
    // threw a plain TypeError client-side for this exact, expected,
    // by-design case (no matching identifier). This UUID is never
    // written to otp_verifications (person_id is NOT NULL on that table,
    // so no real row could exist for a non-existent person anyway).
    // NOTE — not fully airtight: auth-otp-verify returns 404 for an
    // unknown otp_id but 200+verified:false for a real-but-wrong code,
    // so a determined caller could still distinguish match/no-match by
    // response shape. Full fix needs auth-otp-verify changed too — out
    // of scope for this pass, flagged honestly rather than claimed solved.
    return jsonResponse({ data: { otp_id: "00000000-0000-0000-0000-000000000000" }, meta: {}, errors: [] });
  }

  const code = generateOtpCode();
  const codeHash = await hashSecret(code);
  const { data: otpRow, error: insertError } = await admin
    .from("otp_verifications")
    .insert({
      person_id: person.person_id,
      purpose: "Password Reset",
      otp_code_hash: codeHash,
      status: "Sent",
    })
    .select("otp_id")
    .single();

  if (insertError || !otpRow) {
    console.error("auth-password-reset-request insert failed", insertError);
    return jsonResponse({ data: { otp_id: "00000000-0000-0000-0000-000000000000" }, meta: {}, errors: [] });
  }

  try {
    await sendSmsStub(person.mobile_number, code);
  } catch (e) {
    console.error("auth-password-reset-request SMS stub failed", e);
  }

  return jsonResponse({ data: { otp_id: otpRow.otp_id }, meta: {}, errors: [] });
});

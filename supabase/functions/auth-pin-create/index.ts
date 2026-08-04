// MANA LINE — auth-pin-create (LR-008, referenced in auth_api_service.dart).
// Not in 04_API_Specification_v1_Part1.md §1.3's endpoint list under that
// exact path, but auth_api_service.dart's createPin() calls it by name as
// part of the literal, already-integration-tested contract — per prompt
// §3, the Dart file wins over a stale/incomplete spec doc.
//
// Requires an authenticated session (bearer token with a valid person_id
// claim) — runs right after a successful password login, before any PIN
// exists yet. Rejects if the caller's token person_id doesn't match the
// person_id in the body, so one logged-in person can never set another
// person's PIN.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { hashSecret } from "../_shared/hashing.ts";
import { extractBearerToken, verifyPersonJwt } from "../_shared/jwt.ts";

interface PinCreateBody {
  person_id: string | number;
  pin: string;
  biometric_enabled: boolean;
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  const token = extractBearerToken(req);
  if (!token) {
    return errorResponse(401, "UNAUTHENTICATED", "Missing bearer token.");
  }
  let claims: { person_id: string };
  try {
    claims = await verifyPersonJwt(token);
  } catch {
    return errorResponse(401, "UNAUTHENTICATED", "Invalid or expired token.");
  }

  let body: PinCreateBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
  }

  if (!body.person_id || !body.pin) {
    return errorResponse(400, "VALIDATION_ERROR", "person_id and pin are required.");
  }
  if (String(body.person_id) !== claims.person_id) {
    return errorResponse(403, "FORBIDDEN", "Cannot set a PIN for another person.");
  }
  if (!/^\d{4}$/.test(body.pin) && !/^\d{6}$/.test(body.pin)) {
    return errorResponse(400, "VALIDATION_ERROR", "pin must be 4 or 6 digits.");
  }

  const admin = supabaseAdmin();
  const pinHash = await hashSecret(body.pin);

  const { error: updateError } = await admin
    .from("persons")
    .update({
      pin_hash: pinHash,
      pin_length: body.pin.length,
      biometric_enabled: Boolean(body.biometric_enabled),
      failed_pin_attempts: 0,
    })
    .eq("person_id", claims.person_id);

  if (updateError) {
    console.error("auth-pin-create update failed", updateError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not set PIN.");
  }

  return jsonResponse({ data: { success: true }, meta: {}, errors: [] });
});

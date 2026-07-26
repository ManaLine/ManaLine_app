// MANA LINE — POST /auth/login  (04_API_Specification_v1_Part1.md §1.3)
//
// This is NOT a GoTrue session — never calls supabase.auth.signIn*.
// Validates identifier+credential against persons.password_hash/pin_hash
// server-side (bcrypt compare only, never a plaintext comparison), then
// mints a custom JWT via ../_shared/jwt.ts carrying the `person_id` claim
// that app.current_person_id() (0012_rls_module0_identity.sql) reads on
// every subsequent RLS-gated request.
//
// CREDENTIAL-TYPE DISAMBIGUATION — RESOLVED. An explicit `credential_type`
// field ('password' | 'pin') now travels with every login request,
// letting this function check only the intended hash and correctly
// attribute failed attempts to the right BR-201 lockout counter
// (failed_password_attempts vs failed_pin_attempts) instead of the
// previous both-hashes-tried, password-counter-only approximation.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { compareSecret } from "../_shared/hashing.ts";
import { mintPersonJwt } from "../_shared/jwt.ts";

interface LoginBody {
  identifier: string; // mlid or mobile_number
  credential: string; // password or pin
  credential_type: "password" | "pin";
  device_fingerprint: string;
}

const MAX_PIN_ATTEMPTS = 3; // BR-201
const MAX_PASSWORD_ATTEMPTS = 5; // BR-201

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  let body: LoginBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
  }

  // Everything below can throw for reasons that have nothing to do with
  // the request itself (e.g. SUPABASE_JWT_SECRET missing from this
  // function's environment inside mintPersonJwt). Uncaught, Deno's
  // default crash response does NOT carry our CORS headers — the browser
  // then blocks reading it entirely, and Flutter Web reports that as a
  // generic network failure ("No internet connection"), masking the real
  // server-side cause. Wrapping here guarantees a proper, CORS-safe
  // errorResponse instead.
  try {

  if (
    !body.identifier?.trim() ||
    !body.credential ||
    !body.device_fingerprint?.trim() ||
    (body.credential_type !== "password" && body.credential_type !== "pin")
  ) {
    return errorResponse(
      400,
      "VALIDATION_ERROR",
      "identifier, credential, credential_type ('password'|'pin'), and device_fingerprint are required.",
    );
  }

  const admin = supabaseAdmin();

  const isMobile = /^\d{10,15}$/.test(body.identifier.trim());
  const { data: person, error: lookupError } = await admin
    .from("persons")
    .select(
      "person_id, mlid, password_hash, pin_hash, verification_ring, " +
        "failed_pin_attempts, failed_password_attempts, is_deceased",
    )
    .eq(isMobile ? "mobile_number" : "mlid", body.identifier.trim())
    .maybeSingle();

  if (lookupError) {
    console.error("auth-login lookup failed", lookupError);
    return errorResponse(500, "INTERNAL_ERROR", "Login failed.");
  }

  // Same generic failure for "no such identifier" and "wrong credential" —
  // never confirm/deny account existence to an unauthenticated caller.
  // MUST be HTTP 200: this is a normal, expected business outcome (LR-009's
  // own design treats "wrong PIN" as S3 — increment a counter, show
  // "Incorrect PIN" inline — never as a thrown exception). supabase_flutter's
  // functions.invoke() throws a FunctionException for ANY non-2xx status,
  // which would skip straight past the client's `result.success` check and
  // surface a generic "Server error" SnackBar instead of the correct inline
  // message. A 401 here was the actual bug behind that exact symptom.
  const genericFailure = () =>
    jsonResponse({
      data: {
        success: false,
        token: null,
        person_id: null,
        verification_ring: null,
        pin_exists: false,
      },
      meta: {},
      errors: [{ code: "UNAUTHENTICATED", message: "Invalid identifier or credential." }],
    });

  if (!person) return genericFailure();

  const isPin = body.credential_type === "pin";
  const maxAttempts = isPin ? MAX_PIN_ATTEMPTS : MAX_PASSWORD_ATTEMPTS;
  const currentAttempts = isPin ? person.failed_pin_attempts : person.failed_password_attempts;
  const attemptsColumn = isPin ? "failed_pin_attempts" : "failed_password_attempts";

  // BR-201: too many consecutive wrong attempts of the INTENDED credential
  // type -> lock, requires OTP unlock. Checked against the right counter
  // now that credential_type disambiguates which one applies.
  if (currentAttempts >= maxAttempts) {
    return errorResponse(
      403,
      "ACCOUNT_LOCKED",
      "Account is locked after too many failed attempts. Verify via OTP to unlock.",
    );
  }

  const targetHash = isPin ? person.pin_hash : person.password_hash;
  const credentialOk = await compareSecret(body.credential, targetHash);

  if (!credentialOk) {
    await admin
      .from("persons")
      .update({ [attemptsColumn]: currentAttempts + 1 })
      .eq("person_id", person.person_id);
    return genericFailure();
  }

  if (person.is_deceased) {
    return errorResponse(403, "FORBIDDEN", "This account is no longer active.");
  }

  // Success: reset both failure counters (BR-201).
  await admin
    .from("persons")
    .update({ failed_pin_attempts: 0, failed_password_attempts: 0 })
    .eq("person_id", person.person_id);

  // Single Device Policy (BR-152/197): deactivate any other active device,
  // activate/insert this one.
  const { data: activeDevices } = await admin
    .from("devices")
    .select("device_id, device_fingerprint")
    .eq("person_id", person.person_id)
    .eq("is_active", true);

  const alreadyActiveHere = activeDevices?.some(
    (d) => d.device_fingerprint === body.device_fingerprint,
  );

  if (!alreadyActiveHere) {
    if (activeDevices && activeDevices.length > 0) {
      await admin
        .from("devices")
        .update({ is_active: false })
        .eq("person_id", person.person_id)
        .eq("is_active", true);
      // TODO(notifications): fire "New Device Login" notification (BR-205)
      // here. No notifications table/endpoint was included in this batch's
      // reference material — flagged as a follow-up dependency, not
      // silently skipped.
    }
    const { data: existingDeviceRow } = await admin
      .from("devices")
      .select("device_id")
      .eq("person_id", person.person_id)
      .eq("device_fingerprint", body.device_fingerprint)
      .maybeSingle();

    if (existingDeviceRow) {
      await admin
        .from("devices")
        .update({ is_active: true, last_login_at: new Date().toISOString() })
        .eq("device_id", existingDeviceRow.device_id);
    } else {
      await admin.from("devices").insert({
        person_id: person.person_id,
        device_fingerprint: body.device_fingerprint,
        is_active: true,
        last_login_at: new Date().toISOString(),
      });
    }
  } else {
    await admin
      .from("devices")
      .update({ last_login_at: new Date().toISOString() })
      .eq("person_id", person.person_id)
      .eq("device_fingerprint", body.device_fingerprint);
  }

  const token = await mintPersonJwt(person.person_id);

  return jsonResponse({
    data: {
      success: true,
      token,
      person_id: person.person_id,
      verification_ring: person.verification_ring,
      pin_exists: Boolean(person.pin_hash),
      // memberships: spec §1.3 documents this field but it's out of scope
      // for this identity-only batch (business_members is Module 1) —
      // returning an empty array rather than omitting the key, so the
      // Dart client's shape expectations aren't broken. Flagged in END
      // RESULT as a follow-up: populate from business_members once this
      // function is extended, matching auth_api_service.dart's own
      // fetchMemberships() query.
      memberships: [],
    },
    meta: {},
    errors: [],
  });
  } catch (err) {
    console.error("auth-login unhandled error", err);
    return errorResponse(500, "INTERNAL_ERROR", "Login failed. Please try again.");
  }
});

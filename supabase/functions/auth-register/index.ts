// MANA LINE — POST /auth/register  (04_API_Specification_v1_Part1.md §1.1)
//
// Runs as `anon` (no session exists yet) — but ALL writes here use the
// service_role client, since `persons` has no client-writable INSERT
// policy at all (0012_rls_module0_identity.sql).
//
// OTP-COMBINING DECISION (flagged per prompt §2 item 1): this deployment
// does NOT combine OTP-send into registration. auth_api_service.dart's own
// comment says either shape is client-compatible (`otp_id` is nullable
// either way). This function always returns `otp_id: null` and expects the
// caller to make a separate `auth-otp-send` call afterward with the
// returned `person_id`. Rationale: keeps this function's failure modes
// (SMS gateway is UNDECIDED per prompt §2 item 3) fully decoupled from
// identity creation — a gateway outage should never block account
// creation itself.
//
// *** BLOCKING SPEC GAP — RESOLVED (was flagged in END RESULT) ***
// Neither 04_API_Specification_v1_Part1.md §1.1 nor the original
// auth_api_service.dart sent a password anywhere in the request body,
// even though BR-195 requires "Mobile Number + Password" for first login.
// Master chat traced this to a wiring bug: LR-004 already collects and
// validates a password client-side (min 8 chars, letters+numbers) but
// never passed it to register(). Fixed across all three layers
// (lr_004_registration_form.dart, auth_api_service.dart, this function) —
// password is now a field on the contract — required when
// registration_source is "System" (self-registration, e.g. LR-004).
// Left optional for "Migration" (OW-014 Owner-onboarded pre-existing
// members) — that path legitimately has no password yet; the person sets
// one later via LR-007 First Login. hashSecret() (same helper used for
// pin_hash/otp_code_hash) hashes it when present; password_hash stays
// NULL otherwise, matching the column's existing NULLable schema.
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { buildMlpi, buildMltiCandidate, genderDigitOf } from "../_shared/mlid.ts";
import { hashSecret } from "../_shared/hashing.ts";
import { istDate } from "../_shared/time.ts";

interface RegisterBody {
  full_name: string;
  father_husband_name: string;
  gender_digit: string;
  dob?: string | null;
  mobile_number?: string | null;
  password?: string | null;
  aadhaar_number?: string | null;
  address: {
    door_no: string;
    area_locality?: string | null;
    pin_code: string;
    village_id: string;
    from_date?: string;
    reason?: string | null;
  };
  registration_source: "Owner" | "Agent" | "Migration" | "System";
  customer_type: "New" | "Migrated";
}

function isValidAadhaar(v: string): boolean {
  return /^\d{12}$/.test(v);
}
function isValidMobile(v: string): boolean {
  return /^\d{10,15}$/.test(v);
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(405, "METHOD_NOT_ALLOWED", "Use POST.");
  }

  let body: RegisterBody;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Invalid JSON body.");
  }

  // --- Server-side validation. Never trust the Flutter client's own
  // validation (UX convenience only, not a security boundary — prompt §3). ---
  const errors: string[] = [];
  if (!body.full_name?.trim()) errors.push("full_name is required");
  if (!body.father_husband_name?.trim()) errors.push("father_husband_name is required");
  if (body.gender_digit !== "0" && body.gender_digit !== "1") {
    errors.push("gender_digit must be '0' or '1'");
  }
  if (body.aadhaar_number && !isValidAadhaar(body.aadhaar_number)) {
    errors.push("aadhaar_number must be exactly 12 digits");
  }
  if (body.mobile_number && !isValidMobile(body.mobile_number)) {
    errors.push("mobile_number must be 10-15 digits");
  }
  if (body.registration_source === "System") {
    if (!body.password || body.password.length < 8 || !/[A-Za-z]/.test(body.password) || !/\d/.test(body.password)) {
      errors.push("password must be at least 8 characters and include letters and numbers");
    }
  } else if (body.password) {
    // Optional even off the System path, but if provided it still must be valid.
    if (body.password.length < 8 || !/[A-Za-z]/.test(body.password) || !/\d/.test(body.password)) {
      errors.push("password must be at least 8 characters and include letters and numbers");
    }
  }
  if (!body.address?.door_no?.trim()) errors.push("address.door_no is required");
  if (!body.address?.pin_code?.trim() || !/^\d{6}$/.test(body.address.pin_code)) {
    errors.push("address.pin_code must be exactly 6 digits");
  }
  if (!body.address?.village_id) errors.push("address.village_id is required");
  if (!["Owner", "Agent", "Migration", "System"].includes(body.registration_source)) {
    errors.push("registration_source is invalid");
  }
  if (!["New", "Migrated"].includes(body.customer_type)) {
    errors.push("customer_type is invalid");
  }
  if (errors.length > 0) {
    return errorResponse(400, "VALIDATION_ERROR", errors.join("; "));
  }

  const admin = supabaseAdmin();
  const genderDigit = genderDigitOf(body.gender_digit);

  // --- MLID assignment (BR-181/182 base rule; role-based restriction not
  // enforceable here — see mlid.ts header comment). ---
  let mlid: string;
  let mlidType: "MLPI" | "MLTI";
  if (body.aadhaar_number) {
    mlid = buildMlpi(genderDigit, body.aadhaar_number);
    mlidType = "MLPI";
  } else {
    mlidType = "MLTI";
    // Retry on the (very unlikely) random-collision case rather than
    // trusting randomness blindly — persons.mlid is UNIQUE NOT NULL.
    let candidate = buildMltiCandidate(genderDigit);
    for (let attempt = 0; attempt < 5; attempt++) {
      const { data: existing } = await admin
        .from("persons")
        .select("person_id")
        .eq("mlid", candidate)
        .maybeSingle();
      if (!existing) break;
      candidate = buildMltiCandidate(genderDigit);
    }
    mlid = candidate;
  }

  // --- Hard duplicate check: real UNIQUE collision on aadhaar_number
  // (SP-001: never expose which existing account conflicts — generic 409
  // only, per prompt §2 item 1 / auth_api_service.dart architectural note #6). ---
  if (body.aadhaar_number) {
    const { data: aadhaarMatch } = await admin
      .from("persons")
      .select("person_id")
      .eq("aadhaar_number", body.aadhaar_number)
      .maybeSingle();
    if (aadhaarMatch) {
      return errorResponse(
        409,
        "CONFLICT",
        "This Aadhaar Number is already associated with an existing account.",
      );
    }
  }

  // --- Hard duplicate check: mobile_number. EXPLICIT PRODUCT DECISION
  // (supersedes BR-228's original soft-only design, 0039 migration) — a
  // second registration with an already-used mobile number is now
  // blocked, same generic-message treatment as the Aadhaar check above.
  if (body.mobile_number) {
    const { data: mobileMatch } = await admin
      .from("persons")
      .select("person_id")
      .eq("mobile_number", body.mobile_number)
      .maybeSingle();
    if (mobileMatch) {
      return errorResponse(
        409,
        "CONFLICT",
        "This mobile number is already associated with an existing account.",
      );
    }
  }

  // --- Soft duplicate check (BR-228): fuzzy match on mobile_number OR
  // full_name+father_husband_name+address combination. Does NOT block
  // registration — flags via duplicate_suspects (System-Automatic) and a
  // response-only `duplicate_flag`, never surfaced with details to the
  // registering person (matches LR-004: "duplicate_flag is never
  // surfaced ... avoids identity-fraud fishing"). ---
  let duplicateFlag = false;
  let matchedPersonId: number | null = null;
  const fuzzyMatchers: string[] = [];
  if (body.mobile_number) {
    const { data: mobileMatches } = await admin
      .from("persons")
      .select("person_id")
      .eq("mobile_number", body.mobile_number);
    if (mobileMatches && mobileMatches.length > 0) {
      duplicateFlag = true;
      matchedPersonId = mobileMatches[0].person_id;
      fuzzyMatchers.push("Phone");
    }
  }
  {
    const { data: nameMatches } = await admin
      .from("persons")
      .select("person_id")
      .eq("full_name", body.full_name.trim())
      .eq("father_husband_name", body.father_husband_name.trim());
    if (nameMatches && nameMatches.length > 0) {
      duplicateFlag = true;
      matchedPersonId ??= nameMatches[0].person_id;
      fuzzyMatchers.push("Name+FatherHusbandName");
    }
  }

  // --- profile_status (BR-231): Complete if all commonly-required fields
  // present, else Incomplete. Pending Verification / Archived are not
  // reachable from registration itself. ---
  const profileStatus =
    body.dob && body.mobile_number && body.aadhaar_number ? "Complete" : "Incomplete";

  const passwordHash = body.password ? await hashSecret(body.password) : null;

  const { data: inserted, error: insertError } = await admin
    .from("persons")
    .insert({
      mlid,
      mlid_type: mlidType,
      gender_digit: genderDigit,
      full_name: body.full_name.trim(),
      father_husband_name: body.father_husband_name.trim(),
      dob: body.dob ?? null,
      aadhaar_number: body.aadhaar_number ?? null,
      mobile_number: body.mobile_number ?? null,
      password_hash: passwordHash,
      profile_status: profileStatus,
      registration_source: body.registration_source,
      customer_type: body.customer_type,
    })
    .select("person_id, mlid, mlid_type, profile_status")
    .single();

  if (insertError || !inserted) {
    // Race-condition guard: a concurrent request could win the UNIQUE
    // aadhaar_number check between our SELECT and this INSERT.
    if (insertError?.code === "23505") {
      return errorResponse(
        409,
        "CONFLICT",
        "This Aadhaar Number is already associated with an existing account.",
      );
    }
    console.error("auth-register insert failed", insertError);
    return errorResponse(500, "INTERNAL_ERROR", "Could not create account.");
  }

  // --- resolve mandal/district/state from the real locations table ---
  // person_addresses.mandal/district/state are documented as "auto-derived
  // from village" (0001_module0_identity.sql) — the derivation source
  // wasn't in this batch's original attached files, but it does exist:
  // locations(mandal, district, state), FK'd from
  // person_addresses.village_id via fk_person_addresses_village
  // (0002_module1_tenancy.sql). Resolved here rather than trusting the
  // client to send these — address-write paths must derive from
  // `locations`, never accept them as free text (standing convention).
  const { data: village, error: villageError } = await admin
    .from("locations")
    .select("mandal, district, state")
    .eq("location_id", body.address.village_id)
    .maybeSingle();

  if (villageError || !village) {
    console.error("auth-register village lookup failed", villageError);
    return errorResponse(
      422,
      "INVALID_VILLAGE",
      "Selected village could not be found. Please re-select from the village picker.",
    );
  }

  // --- address row (person_addresses, BR-225) ---
  const { error: addressError } = await admin.from("person_addresses").insert({
    person_id: inserted.person_id,
    door_no: body.address.door_no,
    area_locality: body.address.area_locality ?? null,
    pin_code: body.address.pin_code,
    village_id: body.address.village_id,
    mandal: village.mandal,
    district: village.district,
    state: village.state,
    from_date: body.address.from_date ?? istDate(),
    reason: body.address.reason ?? null,
    is_current: true,
  });
  if (addressError) {
    console.error("auth-register address insert failed", addressError);
    // Person row already exists at this point; do not roll it back (no
    // hard deletes anywhere in this schema, BR-002/127). Surface the
    // partial-failure clearly instead.
    return errorResponse(
      500,
      "INTERNAL_ERROR",
      "Account created but address could not be saved. Contact support with person_id " +
        inserted.person_id,
    );
  }

  if (duplicateFlag && matchedPersonId !== null) {
    const { error: suspectError } = await admin.from("duplicate_suspects").insert({
      person_id_a: inserted.person_id,
      person_id_b: matchedPersonId,
      matched_on: fuzzyMatchers.join("+"),
      detection_method: "System-Automatic",
    });
    if (suspectError) {
      console.error("auth-register duplicate_suspects insert failed", suspectError);
      // Non-fatal: registration still succeeds per BR-228 ("does NOT block
      // registration"). The flag is still returned to the caller below.
    }
  }

  return jsonResponse({
    data: {
      person_id: inserted.person_id,
      mlid: inserted.mlid,
      mlid_type: inserted.mlid_type,
      profile_status: inserted.profile_status,
      duplicate_flag: duplicateFlag,
      otp_id: null,
    },
    meta: {},
    errors: [],
  });
});

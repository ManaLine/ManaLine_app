// MANA LINE — MLID generation (BR-181/182).
//
// BR-181: MLPI = "MLPI" + gender_digit(0=F,1=M) + last 8 digits of Aadhaar.
//   Assigned only when Aadhaar is provided at registration.
// BR-182: MLTI = "MLTI" + gender_digit + unique random 8-digit number.
//   Assigned when Aadhaar is not provided at registration.
//
// ASSUMPTION FLAGGED (see END RESULT): Addendum v3 (01_Global_Rules_Guide.md,
// "BR-181/182/190 SUPERSEDED") restricts Owner/Agent/Investor registration
// to Aadhaar-mandatory/MLPI-only, MLTI blocked outright for those three
// roles. `auth-register`'s request body (04_API_Specification_v1_Part1.md
// §1.1 and auth_api_service.dart) has no `role` field — it registers a
// `persons` identity only; role/tenancy attachment happens later via
// `POST /businesses/{id}/members` (§2.5). This function therefore
// implements the BASE BR-181/182 rule only (Aadhaar present -> MLPI,
// absent -> MLTI) and does NOT attempt to enforce the role-based
// restriction, since role isn't known yet at this call. That enforcement
// belongs in the members-creation endpoint (out of this batch's scope) —
// flagged, not silently applied here.

export function genderDigitOf(genderDigit: string): "0" | "1" {
  if (genderDigit !== "0" && genderDigit !== "1") {
    throw new Error("gender_digit must be '0' or '1'");
  }
  return genderDigit;
}

export function buildMlpi(genderDigit: "0" | "1", aadhaarNumber: string): string {
  const last8 = aadhaarNumber.slice(-8);
  return `MLPI${genderDigit}${last8}`;
}

function randomDigits(length: number): string {
  const bytes = new Uint32Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => (b % 10).toString()).join("");
}

export function buildMltiCandidate(genderDigit: "0" | "1"): string {
  return `MLTI${genderDigit}${randomDigits(8)}`;
}

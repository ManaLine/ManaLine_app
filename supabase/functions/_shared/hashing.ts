// MANA LINE — shared password/PIN hashing.
//
// LIBRARY DECISION: bcryptjs (npm:bcryptjs), used consistently for
// password_hash, pin_hash, AND otp_code_hash across every function in this
// batch. Rationale:
//   - The historically-recommended `deno.land/x/bcrypt` native/worker
//     implementation is unreliable on Supabase's Edge Runtime (Worker
//     spawning is restricted in that sandbox) — a well-documented failure
//     mode for exactly this deployment target.
//   - bcryptjs is a pure-JS reimplementation with no native bindings and no
//     workers, so it runs the same way in Deno Deploy/Edge Runtime as
//     anywhere else. Slightly slower than native bcrypt, acceptable at
//     auth-request volume.
//   - argon2 was considered (arguably stronger) but has weaker
//     battle-tested Deno-edge support today; bcrypt is the safer choice for
//     a V1 production auth layer. Revisit for V2 if desired.
// Do not mix hashing schemes across functions — every hash/compare in this
// entire batch goes through this one module.
import bcrypt from "npm:bcryptjs@2.4.3";

const SALT_ROUNDS = 10;

export async function hashSecret(plaintext: string): Promise<string> {
  return await bcrypt.hash(plaintext, SALT_ROUNDS);
}

export async function compareSecret(
  plaintext: string,
  hash: string | null | undefined,
): Promise<boolean> {
  if (!hash) return false;
  return await bcrypt.compare(plaintext, hash);
}

// ===========================================================================
// ⚠️  PRE-LAUNCH ONLY — EVERY OTP IN THIS DEPLOYMENT IS 123456  ⚠️
//
// There is no SMS gateway. auth-otp-send generates a code, hashes it, stores
// the row, and console.logs "[STUB] Would send OTP ... via undecided SMS
// gateway" — the code is never delivered to anybody. A tester could reach the
// OTP screen and had no way to learn the number except reading the function
// logs or the database.
//
// So the code is fixed at 123456 until a gateway is chosen. This is a
// deliberate decision for a pre-launch testing build, taken knowingly.
//
// WHAT IT COSTS, stated plainly because it is easy to forget once it works:
// this is a LIVE project carrying real customers and real loans, and OTP is
// the second factor on more than registration. Password Reset, PIN Reset and
// Account Unlock all go through it. Anyone who knows a mobile number can take
// over that person's account with 123456 — including an Owner's.
//
// REMOVING IT IS ONE LINE: delete MANA_FIXED_OTP and its use below. Prefer
// doing that at the same commit the gateway lands, not after.
//
// MANA_OTP_CODE overrides it without a deploy — set it to any 6 digits, or to
// the literal string "random" to restore CSPRNG behaviour immediately.
// ===========================================================================
const MANA_FIXED_OTP = "123456";

/**
 * The OTP code for a new verification.
 *
 * Returns [MANA_FIXED_OTP] unless MANA_OTP_CODE says otherwise. The random
 * path below is the real implementation and is kept intact — CSPRNG, never
 * Math.random — so restoring it is a matter of deleting the branch above it
 * rather than rewriting anything.
 */
export function generateOtpCode(): string {
  const override = Deno.env.get("MANA_OTP_CODE");
  if (override !== "random") {
    const fixed = override && /^\d{6}$/.test(override) ? override : MANA_FIXED_OTP;
    console.warn(
      `[PRE-LAUNCH] OTP is the fixed code ${fixed}, not a random one. ` +
        `Every account on this deployment can be verified with it. ` +
        `Set MANA_OTP_CODE=random to turn this off.`,
    );
    return fixed;
  }

  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  const code = (bytes[0] % 1_000_000).toString().padStart(6, "0");
  return code;
}

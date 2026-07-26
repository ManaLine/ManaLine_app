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

/** Generates a numeric OTP code (6 digits) using a CSPRNG — never Math.random. */
export function generateOtpCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  const code = (bytes[0] % 1_000_000).toString().padStart(6, "0");
  return code;
}

// MANA LINE — shared service-role client.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-injected into every
// Edge Function's environment by the Supabase platform — they do NOT need
// to be set manually in the dashboard's function secrets. They are read via
// Deno.env.get(...) only, never hardcoded, never returned in a response
// body, never logged.
//
// This client BYPASSES RLS (service_role). Every function in this
// deployment uses it because `persons` has no INSERT/UPDATE policy for any
// client role by design (0012_rls_module0_identity.sql: "person rows are
// created exclusively by registration/onboarding server-side flows").
import { createClient } from "npm:@supabase/supabase-js@2";

export function supabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in function environment",
    );
  }
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

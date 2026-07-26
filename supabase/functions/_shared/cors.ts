// MANA LINE — shared CORS headers.
// Flutter Web is a confirmed target platform, so every function in this
// deployment needs explicit preflight handling — Supabase Edge Functions do
// NOT add CORS headers automatically.
//
// NOTE: '*' is used for Access-Control-Allow-Origin because the Flutter app
// is not yet deployed to a fixed production origin. Tighten this to the
// real app origin(s) once known — flagged in END RESULT.
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Call at the top of every function. Returns a Response for OPTIONS
 * preflight requests, or null if the caller should continue handling the
 * real request. */
export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

/** Standard envelope error response (04_API_Specification_v1_Part1.md §0). */
export function errorResponse(
  status: number,
  code: string,
  message: string,
  extra: Record<string, unknown> = {},
): Response {
  return jsonResponse(
    { data: null, meta: {}, errors: [{ code, message, ...extra }] },
    status,
  );
}

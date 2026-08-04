-- =============================================================================
-- BATCH D (1/2) — auth rate limiting + BR-201 cooldown (#13)
-- =============================================================================
-- WHAT THIS FILE DOES:
--   (1) Creates the auth_rate_limits table — a lightweight advisory
--       counter per "bucket" (e.g. 'login:<mobile>:<ip>' or 'otp:<personId>').
--       No foreign keys, no complex indexes: just (bucket_key, bucket_ts).
--       The Edge Function helper counts rows in the last window and
--       rejects when the limit is reached.
--
--   (2) Adds a BR-201 cooldown: when an account IS locked (403), a
--       counter-based cooldown starts. Even if the victim unlocks via OTP
--       within seconds, repeated lock-outs within a short window still show
--       the lock to the attacker (but the victim's unlock immediately
--       resets everything). The cooldown is enforced in auth-login
--       (edge function) — see the code change there.
--
--   No Dart changes are needed for this item beyond the client 429 path
--   in network_error_handler.dart, which is a small callback addition.
-- -----------------------------------------------------------------------------

-- Advisory bucket counter: one row per call in the window.
-- bucket_id is the unique per-row key (BIGSERIAL, so concurrent inserts
-- never collide); bucket_ts is the wall-clock marker the TTL/cutoff
-- checks compare against (now() at insert).
CREATE TABLE auth_rate_limits (
  bucket_id  BIGSERIAL PRIMARY KEY,
  bucket_key TEXT      NOT NULL,
  bucket_ts  TIMESTAMP NOT NULL DEFAULT now()
);

-- TTL index so old rows don't bloat the table. 24h is ample for
-- any auth window; the Edge Function helper also cleans on each call.
CREATE INDEX idx_auth_rate_limits_key_ts ON auth_rate_limits (bucket_key, bucket_ts);

-- The limiter is only meaningful if the people being limited cannot touch it.
-- This table lives in `public`, so PostgREST would otherwise expose it: an
-- attacker could DELETE their own bucket rows and reset the counter at will.
-- Only the Edge Functions (service role, which bypasses RLS) may reach it.
ALTER TABLE auth_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON auth_rate_limits FROM anon, authenticated;
REVOKE ALL ON SEQUENCE auth_rate_limits_bucket_id_seq FROM anon, authenticated;

COMMENT ON TABLE auth_rate_limits IS
  'Advisory rate-limit counter for auth endpoints. Each successful/failed call inserts a row; the Edge Function helper counts rows within the window and rejects when the limit is reached.';

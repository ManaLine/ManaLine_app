CREATE TABLE auth_rate_limits (
  bucket_id  BIGSERIAL PRIMARY KEY,
  bucket_key TEXT      NOT NULL,
  bucket_ts  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_auth_rate_limits_key_ts ON auth_rate_limits (bucket_key, bucket_ts);

ALTER TABLE auth_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON auth_rate_limits FROM anon, authenticated;
REVOKE ALL ON SEQUENCE auth_rate_limits_bucket_id_seq FROM anon, authenticated;

COMMENT ON TABLE auth_rate_limits IS
  'Advisory rate-limit counter for auth endpoints. Each successful/failed call inserts a row; the Edge Function helper counts rows within the window and rejects when the limit is reached.';

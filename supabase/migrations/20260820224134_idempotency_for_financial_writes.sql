-- Retrying a financial write must not repeat it.
--
-- THE FIELD CASE: an Agent on 2G taps Save on a collection. The request goes
-- out, the reply never comes back, the app shows an error with a Retry button
-- — and every retry recorded a SECOND collection against the same loan. The
-- customer's balance drops twice, the agent's float rises twice, and nobody
-- notices until a settlement fails. app.record_collection had only a
-- duplicate WARNING, which catches two different agents colliding, not one
-- agent's own request being retried.
--
-- ONE table for every financial RPC rather than an idempotency column on each
-- of the eight money tables: the mechanism is identical everywhere, and one
-- place to audit is worth more than a column that some future table forgets.
--
-- The stored response is replayed verbatim, so a retry sees exactly what the
-- first call returned — the same receipt number, the same remaining balance —
-- rather than a fresh "already recorded" error the Agent has to interpret.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  idempotency_key text PRIMARY KEY,
  operation       text        NOT NULL,
  business_id     uuid        NULL REFERENCES businesses(business_id),
  person_id       bigint      NULL REFERENCES persons(person_id),
  response        json        NOT NULL,
  created_at      timestamp   NOT NULL DEFAULT now()
);

COMMENT ON TABLE idempotency_keys IS
  'One row per completed financial write. A retry carrying the same key replays the stored response instead of writing again.';

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_created
  ON idempotency_keys (created_at);

ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;

-- No client ever reads or writes this directly; only SECURITY DEFINER RPCs
-- touch it. RLS on with no policy is deliberate: the table is invisible to
-- PostgREST, which is exactly right for a replay cache.
COMMENT ON COLUMN idempotency_keys.response IS
  'Verbatim JSON the original call returned, replayed on retry.';

-- Returns the stored response for a key, or NULL if this is the first time.
CREATE OR REPLACE FUNCTION app.idempotent_replay(p_key text, p_operation text)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_response json;
  v_operation text;
BEGIN
  IF NULLIF(btrim(p_key), '') IS NULL THEN RETURN NULL; END IF;

  SELECT response, operation INTO v_response, v_operation
    FROM idempotency_keys WHERE idempotency_key = btrim(p_key);

  IF v_response IS NULL THEN RETURN NULL; END IF;

  -- The same key arriving on a different operation means the caller reused a
  -- key it should not have. Replaying a collection's response to a loan
  -- request would be far worse than failing loudly.
  IF v_operation IS DISTINCT FROM p_operation THEN
    RAISE EXCEPTION 'Idempotency key % was already used for %, not %',
      p_key, v_operation, p_operation USING ERRCODE = '23505';
  END IF;

  RETURN v_response;
END;
$$;

CREATE OR REPLACE FUNCTION app.idempotent_store(
  p_key text,
  p_operation text,
  p_response json,
  p_business_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF NULLIF(btrim(p_key), '') IS NULL THEN RETURN; END IF;

  INSERT INTO idempotency_keys (
    idempotency_key, operation, business_id, person_id, response
  ) VALUES (
    btrim(p_key), p_operation, p_business_id, app.current_person_id(), p_response
  )
  -- A race between two in-flight retries: whichever lands first wins and the
  -- second is a no-op. Both callers then see the same stored response.
  ON CONFLICT (idempotency_key) DO NOTHING;
END;
$$;

-- Leave exactly one import_migrated_loans.
--
-- The previous migration added p_idempotency_key with a DEFAULT, which
-- CREATE OR REPLACE cannot do: a changed parameter list makes a SECOND
-- function, and PostgREST answers HTTP 300 because it cannot choose between
-- them. Fourth time this trap has been hit this week — a signature change is
-- always DROP then CREATE, never CREATE OR REPLACE.
DROP FUNCTION IF EXISTS app.import_migrated_loans(uuid, json);

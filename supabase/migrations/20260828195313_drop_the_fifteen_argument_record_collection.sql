-- The fifth time this has happened, and the reason CLAUDE.md lists it.
--
-- Adding p_parent_collection_id with a DEFAULT did not replace
-- app.record_collection -- it created a second one beside it. PostgREST then
-- cannot choose between them and answers HTTP 300 (PGRST203) to every call,
-- which on the handset reads as the collection screen simply not working.
--
-- A changed parameter list is DROP then CREATE. Never CREATE OR REPLACE.
DROP FUNCTION app.record_collection(
  uuid, uuid, numeric, payer_type_enum, date, uuid, uuid,
  collection_result_type_enum, numeric, excess_disposition_enum, text, json,
  boolean, character varying, text
);

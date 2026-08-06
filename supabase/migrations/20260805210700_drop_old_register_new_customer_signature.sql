-- Adding the three GPS parameters in 20260805210617 created a SECOND function
-- rather than replacing the first: CREATE OR REPLACE matches on the full
-- argument list, so a 12-parameter version was created and the original
-- 9-parameter one stayed exactly where it was.
--
-- Because the new parameters all have defaults, a 9-argument call then matched
-- BOTH, and Postgres refused to choose:
--
--   function app.register_new_customer(uuid, unknown, ... , uuid) is not unique
--
-- Every existing caller passes nine arguments, so customer registration would
-- have failed outright for everyone. This is the same overload-ambiguity that
-- had already made app.migrate_loan permanently uncallable
-- (20260805143507) -- the second time this exact shape has bitten in this
-- schema, and worth remembering: adding a defaulted parameter to an existing
-- function is not an in-place change, it is a new overload.
--
-- Caught by a probe rather than in production, because the probe called it the
-- way the app does.
DROP FUNCTION IF EXISTS app.register_new_customer(
  uuid, character varying, character varying, character, character varying,
  character varying, character varying, character varying, uuid
);

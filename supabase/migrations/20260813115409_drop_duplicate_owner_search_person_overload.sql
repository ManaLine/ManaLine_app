-- =============================================================================
-- Drop the stale varchar overload of app.owner_search_person
-- =============================================================================
-- SYMPTOM: OW-005 Step 1 "Select Customer" failed on every search with
--   PGRST203: Could not choose the best candidate function between
--   app.owner_search_person(p_mlid => text, ...) and
--   app.owner_search_person(p_mlid => character varying, ...)
--
-- Two overloads existed with the SAME arity, differing only in parameter type.
-- PostgREST sends JSON strings and cannot pick between text and varchar, so
-- the call 300s before reaching either. Customer search on the loan wizard was
-- dead.
--
-- This is not a cosmetic de-duplication. The two bodies BEHAVE DIFFERENTLY on
-- the name branch:
--
--   varchar (older, dropped here)  ... WHERE full_name ILIKE '%x%' LIMIT 1
--   text    (kept)                 ... ORDER BY length(full_name) LIMIT 25
--
-- The newer text version is the one carrying the "a name is not unique, return
-- every match" fix. Had PostgREST resolved to the varchar copy instead of
-- erroring, an Owner searching a common name would have been handed exactly
-- one of several people with no indication others existed — and OW-005 issues
-- a loan against whoever comes back. A hard PGRST203 was the safer of the two
-- failure modes.
--
-- Root cause to avoid repeating: a later migration recreated this function
-- with text parameters instead of ALTERing the varchar original, so CREATE
-- made a second function rather than replacing the first. CREATE OR REPLACE
-- only replaces when the argument types match exactly.
--
-- Swept the rest of app/public for the same shape while here. The only other
-- overloaded function is app.own_active_agent_membership_permits, which has
-- two DIFFERENT arities (2 and 3 args) — PostgREST resolves that by the
-- argument names supplied, so it is not ambiguous and was left alone.
DROP FUNCTION IF EXISTS app.owner_search_person(
  character varying, character varying, character varying, character varying
);

-- Carry the doc comment across to the survivor; it lived on the dropped copy.
COMMENT ON FUNCTION app.owner_search_person(text, text, text, text) IS
  'Multi-criteria identity search for OW-004/OW-005. Caller must be SOME business''s Owner; the target need not already share a business. MLID/Aadhaar/mobile return at most one row; a name returns up to 25, shortest first, because a name is not unique and picking one silently is how a loan reaches the wrong person.';

-- MANA LINE — 0033_locations_allow_anon_select.sql
--
-- WHY THIS EXISTS: LR-004 (Registration Form) queries `locations` directly
-- for the village search picker — and registration necessarily happens
-- BEFORE any login exists, so the Supabase client calls as `anon`, not
-- `authenticated`. The original policy (0013_rls_module1_tenancy.sql,
-- locations_authenticated_select) requires auth.role() = 'authenticated',
-- which silently returns zero rows to an anon caller — no error, just an
-- empty result set. This is exactly the "RLS silent failure" pattern
-- flagged as a systemic risk elsewhere in this project: it looked like a
-- picker bug (no results ever appear) but was actually a permissions gap.
--
-- This table's own original comment already establishes it's safe for
-- broad read access ("just village/pin-code/district reference data,
-- needed for address entry everywhere") — that reasoning extends cleanly
-- to anon, since there's nothing tenant-scoped or sensitive in a village/
-- mandal/district/state row. Writes remain fully restricted (unchanged) —
-- this migration only affects SELECT.

DROP POLICY IF EXISTS locations_authenticated_select ON locations;

CREATE POLICY locations_public_select ON locations
  FOR SELECT
  USING (true);

COMMENT ON POLICY locations_public_select ON locations IS
  'Broadened from authenticated-only (0013) to public read in 0033 — registration (LR-004) needs village lookup before any session exists. Table has no client write policy, so this only affects reads of non-sensitive reference data.';

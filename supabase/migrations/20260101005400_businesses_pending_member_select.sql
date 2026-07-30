-- =============================================================================
-- 0052a — businesses_pending_member_select RLS policy
-- =============================================================================
-- RECOVERED FILE, added 2026-07-30. This migration was applied directly to
-- the live project on 2026-07-28 (ledger version 20260728102506) and never
-- had a file in supabase/migrations/, which meant the repo could not rebuild
-- the database: a fresh project would have silently missed this policy. SQL
-- below is recovered verbatim from
-- supabase_migrations.schema_migrations.statements. See the drift note in
-- ../MIGRATIONS.md for how this class of gap arose.
-- -----------------------------------------------------------------------------

-- Fixes confirmed bug: a person with a PENDING (not yet Active)
-- membership request could not see the business's own name via the
-- embedded businesses(...) join in fetchMemberships() -- RLS only
-- allowed active members or the owner, so the Pending Requests card on
-- LR-012 showed a blank business name ("-- as Agent" instead of
-- "Business Name -- as Agent"). Same pattern as persons_owner_pending_
-- member_select (0035) -- an additive, narrower policy, not touching
-- the existing businesses_member_select at all.
CREATE POLICY businesses_pending_member_select ON businesses
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM business_members bm
      WHERE bm.business_id = businesses.business_id
        AND bm.person_id = app.current_person_id()
    )
  );

COMMENT ON POLICY businesses_pending_member_select ON businesses IS
  'Lets a person see basic info of a business they hold ANY membership row for (including Pending Invitation), not just Active -- fixes blank business name on LR-012 Pending Requests. Still gated on a real business_members row existing, not a global business search.';

-- MANA LINE — 0029b_platform_admins_minimal.sql
--
-- Minimal subset of 0029 — just enough for create_platform_admin.sql to
-- work. Run this FIRST if you get "relation platform_admins does not
-- exist" — it means 0029 (or an earlier SP-001 migration it depends on)
-- was never actually applied to this live database, despite SP-001
-- (Aadhaar Dispute Resolution) having been built earlier this session.
--
-- Deliberately does NOT include 0029's other 5 RPCs
-- (support_lookup_person, support_suspension_impact,
-- support_apply_suspension, support_upgrade_mlid_dispute,
-- support_upload_identity_document, support_fetch_latest_id_history) —
-- those depend on identity_documents/person_id_history, which may have
-- their own unmet dependencies in this database. If SP-001 itself needs
-- testing, run the FULL 0029 migration separately and check for further
-- missing-relation errors the same way this one surfaced.

CREATE TABLE IF NOT EXISTS platform_admins (
    person_id   BIGINT PRIMARY KEY REFERENCES persons(person_id),
    added_at    TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform_admins IS
  'Minimum viable gate for SP-001 Support-tool RPCs. Presence of a row = full SP-001 access for that person_id; no finer grain. No client write policy anywhere — populated only via direct DB access by a trusted operator.';

ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;
-- Intentional deny-all — no CREATE POLICY for any role, including the
-- admin themselves. Lookups happen via the SECURITY DEFINER function
-- below, which never needs a SELECT policy on this table.

CREATE OR REPLACE FUNCTION app.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM platform_admins WHERE person_id = app.current_person_id()
  );
$$;

COMMENT ON FUNCTION app.is_platform_admin() IS
  'Gate for every SP-001 Support-tool RPC. TRUE only if the calling person_id has a row in platform_admins.';

GRANT EXECUTE ON FUNCTION app.is_platform_admin() TO authenticated;

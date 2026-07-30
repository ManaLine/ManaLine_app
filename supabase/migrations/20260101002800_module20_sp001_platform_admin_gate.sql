-- =============================================================================
-- 0029 — Module 20: SP-001 Platform Admin Gate
-- =============================================================================
-- SUPERSEDES the service_role assumption in 0028. SP-001's own spec leaves
-- the Support-tool access model ("roles, permissions, login") as explicit
-- future work — but 0028's RPCs suspend arbitrary businesses/memberships
-- and rewrite persons.mlid, which is too dangerous to ship gated on nothing
-- more than "the caller holds the service_role key." That key is a single
-- shared secret with zero per-operator accountability and no audit trail
-- of WHICH Support staff member ran a given suspension/mlid-rewrite.
--
-- MINIMUM VIABLE GATE (deliberately small, NOT an attempt to build the full
-- Support-tool access-model spec calls out of scope): a `platform_admins`
-- table, keyed by person_id exactly like every other permission check in
-- this codebase (agent_permissions.agent_id, business_members.role, etc.).
-- A person becomes a platform admin only by a row being inserted here —
-- there is no self-service path, no client INSERT/UPDATE/DELETE policy at
-- all (RLS enabled, deny-all for every authenticated role; only a direct
-- DB admin / future internal Support-tool admin-of-admins flow can manage
-- this table). Support staff therefore DO need a genuine Supabase-
-- authenticated session (the same JWT + person_id-claim mechanism every
-- other RPC in this codebase already relies on via app.current_person_id(),
-- see 0012) — they are simply a person with NO business_members role at
-- all, gated purely by this table, not by owning/joining any tenancy.
--
-- Every SP-001 RPC from 0028 is re-created here (DROP+CREATE, matching the
-- established pattern from 0024's return-shape fix over 0021) with an
-- app.is_platform_admin() check as the FIRST line of the function body, and
-- GRANTed to `authenticated` instead of `service_role` — the service_role
-- key must never be embedded in any client, including this internal tool.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- platform_admins — deliberately minimal. No status/role/scope columns: a
-- person either has a row here (full SP-001 access) or does not (none at
-- all). Finer-grained Support-tool permissions are explicitly out of scope
-- per SP-001's own RESOLVED section; this table is the smallest gate that
-- makes 0028's RPCs safe to ship, not a preview of a larger admin-roles
-- system.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS platform_admins (
    person_id   BIGINT PRIMARY KEY REFERENCES persons(person_id),
    added_at    TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform_admins IS
  'Minimum viable gate for SP-001 Support-tool RPCs (0028/0029). Presence of a row = full SP-001 access for that person_id; no finer grain. No client write policy anywhere — populated only via direct DB access by a trusted operator, since a self-service or in-app path to grant platform-admin rights would defeat the purpose of the gate.';

ALTER TABLE platform_admins ENABLE ROW LEVEL SECURITY;
-- No CREATE POLICY at all, for any role, including the admin themselves —
-- intentional deny-all, same pattern already used for duplicate_suspects
-- in 0012. A platform admin can be looked up FOR THEM (is_platform_admin())
-- via the SECURITY DEFINER function below without ever needing a SELECT
-- policy on this table for authenticated/anon.

-- -----------------------------------------------------------------------------
-- app.is_platform_admin() — the actual gate every SP-001 RPC checks first.
-- -----------------------------------------------------------------------------
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
  'Gate for every SP-001 Support-tool RPC. TRUE only if the calling person_id (resolved the same way as every other app.* helper, via the JWT person_id claim) has a row in platform_admins. Returns FALSE (never NULL) for anon, for any ordinary Owner/Agent/Investor/Customer, and for a NULL current_person_id().';

GRANT EXECUTE ON FUNCTION app.is_platform_admin() TO authenticated;

-- -----------------------------------------------------------------------------
-- Re-create 0028's four RPCs with the gate added + GRANT moved from
-- service_role to authenticated.
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS app.support_lookup_person(VARCHAR);

CREATE OR REPLACE FUNCTION app.support_lookup_person(p_search VARCHAR)
RETURNS TABLE(person_id BIGINT, mlid VARCHAR, full_name VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.person_id, p.mlid, p.full_name
  FROM persons p
  WHERE p.mlid = p_search
     OR RIGHT(p.mlid, 8) = RIGHT(p_search, 8)
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_lookup_person(VARCHAR) TO authenticated;

DROP FUNCTION IF EXISTS app.support_suspension_impact(BIGINT);

CREATE OR REPLACE FUNCTION app.support_suspension_impact(p_person_id BIGINT)
RETURNS TABLE(id TEXT, label VARCHAR, role VARCHAR, is_owner_business BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT b.business_id::TEXT, b.business_name, 'Owner'::VARCHAR, TRUE
  FROM businesses b
  WHERE b.owner_person_id = p_person_id
  UNION ALL
  SELECT bm.membership_id::TEXT, b.business_name, bm.role::VARCHAR, FALSE
  FROM business_members bm
  JOIN businesses b ON b.business_id = bm.business_id
  WHERE bm.person_id = p_person_id
    AND bm.role <> 'Owner';
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_suspension_impact(BIGINT) TO authenticated;

DROP FUNCTION IF EXISTS app.support_apply_suspension(BIGINT, BOOLEAN);

CREATE OR REPLACE FUNCTION app.support_apply_suspension(p_person_id BIGINT, p_suspend BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  IF p_suspend THEN
    UPDATE businesses SET business_status = 'Suspended', updated_at = now()
    WHERE owner_person_id = p_person_id AND business_status <> 'Suspended';

    UPDATE business_members SET membership_status = 'Suspended', updated_at = now()
    WHERE person_id = p_person_id AND role <> 'Owner' AND membership_status <> 'Suspended';
  ELSE
    UPDATE businesses SET business_status = 'Active', updated_at = now()
    WHERE owner_person_id = p_person_id AND business_status = 'Suspended';

    UPDATE business_members SET membership_status = 'Active', updated_at = now()
    WHERE person_id = p_person_id AND role <> 'Owner' AND membership_status = 'Suspended';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_apply_suspension(BIGINT, BOOLEAN) TO authenticated;

DROP FUNCTION IF EXISTS app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION app.support_upgrade_mlid_dispute(
  p_person_id BIGINT, p_corrected_aadhaar VARCHAR, p_reason VARCHAR
)
RETURNS TABLE(person_id BIGINT, old_mlid VARCHAR, new_mlid VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_old_mlid VARCHAR(13);
  v_gender_digit CHAR(1);
  v_new_mlid VARCHAR(13);
  v_conflicting_person BIGINT;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  SELECT mlid, gender_digit INTO v_old_mlid, v_gender_digit
  FROM persons WHERE persons.person_id = p_person_id;
  IF v_old_mlid IS NULL THEN
    RAISE EXCEPTION 'Person not found' USING ERRCODE = 'P0002';
  END IF;

  v_new_mlid := 'MLPI' || v_gender_digit || RIGHT(p_corrected_aadhaar, 8);

  SELECT persons.person_id INTO v_conflicting_person
  FROM persons WHERE persons.mlid = v_new_mlid AND persons.person_id <> p_person_id;
  IF v_conflicting_person IS NOT NULL THEN
    RAISE EXCEPTION 'Corrected Aadhaar already claimed by another person_id' USING ERRCODE = '23505';
  END IF;

  UPDATE persons
  SET mlid = v_new_mlid, mlid_type = 'MLPI', aadhaar_number = p_corrected_aadhaar, updated_at = now()
  WHERE persons.person_id = p_person_id;

  INSERT INTO person_id_history (person_id, old_mlid, new_mlid, reason)
  VALUES (p_person_id, v_old_mlid, v_new_mlid, p_reason);

  RETURN QUERY SELECT p_person_id, v_old_mlid, v_new_mlid;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- identity_documents (original-holder proof upload, called directly from
-- Dart via a plain table INSERT in aadhaar_dispute_state.dart, not an RPC)
-- has no RLS policy anywhere that would let a platform admin (who typically
-- holds NO business_members role, per this migration's own design note)
-- write another person's identity_documents row — 0012's existing policies
-- are self-write or business-partner-write only. Wrapping this in an RPC
-- too, gated the same way, so the Dart layer no longer needs any raw-table
-- write for this flow.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.support_upload_identity_document(
  p_person_id BIGINT, p_document_type identity_document_type_enum, p_file_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_document_id UUID;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  INSERT INTO identity_documents (person_id, document_type, file_url)
  VALUES (p_person_id, p_document_type, p_file_url)
  RETURNING document_id INTO v_document_id;

  RETURN v_document_id;
END;
$$;

COMMENT ON FUNCTION app.support_upload_identity_document(BIGINT, identity_document_type_enum, TEXT) IS
  'Closes a gap in 0028, which had the Dart layer INSERT into identity_documents directly for the original-holder proof path — that raw INSERT has no matching RLS policy for a platform-admin caller with no business_members row. Routed through this gated RPC instead.';

GRANT EXECUTE ON FUNCTION app.support_upload_identity_document(BIGINT, identity_document_type_enum, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- person_id_history read-back (fetchLatestIdHistoryEntry in the Dart layer)
-- also has no matching policy for a platform-admin caller: 0012's existing
-- policies on person_id_history are self-select or
-- is_owner_of_any_shared_business-select only, neither of which a platform
-- admin (no business_members row) satisfies. Wrapping in a gated RPC too,
-- rather than leaving a raw SELECT that would silently return zero rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.support_fetch_latest_id_history(p_person_id BIGINT)
RETURNS TABLE(old_mlid VARCHAR, new_mlid VARCHAR, reason VARCHAR, changed_at TIMESTAMP)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT h.old_mlid, h.new_mlid, h.reason, h.changed_at
  FROM person_id_history h
  WHERE h.person_id = p_person_id
  ORDER BY h.changed_at DESC
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_fetch_latest_id_history(BIGINT) TO authenticated;

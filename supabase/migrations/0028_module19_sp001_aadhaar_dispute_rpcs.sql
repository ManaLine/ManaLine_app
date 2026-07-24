-- =============================================================================
-- 0028 — Module 19: SP-001 Duplicate-Aadhaar Dispute Resolution RPCs
-- =============================================================================
-- SP-001's own spec (LOCKED 2026-07-19) confirms the Support/Admin tool is
-- "entirely separate internal tool/dashboard, outside the Owner/Agent/
-- Investor/Customer app; no MLID login, no app-side integration." Per
-- rls_role_matrix.md ("duplicate_suspects — no client policy at all;
-- Support-tool-only via service_role until that tool's own auth model
-- exists"), the same call is made here for the whole SP-001 surface: these
-- functions carry NO app.current_person_id()-style caller check (there is
-- no logged-in MLID session to check) and are GRANTed to service_role only,
-- never `authenticated`. The Support tool's own Supabase client must be
-- configured with the service_role key, not the anon/public key — that is
-- an infra assumption of this migration, flagged for master chat to confirm
-- the Support tool is deployed as a trusted internal app, not shipped to
-- end-user devices.
--
-- All five functions are still SECURITY DEFINER + locked search_path,
-- matching the rest of the codebase's RPC convention (see 0021/0027), even
-- though the caller-auth check itself is intentionally absent here.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Step 1: case-intake lookup by MLID or Aadhaar.
-- SPEC GAP (carried over from the stub file's own comment): SP-001 describes
-- the workflow, not a dedicated lookup endpoint. aadhaar_number is "stored
-- encrypted at app layer" (0001 comment) so it cannot be matched directly in
-- SQL; MLPI-type mlid values embed the Aadhaar last-8 digits by construction
-- (BR-181), so a search term is matched against mlid exactly OR against the
-- last-8-digit suffix of mlid. Flag for master chat / backend confirmation
-- if a different matching strategy is intended.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.support_lookup_person(VARCHAR);

CREATE OR REPLACE FUNCTION app.support_lookup_person(p_search VARCHAR)
RETURNS TABLE(person_id BIGINT, mlid VARCHAR, full_name VARCHAR)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT p.person_id, p.mlid, p.full_name
  FROM persons p
  WHERE p.mlid = p_search
     OR RIGHT(p.mlid, 8) = RIGHT(p_search, 8)
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION app.support_lookup_person(VARCHAR) TO service_role;

-- -----------------------------------------------------------------------------
-- Step 3 (pre-confirm): suspension-impact summary — every business the
-- person Owns (whole business, is_owner_business=true) plus every other-role
-- membership held elsewhere (membership only, is_owner_business=false), per
-- SP-001 FLOW 3a.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.support_suspension_impact(BIGINT);

CREATE OR REPLACE FUNCTION app.support_suspension_impact(p_person_id BIGINT)
RETURNS TABLE(id TEXT, label VARCHAR, role VARCHAR, is_owner_business BOOLEAN)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT b.business_id::TEXT, b.business_name, 'Owner'::VARCHAR, TRUE
  FROM businesses b
  WHERE b.owner_person_id = p_person_id
  UNION ALL
  SELECT bm.membership_id::TEXT, b.business_name, bm.role::VARCHAR, FALSE
  FROM business_members bm
  JOIN businesses b ON b.business_id = bm.business_id
  WHERE bm.person_id = p_person_id
    AND bm.role <> 'Owner';
$$;

GRANT EXECUTE ON FUNCTION app.support_suspension_impact(BIGINT) TO service_role;

-- -----------------------------------------------------------------------------
-- Step 3 (confirm) / Step 5: single atomic toggle — p_suspend=TRUE suspends
-- every owned business + every other-role membership; p_suspend=FALSE
-- reverses both back to Active, per SP-001 FLOW 3a/5 ("business_status ->
-- Suspended" / "-> Active", "membership status suspended" / unsuspended).
-- Only rows in the opposite state are touched, so re-running is idempotent.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.support_apply_suspension(BIGINT, BOOLEAN);

CREATE OR REPLACE FUNCTION app.support_apply_suspension(p_person_id BIGINT, p_suspend BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
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

GRANT EXECUTE ON FUNCTION app.support_apply_suspension(BIGINT, BOOLEAN) TO service_role;

-- -----------------------------------------------------------------------------
-- Step 5: POST /persons/{person_id}/upgrade-mlid, Support-mediated
-- "Aadhaar Correction — Dispute Resolution" variant (04_API_Specification_v1
-- _Part1.md §1.1, extended this session). person_id never changes — only
-- mlid/mlid_type update on the same row, so every existing FK stays intact
-- (BR-239). Re-runs the duplicate check (BR-228, simplified here to the
-- mlid-uniqueness constraint the corrected Aadhaar would produce) before
-- writing — if the corrected Aadhaar is already claimed by a DIFFERENT
-- person, raises 409-equivalent P0002 rather than silently overwriting,
-- exactly as the API spec's "routes to the SP-001 dispute flow instead of
-- silently overwriting" note describes for the general case (a person
-- disputing into an MLID that is itself already mid-dispute).
-- -----------------------------------------------------------------------------
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

GRANT EXECUTE ON FUNCTION app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR) TO service_role;
